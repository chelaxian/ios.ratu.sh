"""Offline protocol and CLI regression tests, also runnable on the phone."""
import contextlib
import importlib.machinery
import importlib.util
import io
import ipaddress
from pathlib import Path
import socket
import struct
import sys
import threading
import unittest
from unittest.mock import patch

source = Path(__file__).parent / 'layout/usr/bin/isdig'
if not source.exists():
    source = Path('/var/jb/usr/bin/isdig')
loader = importlib.machinery.SourceFileLoader('isdig', str(source))
spec = importlib.util.spec_from_loader(loader.name, loader)
dns = importlib.util.module_from_spec(spec)
loader.exec_module(dns)


def answer(query, flags=0x8180):
    return (query[:2] + struct.pack('!HHHHH', flags, 1, 1, 0, 0) + query[12:] +
            b'\xc0\x0c' + struct.pack('!HHIH', 1, 1, 60, 4) + b'\xc0\x00\x02\x01')


class ProtocolTests(unittest.TestCase):
    def cli(self, *args):
        out, err = io.StringIO(), io.StringIO()
        with patch.object(sys, 'argv', ['isdig', *args]), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            try:
                code = dns.main()
            except SystemExit as e:
                code = e.code
        return code, out.getvalue(), err.getvalue()

    def test_idna_and_root(self):
        self.assertIn(b'xn--', dns.build_query('пример.рф', 1))
        self.assertEqual(dns.build_query('.', 1)[12:], b'\0\0\1\0\1')

    def test_bad_names(self):
        for name in ['a' * 64 + '.com', 'a..com', '.com', '.'.join(['a' * 63] * 4)]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                dns.build_query(name, 1)

    def test_compressed_answer(self):
        result = dns.parse_response(answer(dns.build_query('example.com', 1, txid=7)), 7)
        self.assertEqual(result['answers'][0]['data'], '192.0.2.1')

    def test_malformed_packets(self):
        for packet in [None, b'', b'\0' * 11, b'\0' * 12]:
            with self.subTest(packet=packet), self.assertRaises(ValueError):
                dns.parse_response(packet)
        query = dns.build_query('example.com', 1, txid=7)
        with self.assertRaises(ValueError):
            dns.parse_response(answer(query), 8)
        with self.assertRaises(ValueError):
            dns.parse_response(answer(query)[:-1], 7)

    def test_compression_loop(self):
        with self.assertRaises(ValueError):
            dns.parse_name(b'\xc0\x00', 0)

    def test_srv_and_txt(self):
        srv = struct.pack('!HHH', 10, 20, 443) + b'\x03www\x07example\x03com\0'
        self.assertEqual(dns.parse_rdata(srv, 0, 33, len(srv)), '10 20 443 www.example.com')
        self.assertEqual(dns.parse_rdata(b'\x02ab\x02cd', 0, 16, 6), 'abcd')
        with self.assertRaises(ValueError):
            dns.parse_rdata(b'\x05ab', 0, 16, 3)

    def test_servers(self):
        for spec, transport, host, port in [
            ('@1.1.1.1:5353', 'udp', '1.1.1.1', 5353),
            ('@::1', 'udp', '::1', 53),
            ('@tcp://[::1]:5353', 'tcp', '::1', 5353),
            ('@tls://dns.google', 'dot', 'dns.google', 853),
        ]:
            self.assertEqual(dns.parse_server(spec)[:3], (transport, host, port))

    def test_reverse_v6(self):
        with patch.object(dns, 'query_udp', side_effect=lambda h, p, q, **kw: answer(q)) as query:
            code, _, _ = self.cli('@127.0.0.1', '-x', '2001:4860:4860::8888', '+json')
        self.assertEqual(code, 0)
        self.assertEqual(dns.parse_name(query.call_args.args[2], 12)[0],
                         ipaddress.ip_address('2001:4860:4860::8888').reverse_pointer)

    def test_bad_cli(self):
        for args in [('example.com', '+trace'), ('example.com', '-t', 'BOGUS'),
                     ('-x', 'bad-ip'), ('example.com', '--timeout', '0'),
                     ('example.com', '+nonsense')]:
            with self.subTest(args=args):
                self.assertEqual(self.cli(*args)[0], 2)

    def test_no_hidden_fallback(self):
        with patch('builtins.open', side_effect=FileNotFoundError):
            with self.assertRaises(ValueError):
                dns.default_server()

    def test_tcp_fallback_from_incomplete_udp(self):
        query = dns.build_query('example.com', 1, txid=7)
        truncated = query[:2] + struct.pack('!HHHHH', 0x8380, 1, 1, 0, 0)
        with patch.object(dns, 'build_query', return_value=query), \
                patch.object(dns, 'query_udp', return_value=truncated), \
                patch.object(dns, 'query_tcp', return_value=answer(query)) as tcp:
            code, out, _ = self.cli('@127.0.0.1', 'example.com', '+json')
        self.assertEqual(code, 0)
        self.assertIn('"transport": "tcp"', out)
        tcp.assert_called_once()

    def test_live_local_udp_and_tcp(self):
        for transport in ['udp', 'tcp']:
            with self.subTest(transport=transport):
                kind = socket.SOCK_DGRAM if transport == 'udp' else socket.SOCK_STREAM
                server = socket.socket(socket.AF_INET, kind)
                server.bind(('127.0.0.1', 0))
                server.settimeout(5)
                port = server.getsockname()[1]
                if transport == 'tcp':
                    server.listen(1)
                errors = []
                def serve():
                    try:
                        if transport == 'udp':
                            query, peer = server.recvfrom(65535)
                            server.sendto(answer(query), peer)
                        else:
                            conn, _ = server.accept()
                            with conn:
                                length = struct.unpack('!H', dns.recv_exact(conn, 2))[0]
                                query = dns.recv_exact(conn, length)
                                response = answer(query)
                                # Exercise recv_exact with fragmented framing.
                                for part in [struct.pack('!H', len(response))[:1], struct.pack('!H', len(response))[1:], response]:
                                    conn.sendall(part)
                    except Exception as e:
                        errors.append(e)
                    finally:
                        server.close()
                worker = threading.Thread(target=serve, daemon=True)
                worker.start()
                prefix = '@' if transport == 'udp' else '@tcp://'
                code, out, err = self.cli(prefix + '127.0.0.1:' + str(port), 'example.com', '+short')
                worker.join(6)
                self.assertFalse(errors, errors)
                self.assertEqual((code, out.strip()), (0, '192.0.2.1'), err)


if __name__ == '__main__':
    unittest.main(verbosity=2)
