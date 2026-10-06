# DNS Profile Configurator

Settings pane that builds standard encrypted-DNS profiles
(`com.apple.dnsSettings.managed`) in the same green CRT style as
/etc/hosts (iOS 17.0).

- **DoT**: `ServerName` + optional `ServerAddresses`. iOS always uses port 853
  for DoT; the profile format has no port key.
- **DoH**: `ServerURL`; a custom port is written into the URL.
- **BLOCK**: listed domains go to DoT `127.0.0.1`/`::1` where nothing listens,
  so those names stop resolving. An empty list is refused.
- Optional match domains (`SupplementalMatchDomains`); empty = all DNS.
- Same profile name = same PayloadIdentifier/UUID, so re-creating updates it.

Install path: the profile is queued through ManagedConfiguration
(`MCProfileConnection queueFileDataForAcceptance`), the same queue Safari and
Files use, so Settings shows "Profile Downloaded". If that API is unavailable,
the pane serves the file once from a localhost socket to Safari and closes it.

No daemons or hooks. Profiles are ordinary iOS profiles; manage or remove them
in Settings > General > VPN & Device Management.
