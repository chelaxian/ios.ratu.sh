# Optional system DoH/DoT preservation (0.4.5 candidate)

Scope: BYPASS/DIRECT only, `preserveSystemDNS`, default false. No DNS profile is
edited; profile endpoints and credentials never enter exported settings or logs.

## Mechanism and evidence

The existing terminal NECP `scopeToDirectInterface` stops policy evaluation before
native DNS resolver agents are selected. Live iOS 17 testing showed an empty
resolver configuration list for DIRECT paths. Replacing it with nonterminal VPN
interface-deny route rules preserved DNS but did not reliably bypass the VPN;
that approach was rejected.

The candidate reads enabled system encrypted DNS settings, creates transient
native `nw_resolver_config` objects, publishes them with owned UUIDs and attaches
their DNS agents before the existing DIRECT terminal result. This uses Apple's
encrypted DNS implementation, not a DNS proxy or hardcoded public resolver.
Application gates and a skip guard prevent other apps from inheriting the
additional DNS policies. Domain policies are shared after the gate rather than
multiplied by application count. More-specific domains precede catch-all domains.

An isolated curl-only live prototype on iOS 17 returned an HTTPS resolver config,
used a different public egress IP from the connected VPN, and resolved ChatGPT
through the installed Control D profile. Removing the owned test session restored
the VPN egress. The gated variant also retained the HTTPS resolver configuration.
This is mechanism validation, not final package/UI validation.

Native profile snapshots refresh every 30 seconds while the option is active.
Published resolvers are retained until the corresponding owned policy session is
replaced or cleared. Master-off and other modes stop refresh and release owned
registrations. Domain-only NeverConnect exclusions followed by an unconditional
Connect rule are preserved (the device's Control D profile has 45 exclusions).
Other conditional on-demand profiles are skipped with a visible warning rather
than silently ignoring their conditions. App-embedded DNS is not changed.

## Required candidate checks

- macOS build, arm64e PTRAUTH gate; never install WSL platform-injection output.
- Test ChatGPT in DIRECT with Control D and a connected VPN, including reopened
  app after toggling. Verify nonselected apps retain VPN egress and VPN DNS.
- Option off must reproduce 0.4.4 routing. Hide the option outside BYPASS.
- Master-off, mode switches, VPN reconnect, profile removal/change, IPv4/IPv6.
- Badge option off restores native text/tint and removes owned fallback badges.
- Import/export retains only the boolean, never profile transport settings.

Primary references:

- https://github.com/apple-oss-distributions/xnu/blob/xnu-10002.1.13/bsd/net/necp.c
- https://github.com/apple-oss-distributions/mDNSResponder/blob/mDNSResponder-2200.0.8/mDNSMacOSX/uDNSPathEvaluation.c
- https://github.com/WebKit/WebKit/blob/main/Tools/WebKitTestRunner/cocoa/TestControllerCocoa.mm
