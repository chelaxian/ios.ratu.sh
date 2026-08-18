#!/usr/bin/env python3
"""EtcHosts17 local DNS override daemon.

Architecture (iOS 17 RootHide, APFS sealed system volume):
  The real /etc/hosts lives on the sealed (SSV) system volume and can never be
  edited, and mDNSResponder is a non-injectable platform binary. The only DNS
  override mechanism that is visible and enforceable in Settings on this device
  is an installed configuration profile (com.apple.dnsSettings.managed), exactly
  like the NextDNS/AdGuard/ControlD encrypted-DNS profiles already present. A
  managed encrypted-DNS profile outranks anything written to
  State:/Network/.../DNS, so the old SCDynamicStore redirect alone cannot beat
  an active DoH resolver.

  So this daemon is a small local resolver that speaks both DNS-over-TLS (DoT,
  :853) and DNS-over-HTTPS (DoH, :8443), presenting a certificate signed by a
  per-device CA. A generated .mobileconfig bundles that CA (as a trusted root
  payload) plus a scoped managed-DNS payload whose SupplementalMatchDomains list
  exactly the overridden hosts. Once the profile is installed and the user
  enables it once in Settings, iOS routes ONLY those names to this daemon over
  the chosen encrypted transport -- winning over ControlD DoH and VPN DNS for
  the listed hosts -- while every other name keeps its normal path through the
  primary resolver. That is the /etc/hosts parity we want.

  Two profile modes:
    - block:    matched hosts are answered from the hosts map (0.0.0.0 etc.).
    - upstream: matched hosts are forwarded to a real upstream DoT server
                (ProfileUpstream, e.g. dns.google) instead of the static map --
                the host is still routed to us (so we win over DoH/VPN for it)
                but resolved through a chosen upstream rather than a static IP.

  The daemon also still listens on UDP/TCP :53 so the SCDynamicStore redirect
  (secondary mechanism, for networks with only plain DNS) keeps working.

  The daemon serves the freshly-generated .mobileconfig over a localhost HTTP
  port so the Settings bundle can hand the user straight into the install sheet.

Persistence rule: this daemon is READ-ONLY with respect to
com.ratush.etchosts17.plist. Only the Settings bundle writes that file
(presets, toggles, HostsText). The daemon reads it and only writes runtime
caches (daemon.hosts, hosts.merged). This keeps custom presets and toggles from
being collapsed/reset on respring or reinstall.
"""
import argparse
import base64
import ipaddress
import os
import plistlib
import queue
import re
import select
import socket
import struct
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

# `ssl` is imported once when the DoT/DoH listener first starts (the listeners
# are now unconditional at daemon boot, so this happens early but off the UDP :53
# hot path). Keeping it out of module top-level avoids paying the OpenSSL import
# cost before the daemon has bound its critical :53 socket.
ssl = None


JBROOT_DIR = "/var/mobile/Library/EtcHosts17"
JBROOT_MERGED = JBROOT_DIR + "/hosts.merged"
JBROOT_PREFS = "/var/mobile/Library/Preferences/com.ratush.etchosts17.plist"
# Rootless has one real mobile data namespace.  Keep legacy variable aliases so
# the proven daemon logic remains intact without writing a RootHide mirror.
ROOTFS_DIR = JBROOT_DIR
ROOTFS_MERGED = JBROOT_MERGED
ROOTFS_PREFS = JBROOT_PREFS
DAEMON_HOSTS = JBROOT_DIR + "/daemon.hosts"
UPSTREAMS_FILE = JBROOT_DIR + "/upstreams"
BASE_HOSTS = "/etc/hosts"

TLS_DIR = JBROOT_DIR + "/tls"
CA_DER = TLS_DIR + "/ca.der"
SERVER_CERT = TLS_DIR + "/server.pem"
SERVER_KEY = TLS_DIR + "/server.key"

PREFS_HOSTS_KEY = "HostsText"
PREFS_ENABLED_KEY = "Enabled"
PREFS_GLOBAL_KEY = "GlobalMode"
PREFS_FALLBACK_KEY = "FallbackSystemDNS"
PREFS_CREATE_PROFILE_KEY = "CreateDNSProfile"
PREFS_USE_PROFILE_KEY = "UseDNSProfile"
PREFS_SELECTED_PRESET_KEY = "SelectedPreset"
# Profile mode controls how matched hosts are answered:
#   "block"    -> answer from the hosts map (0.0.0.0 etc.) — default /etc/hosts behaviour
#   "upstream" -> forward matched hosts to a real upstream DoT server (ProfileUpstream)
PREFS_PROFILE_MODE_KEY = "ProfileMode"
PREFS_PROFILE_UPSTREAM_KEY = "ProfileUpstream"   # e.g. "dns.google" (DoT server name)
PREFS_PROFILE_TRANSPORT_KEY = "ProfileTransport"  # "tls" or "https"

CONTROL_MAGIC = b"ETCHOSTS17\n"
CONTROL_APPLY_MAGIC = b"ETCHOSTS17APPLY\n"
CONTROL_PORT = 53535
DOT_PORT = 853
PROFILE_HTTP_PORT = 53580
PROFILE_SERVER_NAME = "etchosts17.local"
PROFILE_ID = "com.ratush.etchosts17.dns"
PROFILE_FILENAME = "EtcHosts17.mobileconfig"
# A few well-known public DoT endpoints offered as presets in the UI. Any valid
# DoT ServerName works; these are convenience shortcuts.
PROFILE_UPSTREAM_PRESETS = [
    ("dns.google", "Google Public DNS (dns.google)"),
    ("1.1.1.1", "Cloudflare (1.1.1.1)"),
    ("9.9.9.9", "Quad9 (9.9.9.9)"),
    ("dns.adguard.com", "AdGuard (dns.adguard.com)"),
    ("dns.quad9.net", "Quad9 TLS name (dns.quad9.net)"),
]

DEFAULT_EXTRA = (
    "# EtcHosts17 supplemental entries\n"
    "127.0.0.1 localhost\n"
    "# Examples:\n"
    "# 0.0.0.0 example.com other.example.com\n"
    "# ::1 ipv6.example.com\n"
)
UPSTREAMS = ["9.9.9.9", "1.1.1.1", "8.8.8.8"]


def read_upstreams():
    """Real resolvers captured by etchosts17resolv (the VPN's own DNS included),
    so forwarding non-overridden queries works under a VPN. Falls back to the
    public defaults if nothing was captured yet."""
    try:
        with open(UPSTREAMS_FILE, "r", encoding="utf-8", errors="ignore") as handle:
            servers = [line.strip() for line in handle if line.strip()]
        servers = [s for s in servers if not s.startswith("127.") and s not in ("::1", "0.0.0.0")]
        # Keep the public defaults as a last-resort tail so DNS never dead-ends.
        for d in UPSTREAMS:
            if d not in servers:
                servers.append(d)
        return servers or UPSTREAMS
    except OSError:
        return UPSTREAMS

IPV4_RE = re.compile(r"^[0-9]{1,3}(\.[0-9]{1,3}){3}$")
DOMAIN_RE = re.compile(
    r"^[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?"
    r"(\.[A-Za-z0-9_]([A-Za-z0-9_-]{0,61}[A-Za-z0-9_])?)*\.?$"
)


def log(message):
    sys.stderr.write(time.strftime("%Y-%m-%d %H:%M:%S ") + message + "\n")
    sys.stderr.flush()


def ensure_storage():
    for path in (ROOTFS_DIR, JBROOT_DIR):
        try:
            os.makedirs(path, exist_ok=True)
            os.chmod(path, 0o755)
        except OSError:
            pass


def read_text(path):
    with open(path, "r", encoding="utf-8", errors="ignore") as handle:
        return handle.read()


def write_text(path, text, mode=0o644):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as handle:
        handle.write(text)
    if path.startswith("/var/mobile/") or path.startswith("/rootfs/private/var/mobile/"):
        try:
            os.chown(tmp, 501, 501)
        except OSError:
            pass
    os.chmod(tmp, mode)
    os.replace(tmp, path)


def read_plist_dict(path):
    with open(path, "rb") as handle:
        value = plistlib.load(handle)
    return value if isinstance(value, dict) else {}


def canonical_prefs_path():
    """Pick the canonical preferences plist for reading tweak state.

    The jbroot copy (``/var/mobile/Library/Preferences/...``) is authoritative:
    it is the file the tweak's Settings bundle writes, and iOS ``cfprefsd`` does
    not roam it. The rootfs copy (``/rootfs/private/var/mobile/...``) is mirrored
    by the UI for compatibility, but ``cfprefsd`` owns that domain and can flush
    a *stale* in-memory cache back to disk with a newer mtime — which previously
    defeated the "newest mtime wins" heuristic (Enabled=False overrode the real
    Enabled=True and silently disabled all host overrides). Prefer jbroot, fall
    back to rootfs only when jbroot is absent."""
    if os.path.exists(JBROOT_PREFS):
        return JBROOT_PREFS
    if os.path.exists(ROOTFS_PREFS):
        return ROOTFS_PREFS
    return None


# Kept for compatibility with any caller that still resolves "the newest prefs".
def newest_prefs_path():
    return canonical_prefs_path()


def read_settings():
    settings = {
        PREFS_ENABLED_KEY: True,
        PREFS_USE_PROFILE_KEY: False,
        PREFS_PROFILE_MODE_KEY: "block",
        PREFS_PROFILE_UPSTREAM_KEY: "dns.google",
        PREFS_PROFILE_TRANSPORT_KEY: "tls",
    }
    path = newest_prefs_path()
    if path:
        try:
            prefs = read_plist_dict(path)
            for key in (PREFS_ENABLED_KEY, PREFS_USE_PROFILE_KEY):
                if isinstance(prefs.get(key), bool):
                    settings[key] = prefs[key]
            mode = prefs.get(PREFS_PROFILE_MODE_KEY)
            if isinstance(mode, str) and mode in ("block", "upstream"):
                settings[PREFS_PROFILE_MODE_KEY] = mode
            upstream = prefs.get(PREFS_PROFILE_UPSTREAM_KEY)
            if isinstance(upstream, str) and upstream.strip():
                settings[PREFS_PROFILE_UPSTREAM_KEY] = upstream.strip()
            transport = prefs.get(PREFS_PROFILE_TRANSPORT_KEY)
            if isinstance(transport, str) and transport in ("tls", "https"):
                settings[PREFS_PROFILE_TRANSPORT_KEY] = transport
        except Exception as exc:
            log("cannot read settings: %s" % exc)
    return settings


def read_hosts_text():
    """Read the active hosts text. Read-only.

    Canonical source order:
      1. The jbroot prefs plist (cfprefsd does not roam it; the Settings UI
         writes here, so it reflects the user's actual editor content).
      2. ``daemon.hosts`` (a runtime cache we keep in sync; used as a fallback
         when the plist is briefly unavailable).
      3. The rootfs prefs plist (last resort — cfprefsd may leave it stale).

    The previous implementation picked whichever of these had the newest mtime,
    but cfprefsd can flush a stale in-memory cache to the rootfs copy with a
    fresh mtime and win the race, silently disabling overrides. Explicit
    canonical order avoids that."""
    canonical = canonical_prefs_path()
    if canonical:
        try:
            value = read_plist_dict(canonical).get(PREFS_HOSTS_KEY)
            if isinstance(value, str) and value.strip():
                return value
        except Exception as exc:
            log("cannot read hosts from %s: %s" % (canonical, exc))
    if os.path.exists(DAEMON_HOSTS):
        try:
            text = read_text(DAEMON_HOSTS)
            if text and text.strip():
                return text
        except Exception as exc:
            log("cannot read hosts from %s: %s" % (DAEMON_HOSTS, exc))
    # Last resort: the rootfs prefs copy, if it is the only thing that exists.
    if canonical != ROOTFS_PREFS and os.path.exists(ROOTFS_PREFS):
        try:
            value = read_plist_dict(ROOTFS_PREFS).get(PREFS_HOSTS_KEY)
            if isinstance(value, str) and value.strip():
                return value
        except Exception as exc:
            log("cannot read hosts from %s: %s" % (ROOTFS_PREFS, exc))
    return DEFAULT_EXTRA


def normalize_hosts_text(text):
    value = (text or "").replace("\r\n", "\n").replace("\r", "\n")
    if value and not value.endswith("\n"):
        value += "\n"
    return value


def valid_ip_literal(value):
    if "." in value and ":" not in value and not IPV4_RE.match(value):
        return False
    try:
        ipaddress.ip_address(value)
        return True
    except ValueError:
        return False


def validation_errors(text):
    errors = []
    for index, raw_line in enumerate(normalize_hosts_text(text).splitlines(), start=1):
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2:
            errors.append("line %d: use 'IP hostname [hostname ...]'" % index)
            continue
        if not valid_ip_literal(parts[0]):
            errors.append("line %d: invalid IP address %r" % (index, parts[0]))
            continue
        for domain in parts[1:]:
            if not DOMAIN_RE.match(domain):
                errors.append("line %d: invalid hostname %r" % (index, domain))
    return errors


def validated_hosts_text(text):
    value = normalize_hosts_text(text)
    errors = validation_errors(value)
    if errors:
        raise ValueError("; ".join(errors))
    return value


def parse_hosts_text(text):
    hosts = {}
    for raw_line in normalize_hosts_text(text).splitlines():
        line = raw_line.split("#", 1)[0].strip()
        if not line:
            continue
        parts = line.split()
        if len(parts) < 2 or not valid_ip_literal(parts[0]):
            continue
        address = ipaddress.ip_address(parts[0])
        for name in parts[1:]:
            hosts.setdefault(name.rstrip(".").lower(), []).append(address)
    return hosts


def hostnames_from_text(text):
    names = []
    seen = set()
    for host in parse_hosts_text(text):
        if host not in seen:
            seen.add(host)
            names.append(host)
    return names


def build_merged(extra, enabled):
    try:
        base = read_text(BASE_HOSTS)
    except OSError:
        base = "127.0.0.1 localhost\n255.255.255.255 broadcasthost\n::1 localhost\n"
    if base and not base.endswith("\n"):
        base += "\n"
    if enabled:
        return base + "\n# EtcHosts17 supplemental entries begin\n" + extra + "# EtcHosts17 supplemental entries end\n"
    return base


def sync_caches():
    """Write only runtime caches. Never touches the preferences plist."""
    ensure_storage()
    text = read_hosts_text()
    try:
        text = validated_hosts_text(text)
    except ValueError as exc:
        log("invalid hosts text, using default: %s" % exc)
        text = DEFAULT_EXTRA
    enabled = read_settings().get(PREFS_ENABLED_KEY, True)
    try:
        write_text(DAEMON_HOSTS, text)
        merged = build_merged(text, enabled)
        write_text(ROOTFS_MERGED, merged)
        write_text(JBROOT_MERGED, merged)
    except OSError as exc:
        log("cache write failed: %s" % exc)
    return text


# ---------------------------------------------------------------------------
# DNS wire helpers
# ---------------------------------------------------------------------------

def parse_question(packet):
    if len(packet) < 12:
        return None
    offset = 12
    labels = []
    while offset < len(packet):
        length = packet[offset]
        offset += 1
        if length == 0:
            break
        if length & 0xC0 or offset + length > len(packet):
            return None
        labels.append(packet[offset:offset + length].decode("ascii", "ignore"))
        offset += length
    if offset + 4 > len(packet):
        return None
    qtype, qclass = struct.unpack("!HH", packet[offset:offset + 4])
    return ".".join(labels).lower(), qtype, qclass, offset + 4


def empty_response(packet, question_end):
    return packet[:2] + b"\x81\x80\x00\x01\x00\x00\x00\x00\x00\x00" + packet[12:question_end]


def answer_response(packet, question_end, address):
    rtype = 1 if address.version == 4 else 28
    answer = (
        b"\xc0\x0c"
        + struct.pack("!HHI", rtype, 1, 60)
        + struct.pack("!H", len(address.packed))
        + address.packed
    )
    return packet[:2] + b"\x81\x80\x00\x01\x00\x01\x00\x00\x00\x00" + packet[12:question_end] + answer


# ---------------------------------------------------------------------------
# Upstream DoT resolver (for "upstream" profile mode: matched hosts are
# forwarded to a real DoT server instead of being answered from the map)
# ---------------------------------------------------------------------------

def forward_dot(packet, server_name, timeout=4.0):
    """Forward a single DNS query to an upstream DoT server by name.

    Resolves ServerName to an IP, opens a TLS 1.2+ connection on :853, sends the
    length-prefixed query, and returns the raw response. Best-effort: on any
    failure returns None so the caller can fall back to an empty response."""
    if not server_name:
        return None
    try:
        infos = socket.getaddrinfo(server_name, 853, socket.AF_INET, socket.SOCK_STREAM)
        addr = infos[0][4]
    except OSError:
        return None
    if ssl is None:
        return None
    try:
        raw = socket.create_connection(addr, timeout=timeout)
        raw.settimeout(timeout)
        context = ssl.create_default_context()
        context.check_hostname = True
        context.verify_mode = ssl.CERT_REQUIRED
        tls = context.wrap_socket(raw, server_hostname=server_name)
        try:
            tls.sendall(struct.pack("!H", len(packet)) + packet)
            header = recv_exact(tls, 2)
            if not header:
                return None
            (length,) = struct.unpack("!H", header)
            return recv_exact(tls, length)
        finally:
            try:
                tls.close()
            except OSError:
                pass
    except (OSError, ssl.SSLError):
        return None


def forward_matched(packet):
    """How a *matched* (listed) host is resolved in profile mode.

    - block mode: answered from the hosts map (caller already handles this).
    - upstream mode: forwarded to the configured upstream DoT server so the
      matched name resolves through a real resolver instead of the override.
    Returns raw DNS bytes, or None if no answer."""
    mode = STATE.get("mode", "block")
    if mode != "upstream":
        return None
    upstream = STATE.get("upstream") or "dns.google"
    return forward_dot(packet, upstream, timeout=4.0)


def forward(packet, upstreams, timeout=2.0):
    """Query ALL upstreams in parallel over UDP; return the first reply.

    The daemon sits in the path of every DNS query (the global redirect), so a
    slow or dead upstream must never stall resolution. Firing all upstreams at
    once and taking the first answer bounds every miss to `timeout`, instead of
    the old sequential up-to-3s-per-upstream walk that froze all DNS."""
    socks = []
    for upstream in upstreams:
        family = socket.AF_INET6 if ":" in upstream else socket.AF_INET
        try:
            sock = socket.socket(family, socket.SOCK_DGRAM)
            sock.setblocking(False)
            sock.sendto(packet, (upstream, 53))
            socks.append(sock)
        except OSError:
            try:
                sock.close()
            except Exception:
                pass
    if not socks:
        return None
    deadline = time.monotonic() + timeout
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return None
            try:
                ready, _, _ = select.select(socks, [], [], remaining)
            except OSError:
                return None
            if not ready:
                return None
            for sock in ready:
                try:
                    response, _ = sock.recvfrom(4096)
                    return response
                except OSError:
                    pass
    finally:
        for sock in socks:
            try:
                sock.close()
            except Exception:
                pass


def forward_tcp(message, upstreams, timeout=3.0):
    """Forward a query to an upstream over TCP (used for TCP:53 clients, so a
    truncated UDP answer is never handed back on a TCP connection)."""
    for upstream in upstreams:
        family = socket.AF_INET6 if ":" in upstream else socket.AF_INET
        sock = socket.socket(family, socket.SOCK_STREAM)
        sock.settimeout(timeout)
        try:
            sock.connect((upstream, 53))
            sock.sendall(struct.pack("!H", len(message)) + message)
            header = recv_exact(sock, 2)
            if not header:
                continue
            (length,) = struct.unpack("!H", header)
            resp = recv_exact(sock, length)
            if resp:
                return resp
        except OSError:
            pass
        finally:
            try:
                sock.close()
            except OSError:
                pass
    return None


def handle_query(packet, forwarder=None):
    """Resolve one DNS query packet. Returns the response bytes (or None).

    `forwarder(packet) -> bytes|None` overrides how non-listed names are
    forwarded (UDP by default; TCP for TCP:53 clients)."""
    parsed = parse_question(packet)
    if not parsed:
        return None
    name, qtype, _qclass, qend = parsed

    # Suppress DDR so mDNSResponder does not auto-upgrade to an encrypted
    # designated resolver that would bypass this daemon.
    if name.endswith("resolver.arpa"):
        return empty_response(packet, qend)

    addresses = STATE["hosts"].get(name)
    if addresses:
        # Upstream mode: forward the matched host to a real DoT resolver instead
        # of answering from the override map. This is the "non-blocking profile"
        # path: the host is still routed to us (so we win over DoH/VPN for it),
        # but resolved through a chosen upstream rather than a static address.
        if STATE.get("mode") == "upstream":
            response = forward_matched(packet)
            if response:
                return response
            # Upstream failed: fall through to the static override so the user
            # never gets NXDOMAIN for a host they explicitly listed.
        match = None
        for address in addresses:
            if (qtype == 1 and address.version == 4) or (qtype == 28 and address.version == 6):
                match = address
                break
        if match:
            return answer_response(packet, qend, match)
        # A/AAAA of the other family, or HTTPS/SVCB: answer NODATA so no real
        # address (or ipv4hint) leaks for an overridden host.
        return empty_response(packet, qend)

    # Not overridden -> forward it (additive /etc/hosts semantics: only listed
    # names are overridden, everything else resolves normally). To block a name,
    # map it to 0.0.0.0 in the editor.
    if forwarder is None:
        forwarder = lambda pkt: forward(pkt, STATE.get("upstreams") or UPSTREAMS)
    response = forwarder(packet)
    return response if response else empty_response(packet, qend)


# ---------------------------------------------------------------------------
# DNS-over-TLS listener (the profile points scoped domains here)
# ---------------------------------------------------------------------------

def recv_exact(sock, count):
    chunks = []
    while count > 0:
        chunk = sock.recv(count)
        if not chunk:
            return None
        chunks.append(chunk)
        count -= len(chunk)
    return b"".join(chunks)


def dot_connection(tls):
    try:
        while True:
            header = recv_exact(tls, 2)
            if not header:
                break
            (length,) = struct.unpack("!H", header)
            message = recv_exact(tls, length)
            if not message:
                break
            response = handle_query(message)
            if response is None:
                continue
            tls.sendall(struct.pack("!H", len(response)) + response)
    except (OSError, ssl.SSLError):
        pass
    finally:
        try:
            tls.close()
        except OSError:
            pass


def dot_server():
    """DNS-over-TLS listener on :853.

    Started UNCONDITIONALLY at daemon boot (not only in profile mode). The scoped
    managed-DNS profile routes matched hosts here over TLS; without this listener
    the profile has nothing to talk to and DNS for those hosts just times out.
    Being always-on means enabling the profile in Settings immediately works,
    without needing a daemon restart or a toggle flip."""
    global ssl
    if ssl is None:
        import ssl as _ssl_mod  # lazy: OpenSSL bindings pulled in once at boot
        ssl = _ssl_mod
    if not (os.path.exists(SERVER_CERT) and os.path.exists(SERVER_KEY)):
        log("DoT listener disabled: no certificate at %s" % SERVER_CERT)
        return
    try:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(SERVER_CERT, SERVER_KEY)
    except Exception as exc:
        log("DoT listener disabled: cannot load cert: %s" % exc)
        return
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        bind_with_retry(listener, ("0.0.0.0", DOT_PORT))
    except OSError as exc:
        log("DoT listener bind failed: %s" % exc)
        return
    listener.listen(32)
    log("EtcHosts17 DoT listener on 0.0.0.0:%d" % DOT_PORT)
    while True:
        try:
            client, _addr = listener.accept()
        except OSError:
            continue
        try:
            tls = context.wrap_socket(client, server_side=True)
        except (OSError, ssl.SSLError):
            try:
                client.close()
            except OSError:
                pass
            continue
        threading.Thread(target=dot_connection, args=(tls,), daemon=True).start()


# ---------------------------------------------------------------------------
# DNS-over-HTTPS listener (RFC 8484) — alternative profile transport
# ---------------------------------------------------------------------------

# A scoped managed-DNS profile can use DoH instead of DoT. Some networks middlebox
# :853 (DoT) while :443/DoH passes; offering both lets the user pick what works.
DOH_PORT = 8443
DOH_PATH = "/dns-query"


class _DoHHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def _serve_query(self, message):
        if not message:
            self.send_error(400, "bad message")
            return
        response = handle_query(message)
        if response is None:
            self.send_error(502, "no answer")
            return
        body = response
        self.send_response(200)
        self.send_header("Content-Type", "application/dns-message")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_POST(self):  # noqa: N802
        if self.path != DOH_PATH:
            self.send_error(404, "not found")
            return
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0 or length > 65535:
            self.send_error(400, "bad length")
            return
        message = self.rfile.read(length)
        ctype = (self.headers.get("Content-Type") or "").lower()
        if ctype == "application/dns-json":
            self.send_error(415, "json wire format unsupported; use application/dns-message")
            return
        self._serve_query(message)

    def do_GET(self):  # noqa: N802 — RFC 8484 GET with ?dns= base64url
        if self.path.startswith(DOH_PATH + "?"):
            from urllib.parse import urlparse, parse_qs
            qs = parse_qs(urlparse(self.path).query)
            encoded = (qs.get("dns") or qs.get("DNS") or [""])[0]
            # base64url decode, accept missing padding
            pad = "=" * (-len(encoded) % 4)
            try:
                import base64 as _b64
                message = _b64.urlsafe_b64decode(encoded + pad)
            except (ValueError, TypeError):
                self.send_error(400, "bad dns param")
                return
            self._serve_query(message)
            return
        self.send_error(404, "not found")

    def log_message(self, *args):
        return


def doh_server():
    """DoH (RFC 8484) listener over TLS on :8443.

    The managed-DNS DoH profile uses ServerURL, so the certificate's SAN must match
    the host part of that URL. We always listen on the same per-device cert as DoT
    (etchosts17.local); the profile's ServerURL is built to match. A fresh accept
    loop hands each TLS connection to a thread running a BaseHTTPRequestHandler —
    simpler than fighting ThreadingHTTPServer's bind-its-own-socket assumption."""
    global ssl
    if ssl is None:
        try:
            import ssl as _ssl_mod
            ssl = _ssl_mod
        except ImportError:
            log("DoH listener disabled: no ssl module")
            return
    if not (os.path.exists(SERVER_CERT) and os.path.exists(SERVER_KEY)):
        log("DoH listener disabled: no certificate at %s" % SERVER_CERT)
        return
    try:
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(SERVER_CERT, SERVER_KEY)
    except Exception as exc:
        log("DoH listener disabled: cannot load cert: %s" % exc)
        return
    listener = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        bind_with_retry(listener, ("0.0.0.0", DOH_PORT))
    except OSError as exc:
        log("DoH listener bind failed: %s" % exc)
        return
    listener.listen(32)
    log("EtcHosts17 DoH listener on 0.0.0.0:%d%s" % (DOH_PORT, DOH_PATH))

    def serve_connection(conn):
        # Reuse the stdlib request handler over an already-wrapped TLS socket.
        class _Channel(_DoHHandler):
            pass
        try:
            _Channel(conn, ("127.0.0.1", DOH_PORT), None)
        except (OSError, ssl.SSLError, ValueError, BrokenPipeError):
            pass
        finally:
            try:
                conn.close()
            except OSError:
                pass

    while True:
        try:
            client, _addr = listener.accept()
        except OSError:
            continue
        try:
            tls = context.wrap_socket(client, server_side=True)
        except (OSError, ssl.SSLError):
            try:
                client.close()
            except OSError:
                pass
            continue
        threading.Thread(target=serve_connection, args=(tls,), daemon=True).start()


# ---------------------------------------------------------------------------
# .mobileconfig generation + localhost delivery
# ---------------------------------------------------------------------------

def local_interface_ip():
    try:
        probe = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        probe.connect(("1.1.1.1", 53))
        ip = probe.getsockname()[0]
        probe.close()
        return ip
    except OSError:
        return None


def _det_uuid(tag):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, "etchosts17." + tag)).upper()


def build_profile_data():
    """Generate the scoped managed-DNS .mobileconfig from the current override hosts.

    Two transports are supported, chosen by the user in Settings:
      - DoT: DNSProtocol=TLS, ServerName=etchosts17.local, ServerAddresses=[en0_ip, 127.0.0.1]
      - DoH: DNSProtocol=HTTPS, ServerURL=https://etchosts17.local:<DOH_PORT>/dns-query

    CRITICAL: ServerAddresses MUST include a non-loopback IP (the live en0 IP).
    iOS mDNSResponder silently ignores loopback (127.0.0.1) as a DoT/DoH server
    address in a managed-DNS profile — verified on this device (v0.6.0): with
    ServerAddresses=[127.0.0.1] only, 0 packets ever reached :853 even with the
    profile enabled in Settings and the DNS cache flushed. Adding the en0 IP makes
    iOS actually open the DoT connection. The en0 IP is dynamic, so the profile
    is rebuilt whenever the watcher detects a network change.

    Either way the profile is scoped (SupplementalMatchDomains) to ONLY the listed
    hosts, so everything else keeps using the primary resolver (ControlD/VPN/etc).
    The CA is bundled as a trusted root so iOS trusts the per-device cert without
    a manual "Full Trust" step."""
    match = [h for h in STATE["hosts"].keys() if h != "localhost"]
    match.sort()
    # CRITICAL: iOS ignores loopback (127.0.0.1) as a managed-DNS server address.
    # We MUST include the live en0 IP so mDNSResponder actually opens a DoT/DoH
    # connection to the daemon. The daemon listens on 0.0.0.0 so it accepts the
    # en0 IP. 127.0.0.1 is kept as a fallback tail (harmless if the en0 IP is
    # unreachable, e.g. right after a network switch before the profile rebuild).
    en0 = local_interface_ip()
    servers = []
    if en0 and not en0.startswith("127."):
        servers.append(en0)
    servers.append("127.0.0.1")

    try:
        with open(CA_DER, "rb") as handle:
            ca_der = handle.read()
    except OSError:
        ca_der = b""

    transport = STATE.get("transport", "tls")   # "tls" or "https"

    cert_payload = {
        "PayloadType": "com.apple.security.root",
        "PayloadVersion": 1,
        "PayloadIdentifier": PROFILE_ID + ".ca",
        "PayloadUUID": _det_uuid("ca"),
        "PayloadDisplayName": "EtcHosts17 Local CA",
        "PayloadDescription": "Trusts the local EtcHosts17 encrypted-DNS resolver.",
        "PayloadCertificateFileName": "EtcHosts17CA.cer",
        "PayloadContent": ca_der,
    }

    dns_settings = {}
    if transport == "https":
        # DoH ServerURL must use the IP (etchosts17.local does not resolve
        # publicly, and iOS does not use a separate resolver to look it up).
        # The cert's SAN must therefore include the en0 IP too (postinst adds it
        # on fresh installs; on upgrade the user re-taps Create profile once).
        doh_host = en0 if (en0 and not en0.startswith("127.")) else PROFILE_SERVER_NAME
        dns_settings = {
            "DNSProtocol": "HTTPS",
            "ServerURL": "https://%s:%d%s" % (doh_host, DOH_PORT, DOH_PATH),
            "ServerAddresses": servers,
        }
    else:
        dns_settings = {
            "DNSProtocol": "TLS",
            "ServerName": PROFILE_SERVER_NAME,
            "ServerAddresses": servers,
        }

    # Scoped mode: only the listed hosts are routed here (SupplementalMatchDomains),
    # so editor changes to the *set of hostnames* need a profile reinstall. Global
    # mode: no match list -> this becomes the primary resolver for every query, so
    # any editor change is picked up live with no reinstall.
    if match and not STATE.get("global"):
        dns_settings["SupplementalMatchDomains"] = match
    dns_payload = {
        "PayloadType": "com.apple.dnsSettings.managed",
        "PayloadVersion": 1,
        "PayloadIdentifier": PROFILE_ID + ".dnssettings",
        "PayloadUUID": _det_uuid("dns"),
        "PayloadDisplayName": "EtcHosts17 DNS",
        "PayloadDescription": "Routes the overridden hosts to the local resolver.",
        "DNSSettings": dns_settings,
    }
    proto_label = "DoH" if transport == "https" else "DoT"
    mode_label = "resolved upstream" if STATE.get("mode") == "upstream" else "overridden"
    top = {
        "PayloadType": "Configuration",
        "PayloadVersion": 1,
        "PayloadIdentifier": PROFILE_ID,
        "PayloadUUID": _det_uuid("root"),
        "PayloadDisplayName": "/etc/hosts (iOS 17.0)",
        "PayloadDescription": (
            ("Routes ALL DNS to the local EtcHosts17 resolver over %s; %d host(s) "
             "%s, the rest forwarded upstream." % (proto_label, len(match), mode_label))
            if STATE.get("global") else
            ("Routes %d listed host(s) to the local EtcHosts17 resolver over %s (%s), "
             "overriding DoH/VPN for those names." % (len(match), proto_label, mode_label))
        ),
        "PayloadOrganization": "EtcHosts17",
        "PayloadRemovalDisallowed": False,
        "PayloadContent": [cert_payload, dns_payload],
    }
    return plistlib.dumps(top, fmt=plistlib.FMT_XML)


# ---------------------------------------------------------------------------
# Generic profile builder (the Profile Builder UI hits /build.mobileconfig)
# ---------------------------------------------------------------------------

def build_custom_profile(params):
    """Build an arbitrary managed-DNS .mobileconfig from query params.

    Supported params (all optional except proto/server-or-url):
      proto    = "TLS" | "HTTPS"
      server   = DoT ServerName (e.g. "dns.google")              [proto=TLS]
      url      = DoH ServerURL (e.g. "https://dns.google/dns-query")  [proto=HTTPS]
      port     = custom port 1-65535 (optional). For DoH the port is injected
                 into the ServerURL host (e.g. https://host:PORT/path); for DoT
                 iOS always uses :853 so a non-standard port is ignored.
      addrs    = comma-sep ServerAddresses (optional; default [server])
      domains  = comma-sep SupplementalMatchDomains (empty -> global/primary)
      name     = PayloadDisplayName (default "EtcHosts17 Custom DNS")
      ca       = base64 DER of a root CA to bundle as trusted root (optional)
                 special value "local" -> bundle our per-device CA
    """
    proto = (params.get("proto") or "TLS").upper()
    display = params.get("name") or "EtcHosts17 Custom DNS"
    domains_raw = params.get("domains") or ""
    domains = [d.strip().lower().rstrip(".") for d in domains_raw.split(",") if d.strip()]
    addrs_raw = params.get("addrs") or ""
    if addrs_raw:
        addrs = [a.strip() for a in addrs_raw.split(",") if a.strip()]
    else:
        addrs = []

    # Custom port (1-65535). For DoH we splice it into the ServerURL; for DoT
    # iOS always connects on :853, so a custom port has no effect there.
    port_raw = (params.get("port") or "").strip()
    try:
        port = int(port_raw) if port_raw else 0
    except ValueError:
        port = 0
    if port < 1 or port > 65535:
        port = 0

    dns_settings = {}
    if proto == "HTTPS":
        url = params.get("url") or ""
        if not url:
            raise ValueError("proto=HTTPS requires url")
        # Inject custom port into the URL host if not already present.
        if port and "://" in url:
            scheme, rest = url.split("://", 1)
            # Split host from path at the first '/'
            slash = rest.find("/")
            if slash == -1:
                host_part, path_part = rest, ""
            else:
                host_part, path_part = rest[:slash], rest[slash:]
            # Only inject if there is no :port already in the host.
            if ":" not in host_part.split("?")[0]:
                host_part = "%s:%d%s" % (host_part, port,
                                         ("?" + host_part.split("?", 1)[1]
                                          if "?" in host_part else ""))
                url = "%s://%s%s" % (scheme, host_part, path_part)
        dns_settings = {"DNSProtocol": "HTTPS", "ServerURL": url}
        if addrs:
            dns_settings["ServerAddresses"] = addrs
    else:  # TLS — iOS always uses :853; no per-profile port override exists.
        server = params.get("server") or ""
        if not server:
            raise ValueError("proto=TLS requires server")
        dns_settings = {"DNSProtocol": "TLS", "ServerName": server}
        if addrs:
            dns_settings["ServerAddresses"] = addrs
    if domains:
        dns_settings["SupplementalMatchDomains"] = domains

    # Deterministic UUIDs from the settings content so a re-install updates the
    # same profile instead of stacking duplicates.
    fingerprint = "|".join([proto, str(dns_settings)])
    pid_custom = "com.ratush.etchosts17.custom"

    payloads = []
    ca_param = params.get("ca") or ""
    if ca_param == "local":
        try:
            with open(CA_DER, "rb") as fh:
                ca_der = fh.read()
        except OSError:
            ca_der = b""
        if ca_der:
            payloads.append({
                "PayloadType": "com.apple.security.root",
                "PayloadVersion": 1,
                "PayloadIdentifier": pid_custom + ".ca",
                "PayloadUUID": _det_uuid("customca"),
                "PayloadDisplayName": "EtcHosts17 Local CA",
                "PayloadDescription": "Trusts the local EtcHosts17 resolver cert.",
                "PayloadCertificateFileName": "EtcHosts17CA.cer",
                "PayloadContent": ca_der,
            })
    elif ca_param:
        # user-supplied base64 DER
        import base64 as _b64
        try:
            ca_der = _b64.b64decode(ca_param)
            payloads.append({
                "PayloadType": "com.apple.security.root",
                "PayloadVersion": 1,
                "PayloadIdentifier": pid_custom + ".ca",
                "PayloadUUID": _det_uuid("userca"),
                "PayloadDisplayName": "Custom Root CA",
                "PayloadDescription": "User-provided root CA for this DNS profile.",
                "PayloadContent": ca_der,
            })
        except Exception:
            pass  # ignore malformed CA

    payloads.append({
        "PayloadType": "com.apple.dnsSettings.managed",
        "PayloadVersion": 1,
        "PayloadIdentifier": pid_custom + ".dnssettings",
        "PayloadUUID": _det_uuid("customdns" + fingerprint),
        "PayloadDisplayName": display,
        "PayloadDescription": "Custom managed-DNS profile built by EtcHosts17.",
        "DNSSettings": dns_settings,
    })

    scope = "scoped (%d domains)" % len(domains) if domains else "global (primary)"
    top = {
        "PayloadType": "Configuration",
        "PayloadVersion": 1,
        "PayloadIdentifier": pid_custom,
        "PayloadUUID": _det_uuid("customroot"),
        "PayloadDisplayName": display,
        "PayloadDescription": "%s %s profile (%s)" % (proto, "DoT" if proto == "TLS" else "DoH", scope),
        "PayloadOrganization": "EtcHosts17",
        "PayloadRemovalDisallowed": False,
        "PayloadContent": payloads,
    }
    return plistlib.dumps(top, fmt=plistlib.FMT_XML)


class _ProfileHandler(BaseHTTPRequestHandler):
    def _serve_profile(self, data, filename):
        self.send_response(200)
        self.send_header("Content-Type", "application/x-apple-aspen-config")
        self.send_header("Content-Disposition", 'attachment; filename="%s"' % filename)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):  # noqa: N802 (http.server API)
        from urllib.parse import urlparse, parse_qs
        parsed = urlparse(self.path)
        path = parsed.path
        qs = {k: v[0] for k, v in parse_qs(parsed.query).items()}

        # /build.mobileconfig?proto=TLS&server=... — generic profile builder
        if path == "/build.mobileconfig":
            try:
                data = build_custom_profile(qs)
            except Exception as exc:
                self.send_error(400, "build error: %s" % exc)
                return
            self._serve_profile(data, "EtcHosts17-Custom.mobileconfig")
            return

        # /EtcHosts17.mobileconfig — the EtcHosts17 override profile (legacy/default)
        if path in ("/EtcHosts17.mobileconfig", "/"):
            try:
                data = build_profile_data()
            except Exception as exc:
                self.send_error(500, "profile error: %s" % exc)
                return
            self._serve_profile(data, PROFILE_FILENAME)
            return

        self.send_error(404, "not found")

    def log_message(self, *args):
        return


def profile_http_server():
    try:
        server = ThreadingHTTPServer(("127.0.0.1", PROFILE_HTTP_PORT), _ProfileHandler)
    except OSError as exc:
        log("profile HTTP server bind failed: %s" % exc)
        return
    log("EtcHosts17 profile server on 127.0.0.1:%d" % PROFILE_HTTP_PORT)
    server.serve_forever()


# ---------------------------------------------------------------------------
# Daemon
# ---------------------------------------------------------------------------

# fallback is always True (additive /etc/hosts: forward non-listed) and global is
# always False (scoped profile only: routing ALL DNS through this tiny daemon
# would be a single point of failure). Both former toggles were removed.
#
# transport (DoT vs DoH) and mode (block vs upstream) only affect how the
# *profile* routes matched hosts; the listeners are always on so enabling the
# profile in Settings starts working instantly without a daemon restart.
STATE = {"hosts": {}, "enabled": True, "fallback": True, "global": False,
         "profile": False, "transport": "tls", "mode": "block",
         "upstream": "dns.google", "upstreams": list(UPSTREAMS)}
WAKE = threading.Event()
LISTENERS_STARTED = {"dot": False, "doh": False, "profile_http": False}


def ensure_listeners():
    """Start DoT (:853), DoH (:8443) and the profile HTTP server (:53580) once.

    These are UNCONDITIONAL now: the scoped managed-DNS profile is the primary
    mechanism for beating active DoH/VPN for listed hosts, and it has nothing to
    talk to without the DoT/DoH listener. Keeping them always-on means enabling
    the profile in Settings immediately works. The ssl module import is paid once
    here; the daemon's baseline stays small because no other heavy import is
    pulled in front of the UDP :53 hot path."""
    if not LISTENERS_STARTED["dot"]:
        LISTENERS_STARTED["dot"] = True
        threading.Thread(target=dot_server, daemon=True).start()
    if not LISTENERS_STARTED["doh"]:
        LISTENERS_STARTED["doh"] = True
        threading.Thread(target=doh_server, daemon=True).start()
    if not LISTENERS_STARTED["profile_http"]:
        LISTENERS_STARTED["profile_http"] = True
        threading.Thread(target=profile_http_server, daemon=True).start()


def heal_rootfs_prefs():
    """Keep the rootfs prefs mirror in sync with the canonical jbroot copy.

    iOS ``cfprefsd`` owns the rootfs preferences domain and can flush a stale
    in-memory cache back to ``/rootfs/.../com.ratush.etchosts17.plist`` with a
    fresh mtime (e.g. Enabled=False overwriting the UI's Enabled=True). When the
    jbroot canonical copy disagrees, we rewrite the rootfs copy from jbroot so
    the next cfprefsd flush has correct content. This is idempotent and safe:
    we never touch the jbroot canonical file, only the mirror."""
    if not (os.path.exists(JBROOT_PREFS) and os.path.exists(ROOTFS_PREFS)):
        return
    try:
        jb = read_plist_dict(JBROOT_PREFS)
        rf = read_plist_dict(ROOTFS_PREFS)
    except Exception:
        return
    # Compare the keys the daemon cares about; only rewrite when they differ.
    keys = (PREFS_ENABLED_KEY, PREFS_HOSTS_KEY, PREFS_USE_PROFILE_KEY,
            PREFS_PROFILE_MODE_KEY, PREFS_PROFILE_UPSTREAM_KEY,
            PREFS_PROFILE_TRANSPORT_KEY)
    if all(jb.get(k) == rf.get(k) for k in keys):
        return
    try:
        with open(JBROOT_PREFS, "rb") as handle:
            data = handle.read()
        with open(ROOTFS_PREFS, "wb") as handle:
            handle.write(data)
        log("healed rootfs prefs from jbroot canonical copy")
    except OSError as exc:
        log("could not heal rootfs prefs: %s" % exc)


def reload_state():
    heal_rootfs_prefs()
    settings = read_settings()
    STATE["enabled"] = settings.get(PREFS_ENABLED_KEY, True)
    STATE["profile"] = settings.get(PREFS_USE_PROFILE_KEY, False)
    STATE["mode"] = settings.get(PREFS_PROFILE_MODE_KEY, "block")
    STATE["upstream"] = settings.get(PREFS_PROFILE_UPSTREAM_KEY, "dns.google")
    STATE["transport"] = settings.get(PREFS_PROFILE_TRANSPORT_KEY, "tls")
    STATE["fallback"] = True
    STATE["global"] = False
    STATE["upstreams"] = read_upstreams()
    text = sync_caches()
    STATE["hosts"] = parse_hosts_text(text) if STATE["enabled"] else {}
    ensure_listeners()
    log("loaded %d override host(s), enabled=%s profile=%s transport=%s mode=%s upstream=%s"
        % (len(STATE["hosts"]), STATE["enabled"], STATE["profile"],
           STATE["transport"], STATE["mode"], STATE["upstream"]))


def watcher():
    last = None
    last_ip = None
    while True:
        try:
            paths = (DAEMON_HOSTS, ROOTFS_PREFS, JBROOT_PREFS, UPSTREAMS_FILE)
            stamp = tuple((p, os.stat(p).st_mtime) for p in paths if os.path.exists(p))
            # The profile bakes the live en0 IP into ServerAddresses, so a network
            # change (Wi-Fi/cellular handoff) must trigger a reload so the served
            # .mobileconfig picks up the new IP. Detect the change here.
            current_ip = local_interface_ip()
            if stamp != last or current_ip != last_ip:
                reload_state()
                last = stamp
                last_ip = current_ip
        except Exception as exc:
            log("watcher error: %s" % exc)
        WAKE.wait(10)
        WAKE.clear()


def bind_with_retry(sock, addr, attempts=40, delay=0.5):
    for attempt in range(attempts):
        try:
            sock.bind(addr)
            return
        except OSError as exc:
            if attempt == attempts - 1:
                raise
            if attempt == 0:
                log("waiting for %s:%s: %s" % (addr[0], addr[1], exc))
            time.sleep(delay)


UDP_QUEUE = queue.Queue(maxsize=1024)
UDP_WORKERS = 6


def udp_worker():
    """Resolve queued UDP queries off the accept loop so a slow upstream forward
    never blocks new queries (the daemon is in the path of ALL system DNS)."""
    while True:
        item = UDP_QUEUE.get()
        if item is None:
            return
        query_sock, packet, client = item
        try:
            response = handle_query(packet)
            if response is not None:
                query_sock.sendto(response, client)
        except Exception as exc:
            log("udp worker error: %s" % exc)


def tcp_connection(conn):
    try:
        conn.settimeout(6)
        upstreams = STATE.get("upstreams") or UPSTREAMS
        while True:
            header = recv_exact(conn, 2)
            if not header:
                break
            (length,) = struct.unpack("!H", header)
            message = recv_exact(conn, length)
            if not message:
                break
            response = handle_query(message, forwarder=lambda pkt: forward_tcp(pkt, upstreams))
            if response is None:
                continue
            conn.sendall(struct.pack("!H", len(response)) + response)
    except OSError:
        pass
    finally:
        try:
            conn.close()
        except OSError:
            pass


def tcp_server(family, host):
    """TCP:53 listener. mDNSResponder retries over TCP on truncated/large
    answers; without this those queries would silently fail."""
    listener = socket.socket(family, socket.SOCK_STREAM)
    listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    if family == socket.AF_INET6:
        listener.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
    try:
        bind_with_retry(listener, (host, 53))
    except OSError as exc:
        log("TCP:53 bind failed on %s: %s" % (host, exc))
        return
    listener.listen(64)
    log("EtcHosts17 TCP resolver on %s:53" % host)
    while True:
        try:
            conn, _addr = listener.accept()
        except OSError:
            continue
        threading.Thread(target=tcp_connection, args=(conn,), daemon=True).start()


def daemon():
    ensure_storage()
    reload_state()

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    bind_with_retry(sock, ("0.0.0.0", 53))
    sockets = [sock]
    sock6 = None
    try:
        sock6 = socket.socket(socket.AF_INET6, socket.SOCK_DGRAM)
        sock6.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        sock6.setsockopt(socket.IPPROTO_IPV6, socket.IPV6_V6ONLY, 1)
        sock6.bind(("::", 53))
        sockets.append(sock6)
    except OSError as exc:
        log("IPv6 listener unavailable: %s" % exc)

    control = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    control.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    bind_with_retry(control, ("127.0.0.1", CONTROL_PORT))

    log("EtcHosts17 DNS daemon on 0.0.0.0:53" + (" and [::]:53" if sock6 else ""))
    threading.Thread(target=watcher, daemon=True).start()
    for _ in range(UDP_WORKERS):
        threading.Thread(target=udp_worker, daemon=True).start()
    threading.Thread(target=tcp_server, args=(socket.AF_INET, "0.0.0.0"), daemon=True).start()
    if sock6 is not None:
        threading.Thread(target=tcp_server, args=(socket.AF_INET6, "::"), daemon=True).start()
    # DoT (:853), DoH (:8443) and profile-HTTP (:53580) listeners were started
    # unconditionally by ensure_listeners() inside reload_state() above. They are
    # always on so enabling the scoped managed-DNS profile in Settings works
    # immediately, without a daemon restart or a toggle flip.

    while True:
        try:
            ready, _, _ = select.select(sockets + [control], [], [], 30)
            if not ready:
                continue
            if control in ready:
                payload, _client = control.recvfrom(65535)
                if payload.startswith(CONTROL_APPLY_MAGIC):
                    log("control apply")
                    WAKE.set()
                elif payload.startswith(CONTROL_MAGIC):
                    text = payload[len(CONTROL_MAGIC):].decode("utf-8", "ignore")
                    try:
                        text = validated_hosts_text(text)
                    except ValueError as exc:
                        log("rejected control update: %s" % exc)
                        continue
                    # Runtime cache only -- never the preferences plist.
                    write_text(DAEMON_HOSTS, text)
                    STATE["hosts"] = parse_hosts_text(text) if STATE["enabled"] else {}
                    log("control update: %d host(s)" % len(STATE["hosts"]))
                continue

            for query_sock in sockets:
                if query_sock in ready:
                    packet, client = query_sock.recvfrom(4096)
                    try:
                        UDP_QUEUE.put_nowait((query_sock, packet, client))
                    except queue.Full:
                        # Overload: drop rather than block the accept loop; the
                        # client will retry. Better a dropped query than frozen DNS.
                        pass
        except Exception as exc:
            log("request error: %s" % exc)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["daemon", "apply", "sync", "profile"], nargs="?", default="apply")
    args = parser.parse_args()
    if args.mode == "daemon":
        daemon()
    elif args.mode == "profile":
        # Emit the generated profile to stdout (diagnostics / offline install).
        reload_state()
        sys.stdout.buffer.write(build_profile_data())
    else:
        sync_caches()
        log("%s complete" % args.mode)


if __name__ == "__main__":
    main()
