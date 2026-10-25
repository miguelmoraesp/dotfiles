# dotfiles — Arch + Umbriel + Noctalia

A Wayland desktop on [Umbriel](https://github.com/noctalia-dev/umbriel) (compositor) with
[Noctalia](https://github.com/noctalia-dev/noctalia) v5 as the shell and
[Noctalia Greeter](https://github.com/noctalia-dev/noctalia-greeter) on greetd as the login screen. Noctalia alone
replaces what used to be waybar, rofi, dunst, hyprpaper/waypaper, a power menu and flameshot: bar, launcher,
notifications, wallpaper, lock screen, OSD, clipboard and screenshots.

## Install

On a fresh Arch install, with your user in the `wheel` group:

```sh
git clone https://github.com/miguelmoraesp/dotfiles ~/dotfiles && cd ~/dotfiles
./install.sh --wg-conf ~/Downloads/my-vpn.conf   # drop --wg-conf if you are not using the split tunnel yet
reboot
```

`install.sh`:

1. installs `packages/pacman.txt` and, through `yay` (built from source if missing), `packages/aur.txt`;
2. copies `config/` into `~/.config/`, `home/` into `~`, and `wallpapers/` into `~/wallpapers`
   (anything different already there is kept as `*.bak-<date>`);
3. copies `noctalia-plugins/` into `~/.local/share/noctalia/plugins/`;
4. installs wgsplit (CLI, root helper, sudoers rule, WireGuard config) and the Firefox `vpn` profile;
5. sets up greetd with Noctalia Greeter (Umbriel session and your user preselected, passwordless appearance sync)
   and disables any other display manager;
6. enables NetworkManager, bluetooth, power-profiles-daemon, AccountsService, PipeWire and `wgsplit-anchor.service`.

Options: `--no-packages`, `--no-configs`, `--no-plugins`, `--no-wgsplit`, `--no-greeter`, `--no-services`,
`--wg-conf <file>`, `--spicetify`. Re-running is safe; `./install.sh --no-packages` re-applies everything else.

Configs are **copied**, not symlinked: Noctalia's theme templates rewrite `umbriel/config.toml`,
`kitty/kitty.conf`, `starship.toml` and `gtk.css`, and through a symlink those edits would land in the repo.

## Layout

| Path | What |
| --- | --- |
| `config/umbriel/config.toml` | Compositor: binds, window rules, scratchpads, blur |
| `config/noctalia/config.toml` | Shell: bar, theme, templates, wallpaper, idle, greeter sync, plugins |
| `config/noctalia/palettes/VioletNoir.json` | The purple, black and white color palette (dark and light) |
| `config/kitty`, `config/starship.toml`, `config/gtk-*` | Apps; colors come from Noctalia's templates |
| `config/environment.d/10-wayland.conf` | Session environment (Qt/Electron on Wayland, cursor, `~/.local/bin` on PATH) |
| `config/spotify-launcher.conf` | Spotify as a native Wayland client |
| `config/systemd/user/wgsplit-*.service` | Keeps `wgsplit.slice` alive; DNS forwarder for the tunnel |
| `home/.bashrc`, `home/.bash_profile` | Bash with Starship, history, aliases |
| `system/` | greetd and Noctalia Greeter configs (installed by `install.sh`) |
| `firefox/vpn-user.js` | Hardening for the Firefox `vpn` profile |
| `extras/spicetify/` | Units that re-apply Spicetify after Spotify updates |
| `noctalia-plugins/wg-split`, `noctalia-plugins/spotify` | This repo's Noctalia plugins |
| `wgsplit/` | `wgsplit` CLI and the `wgsplit-root` helper |
| `wallpapers/` | Wallpapers copied to `~/wallpapers` (add `blackhole.png` here) |
| `packages/` | Package lists |
| `tools/lint.py`, `.github/workflows/lint.yml` | CI checks |

## Keybinds

The binds from the old `hyprland.conf` are kept. `Mod` is Super.

| Bind | Action |
| --- | --- |
| `Mod` (alone) / `Mod+R` | Launcher |
| `Mod+Q` / `Mod+Return` | Kitty |
| `Mod+C` / `Mod+Shift+C` | Close / kill window |
| `Mod+E` · `Mod+B` | Dolphin · Firefox |
| `Mod+V` · `Mod+F` · `Mod+P` | Float · fullscreen · pin on top |
| `Mod+T` · `Mod+Alt+L` | Flip split (dwindle) · toggle dwindle/scrolling |
| `Mod+arrows` / `Mod+HJKL` | Focus; with `Shift` move, with `Ctrl` swap |
| `Mod+1..0` / `Mod+Shift+1..0` | Go to workspace / move window there |
| `Mod+O` or the top-left corner | Overview |
| `Mod+A` · `Mod+N` · `Mod+M` | Control center · Noctalia settings · session menu |
| `Mod+Shift+S` / `Print` | Region screenshot (`Mod+Print` full screen, `Mod+Shift+A` annotate) |
| `Mod+Shift+V` · `Mod+Shift+P` · `Mod+Ctrl+P` | Clipboard · wallpaper picker · Wallhaven browser |
| `Mod+Shift+L` | Lock screen |
| `Mod+Space` / `Mod+Shift+Space` | General scratchpad: show / send window |
| `Mod+S` | Spotify scratchpad (starts Spotify if it is closed) |
| `Mod+Shift+M` | Spotify panel |
| `Mod+W` / `Mod+Shift+W` | Split-tunnel panel / toggle the tunnel |
| `Mod+F1` | Umbriel keybind cheatsheet |
| `Alt+Tab` | Window switcher |

Fixed workspaces carried over: editors on 1, Firefox on 2, Discord on 7. Spotify goes to the `music` scratchpad.

## Login screen

greetd runs Noctalia Greeter on VT 1 with the Umbriel session and your user preselected and the `br` keyboard
layout. With `[shell.greeter_sync] auto_sync = true`, Noctalia copies your wallpaper, palette, font and monitor
layout to the greeter whenever they change (no password prompt: `install.sh` enables the greeter's narrow
passwordless rule for your user). Pick the **Synced** color scheme on the login screen once; it is remembered.

Greeter settings live in `/var/lib/noctalia-greeter/greeter.toml` (from `system/noctalia-greeter/greeter.toml`).

## WireGuard split tunnel (`wgsplit` + the `zmiguel/wg-split` plugin)

Only the apps you choose use the VPN; everything else stays on the normal connection.

```
app started with `wgsplit run`  →  scope in wgsplit.slice (systemd --user)
nftables: socket cgroupv2 == wgsplit.slice  →  fwmark 0x5157
ip rule fwmark 0x5157  →  table 5157  →  default dev wgsplit
port 53 from the slice  →  dnsmasq in the slice (wgsplit-dns.service)  →  tunnel DNS
```

- **On/off:** bar shield (right click), control-center tile, `Mod+Shift+W`, the panel (`Mod+W`),
  or `wgsplit up` / `wgsplit down`.
- **Run an app through the VPN:** ▶ in the panel, `/vpn <app>` in the launcher, `wgsplit run <command>`,
  or the `vpn` alias in bash. The pinned apps are the plugin's `Apps` setting (default: `spotify-launcher` and
  `firefox --new-instance -P vpn`).
- **Move a running app:** "Move a running app" in the panel, or `wgsplit attach spotify`. Only connections
  opened afterwards use the tunnel; reconnecting fixes the rest.
- **DNS:** lookups from tunneled apps go to a dnsmasq that runs inside the tunnel and forwards to the
  config's `DNS` servers (or `DNS_FALLBACK`, `1.1.1.1 1.0.0.1` by default), so they don't leak to your ISP. The
  Firefox `vpn` profile also forces DNS-over-HTTPS and hides local addresses from WebRTC.
- **Kill switch** (on by default): when the tunnel goes down, its apps lose network access instead of falling
  back to the normal connection. "Release apps" in the panel (or `wgsplit down` without `--keep-killswitch`)
  lifts it.
- **LAN:** tunneled apps can still reach the local network (`ALLOW_LAN=0` in `/etc/wgsplit.env` turns that off).

Put the WireGuard config in `/etc/wireguard/wgsplit.conf` (your provider's file works). `Table` and
`PostUp`/`PostDown` are ignored because `wgsplit-root` does not use `wg-quick up`. Review the exact nftables
ruleset with `wgsplit-root print-rules $(id -u)`.

Caveats:

- **An app that is already running does not join through `run`:** `firefox` with Firefox open just opens a
  window in the old process, outside the tunnel. That is why the default is `--new-instance -P vpn`.
- `sudoers` allows **only** `/usr/local/bin/wgsplit-root` without a password, and only for your user.

## Spotify (the `zmiguel/spotify` plugin)

- Bar widget with artist and title (click opens the panel, right click pauses, scroll skips).
- Panel with artwork, a seek bar, controls, copy link, show window, and "open through the VPN".
- Spotify lives in Umbriel's `music` scratchpad (`Mod+S`), which starts it when closed. To always route it through
  the VPN, set `spawn_when_empty = "wgsplit run spotify-launcher"` in `config/umbriel/config.toml`.
- Theme: `./install.sh --no-packages --spicetify` (open Spotify and log in once first) installs Spicetify with the
  Comfy theme and a path unit that re-applies it after each Spotify update; then add `"spicetify"` to
  `community_ids` so its colors follow Noctalia.

## Theme and bar

The palette is **VioletNoir** (`config/noctalia/palettes/VioletNoir.json`): a near-black, slightly violet
background, purple accents and white text, with a light variant and matching terminal colors. Every text/background
pair meets WCAG AA (4.5:1 or better). Noctalia applies it to the shell and, through the `umbriel`, `kitty`, `gtk3`,
`gtk4`, `qt`, `btop` and `starship` templates, to the apps; greeter sync carries it to the login screen. To follow the
wallpaper instead, set `source = "wallpaper"` in `[theme]`.

The bar keeps the right side to icons only: Spotify, the split-tunnel shield, tray, network, volume, notifications
and power. Clipboard, bluetooth and the other quick settings live in the control center (`Mod+A`, or click the
network icon). On the left, next to the launcher, the photo icon opens the official **Wallhaven** browser
(`noctalia/wallhaven`): search wallpapers, download them into `~/wallpapers` and apply them.

## CI

`.github/workflows/lint.yml` runs on every push: `bash -n` and ShellCheck on the scripts, `tools/lint.py`
(TOML/JSON parsing, plugin manifests, entry files, `require` targets, translation keys used by the code, and key
parity between translation files), Luau syntax for every plugin script, and `nft -c` on the ruleset
`wgsplit-root print-rules` renders from `tools/sample-wgsplit.conf`. Run `python3 tools/lint.py` locally.

## Troubleshooting

| Symptom | Where to look |
| --- | --- |
| A Noctalia setting seems ignored | `~/.local/state/noctalia/settings.toml` (the GUI wins) and `noctalia config validate` |
| A bind does nothing | `umbriel config validate`; for Noctalia binds, run the `noctalia msg ...` command in a terminal |
| Noctalia logs | `~/.cache/noctalia/noctalia.log` |
| A plugin is missing | `noctalia msg plugins list`; enable with `noctalia msg plugins enable zmiguel/wg-split` |
| `wgsplit up` fails | `sudo -n /usr/local/bin/wgsplit-root up $(id -u)` shows the error; check `/etc/wireguard/wgsplit.conf` |
| An app does not use the VPN | `wgsplit status` lists the slice; compare `curl ifconfig.me` with `wgsplit run curl ifconfig.me` |
| Tunneled apps have no DNS | `systemctl --user status wgsplit-dns.service`; `wgsplit run getent hosts example.com` |
| No login screen after reboot | Switch to a TTY (`Ctrl+Alt+F2`), then `systemctl status greetd` |

### Testing in a VMware VM

Everything was tested end to end on an Arch VMware VM, with one VM-only workaround. VMware's `vmwgfx` driver
cannot import the dmabufs that GPU-rendered Wayland clients hand to the compositor, so the greeter and Noctalia
die with `importing the supplied dmabufs failed`. Force software rendering on the VM only (real GPUs don't need
this):

```sh
# Login screen: in /etc/greetd/config.toml
command = "env LIBGL_ALWAYS_SOFTWARE=1 /usr/bin/noctalia-greeter-session"

# Desktop session
echo LIBGL_ALWAYS_SOFTWARE=1 > ~/.config/environment.d/90-vm.conf
```

Give the VM at least 4 cores and 6 GB of RAM, or the Umbriel build runs out of memory. WSL2 can test
`install.sh` and the config validators, but not the desktop (no DRM/GBM) or the split-tunnel routing (its kernel
lacks `nft_socket`).
