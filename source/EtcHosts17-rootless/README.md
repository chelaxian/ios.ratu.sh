# /etc/hosts — EtcHosts17 1.x

Real hosts-file behaviour for Dopamine rootless jailbreaks (tested on iOS 17.0).

## How it works

iOS `mDNSResponder` contains Apple's complete `/etc/hosts` engine
(`mDNSMacOSXUpdateEtcHosts`, vnode watch, local auth records), but `main()`
only starts it on Apple internal builds. Retail builds register just
`localhost`/`broadcasthost`.

`Tweak.x` is injected into `mDNSResponder` only. It:

1. redirects the daemon's read-only `open()`/`fopen()` of `/etc/hosts` to
   `/var/jb/var/mobile/Library/EtcHosts17/hosts` (falls back to the stock file
   if that is unreadable);
2. calls `mDNSResponder`'s own `mDNSMacOSXUpdateEtcHosts()` once after start-up,
   the same call its change handler makes. From then on the daemon watches the
   file itself and reloads it on every atomic replace;
3. publishes its state on `com.ratush.etchosts17.state` (loaded / engine on /
   no file / unsupported build, plus pid).

Entries become local-only records that `mDNSResponder` answers before any
unicast query, so they win over Wi-Fi/cellular DNS, DoH/DoT profiles and VPN DNS.
The internal-build flag is not touched.

The Settings pane compiles the editor text into that file: one `address name`
line per record, stock localhost lines first, and (option "Cover both IPv4 and
IPv6", on by default) the missing address family added (`::ffff:IP` or `::`
for IPv4-only entries, `0.0.0.0` for IPv6-only ones) so the real answer of the
other family cannot leak through.

## Safety

- No daemons, no DNS profiles, no SCDynamicStore keys, no custom DNS servers.
- The only file written is the compiled hosts file under `/var/jb`.
- Tweak removed, injection disabled, jailbreak gone, or unknown mDNSResponder
  build: the daemon starts as stock.
- `postinst`/`postrm` only restart `mDNSResponder` (launchd brings it straight
  back) and retire the 0.x daemons if any are still loaded.

## Limits

Apps that do their own DNS (Chrome Secure DNS, c-ares tools such as Procursus
`curl`) bypass the system resolver, the same as on a desktop.

If a 0.x "/etc/hosts (iOS 17.0)" DNS profile is still installed, remove it in
Settings > General > VPN & Device Management.
