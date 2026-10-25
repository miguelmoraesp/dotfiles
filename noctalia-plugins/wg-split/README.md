# WireGuard Split Tunnel

Route only chosen applications through a WireGuard tunnel. Front end for the `wgsplit` CLI in this repo
(`wgsplit/`), which puts apps in the systemd `--user` slice `wgsplit.slice` and routes that slice's sockets
through the tunnel with nftables (`socket cgroupv2`) and policy routing. DNS from the slice is redirected to a
dnsmasq that runs inside the tunnel, so lookups do not leak either.

| Entry | Kind | What it does |
| --- | --- | --- |
| `service` | service | Polls `wgsplit status --json`, runs every command |
| `bar` | bar widget | Shield with the state; left click opens the panel, right click toggles the tunnel |
| `panel` | panel | Tunnel switch, endpoint/handshake/traffic/DNS, configured apps, run any command, apps in the tunnel, move running apps |
| `toggle` | control-center shortcut | Toggles the tunnel |
| `launcher` | launcher provider | `/vpn <app>` runs an app through the tunnel |

```sh
noctalia msg plugin zmiguel/wg-split:service all toggle          # also: up, down, release, refresh, status
noctalia msg plugin zmiguel/wg-split:service all run "firefox --new-instance -P vpn"
noctalia msg plugin zmiguel/wg-split:service all attach spotify
noctalia msg panel-toggle zmiguel/wg-split:panel
```

Requires `wgsplit` (installed by `install.sh`), `wireguard-tools`, `nftables`, `dnsmasq`, `jq`, and a kernel
with `nft_socket`. With the kill switch on, `down` keeps tunneled apps offline; `release` removes the rules.
