// user.js for the Firefox "vpn" profile (what wgsplit starts with `firefox --new-instance -P vpn`).
// install.sh copies it into the profile folder; Firefox applies it on every start.

// Mandatory DNS-over-HTTPS: lookups leave through the tunnel with the rest of the traffic,
// even if wgsplit's DNS redirect is off.
user_pref("network.trr.mode", 3);
user_pref("network.trr.uri", "https://mozilla.cloudflare-dns.com/dns-query");
user_pref("network.trr.custom_uri", "https://mozilla.cloudflare-dns.com/dns-query");
user_pref("network.trr.bootstrapAddr", "1.1.1.1");

// WebRTC: do not expose local network addresses in ICE candidates.
user_pref("media.peerconnection.ice.default_address_only", true);
user_pref("media.peerconnection.ice.no_host", true);

// No speculative connections or DNS prefetching.
user_pref("network.dns.disablePrefetch", true);
user_pref("network.prefetch-next", false);
user_pref("network.predictor.enabled", false);
user_pref("network.http.speculative-parallel-limit", 0);

// Makes it obvious which window is the VPN one.
user_pref("browser.startup.homepage", "https://am.i.mullvad.net/");
user_pref("browser.startup.page", 1);
