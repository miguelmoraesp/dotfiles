#!/usr/bin/env bash
# Sets up the Umbriel + Noctalia desktop on a fresh Arch install.
#
#   ./install.sh                          everything
#   ./install.sh --wg-conf ~/proton.conf  also install the WireGuard config for wgsplit
#   ./install.sh --no-packages            re-apply configs, plugins, wgsplit and greeter only
#   ./install.sh --spicetify              Spotify theme via Spicetify (open Spotify once first)
#
# Options: --no-packages --no-configs --no-plugins --no-wgsplit --no-greeter
#          --no-services --wg-conf <file> --spicetify --help
#
# Run as your user (not root); sudo is used where needed.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STAMP="$(date +%Y%m%d-%H%M%S)"

DO_PACKAGES=1
DO_CONFIGS=1
DO_PLUGINS=1
DO_WGSPLIT=1
DO_GREETER=1
DO_SERVICES=1
DO_SPICETIFY=0
WG_CONF=""

c_info=$'\e[1;34m' c_ok=$'\e[1;32m' c_warn=$'\e[1;33m' c_err=$'\e[1;31m' c_off=$'\e[0m'
step() { printf '\n%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok() { printf '  %s✓%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '  %s!%s %s\n' "$c_warn" "$c_off" "$*" >&2; }
die() {
    printf '%serror:%s %s\n' "$c_err" "$c_off" "$*" >&2
    exit 1
}

usage() {
    sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --no-packages) DO_PACKAGES=0 ;;
        --no-configs) DO_CONFIGS=0 ;;
        --no-plugins) DO_PLUGINS=0 ;;
        --no-wgsplit) DO_WGSPLIT=0 ;;
        --no-greeter) DO_GREETER=0 ;;
        --no-services) DO_SERVICES=0 ;;
        --spicetify) DO_SPICETIFY=1 ;;
        --wg-conf)
            [[ $# -ge 2 ]] || die "--wg-conf needs a file"
            WG_CONF="$2"
            shift
            ;;
        -h | --help) usage 0 ;;
        *)
            warn "unknown option: $1"
            usage 2
            ;;
    esac
    shift
done

[[ $EUID -ne 0 ]] || die "run as your user, not as root"
[[ -f /etc/arch-release ]] || die "this script is for Arch Linux"
command -v sudo >/dev/null || die "install sudo and add your user to the wheel group"
if [[ -n "$WG_CONF" && ! -f "$WG_CONF" ]]; then
    die "WireGuard config not found: $WG_CONF"
fi

# Reads a package list, skipping comments and blank lines.
read_list() {
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

# Copies a file into place; anything different already there is kept as a backup.
install_file() {
    local src="$1" dest="$2" mode="${3:-644}"
    if [[ -e "$dest" || -L "$dest" ]]; then
        if [[ ! -L "$dest" ]] && cmp -s "$src" "$dest"; then
            return 0
        fi
        mv "$dest" "$dest.bak-$STAMP"
        warn "backup: $dest.bak-$STAMP"
    fi
    install -Dm"$mode" "$src" "$dest"
}

# Same as install_file, for files owned by root (or another account).
sudo_install_file() {
    local src="$1" dest="$2" mode="${3:-644}" owner="${4:-root}"
    if sudo test -e "$dest"; then
        if sudo cmp -s "$src" "$dest"; then
            return 0
        fi
        sudo mv "$dest" "$dest.bak-$STAMP"
        warn "backup: $dest.bak-$STAMP"
    fi
    sudo install -Dm"$mode" -o "$owner" -g "$owner" "$src" "$dest"
}

aur_helper() {
    if command -v paru >/dev/null; then
        echo paru
    elif command -v yay >/dev/null; then
        echo yay
    fi
}

# ── packages ──────────────────────────────────────────────────────────────────

install_packages() {
    step "Official packages"
    mapfile -t pkgs < <(read_list "$REPO/packages/pacman.txt")
    sudo pacman -Syu --needed --noconfirm "${pkgs[@]}"
    ok "${#pkgs[@]} pacman packages"

    step "AUR packages"
    local helper
    helper="$(aur_helper)"
    if [[ -z "$helper" ]]; then
        local tmp
        tmp="$(mktemp -d)"
        git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
        (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
        helper=paru
        ok "installed paru"
    fi
    mapfile -t aur < <(read_list "$REPO/packages/aur.txt")
    "$helper" -S --needed --noconfirm "${aur[@]}"
    ok "${#aur[@]} AUR packages with $helper"
}

# ── configs ───────────────────────────────────────────────────────────────────

install_tree() {
    local from="$1" to="$2" src rel count=0
    while IFS= read -r -d '' src; do
        rel="${src#"$from/"}"
        [[ "$rel" == README.md ]] && continue
        install_file "$src" "$to/$rel"
        count=$((count + 1))
    done < <(find "$from" -type f -print0)
    echo "$count"
}

install_configs() {
    step "Configs in $CONFIG_HOME"
    ok "$(install_tree "$REPO/config" "$CONFIG_HOME") files (copies, not links: Noctalia's theme templates edit some of them)"

    step "Shell files in $HOME"
    ok "$(install_tree "$REPO/home" "$HOME") files"

    step "Wallpapers in ~/wallpapers"
    ok "$(install_tree "$REPO/wallpapers" "$HOME/wallpapers") files"
    if command -v xdg-user-dirs-update >/dev/null; then
        xdg-user-dirs-update
    fi
    if [[ ! -f "$HOME/wallpapers/blackhole.png" ]]; then
        warn "$HOME/wallpapers/blackhole.png is missing; add it to the repo's wallpapers/ (Noctalia falls back to its own)"
    fi
}

# ── Noctalia plugins ──────────────────────────────────────────────────────────

install_plugins() {
    step "Noctalia plugins in $DATA_HOME/noctalia/plugins"
    local dir name dest
    for dir in "$REPO"/noctalia-plugins/*/; do
        name="$(basename "$dir")"
        dest="$DATA_HOME/noctalia/plugins/$name"
        rm -rf "$dest"
        mkdir -p "$dest"
        cp -r "$dir". "$dest/"
        ok "$name"
    done
}

# ── wgsplit (WireGuard split tunnel) ──────────────────────────────────────────

# Prints the directory of the Firefox profile named "vpn", if there is one.
firefox_vpn_profile() {
    local ini base path relative
    for ini in "$HOME/.mozilla/firefox/profiles.ini" "$CONFIG_HOME/mozilla/firefox/profiles.ini"; do
        [[ -f "$ini" ]] || continue
        base="$(dirname "$ini")"
        read -r relative path < <(awk -F= '
            /^\[/ { if (name == "vpn") exit; name = ""; rel = 1; p = "" }
            $1 == "Name" { name = $2 }
            $1 == "IsRelative" { rel = $2 }
            $1 == "Path" { p = $2 }
            END { if (name == "vpn") print rel, p }
        ' "$ini")
        [[ -n "${path:-}" ]] || continue
        if [[ "$relative" == 1 ]]; then
            echo "$base/$path"
        else
            echo "$path"
        fi
        return 0
    done
    return 1
}

setup_firefox_vpn_profile() {
    command -v firefox >/dev/null || return 0
    local profile
    if ! profile="$(firefox_vpn_profile)"; then
        firefox --headless -CreateProfile vpn >/dev/null 2>&1 || true
        profile="$(firefox_vpn_profile)" || {
            warn "could not create the Firefox 'vpn' profile (create it with: firefox -P)"
            return 0
        }
        ok "created Firefox profile 'vpn'"
    fi
    install_file "$REPO/firefox/vpn-user.js" "$profile/user.js"
    ok "Firefox 'vpn' profile: DNS-over-HTTPS and WebRTC hardening ($profile/user.js)"
}

install_wgsplit() {
    step "wgsplit (per-app split tunnel)"
    install -Dm755 "$REPO/wgsplit/wgsplit" "$HOME/.local/bin/wgsplit"
    ok "$HOME/.local/bin/wgsplit"

    sudo install -Dm755 -o root -g root "$REPO/wgsplit/wgsplit-root" /usr/local/bin/wgsplit-root
    ok "/usr/local/bin/wgsplit-root"

    # Only the root helper, only for this user, without a password: that is what the plugin calls.
    local sudoers
    sudoers="$(mktemp)"
    printf '%s ALL=(root) NOPASSWD: /usr/local/bin/wgsplit-root\n' "$USER" > "$sudoers"
    if sudo visudo -cqf "$sudoers"; then
        sudo install -Dm440 -o root -g root "$sudoers" /etc/sudoers.d/wgsplit
        ok "/etc/sudoers.d/wgsplit"
    else
        warn "generated sudoers entry is invalid; skipped /etc/sudoers.d/wgsplit"
    fi
    rm -f "$sudoers"

    if [[ -n "$WG_CONF" ]]; then
        sudo install -Dm600 -o root -g root "$WG_CONF" /etc/wireguard/wgsplit.conf
        ok "/etc/wireguard/wgsplit.conf"
    elif ! sudo test -f /etc/wireguard/wgsplit.conf; then
        warn "no WireGuard config yet: sudo install -Dm600 your.conf /etc/wireguard/wgsplit.conf"
    fi

    # A Firefox that is already open never joins the tunnel; a new instance on its own profile does.
    setup_firefox_vpn_profile
}

# ── login: greetd + Noctalia Greeter ──────────────────────────────────────────

setup_greeter() {
    step "Login screen (greetd + Noctalia Greeter)"
    command -v noctalia-greeter-session >/dev/null || die "noctalia-greeter is not installed (run without --no-packages)"

    sudo_install_file "$REPO/system/greetd/config.toml" /etc/greetd/config.toml
    ok "/etc/greetd/config.toml"

    sudo systemd-tmpfiles --create noctalia-greeter.conf >/dev/null 2>&1 || true
    sudo noctalia-greeter-apply-appearance --setup-system >/dev/null \
        || warn "noctalia-greeter-apply-appearance --setup-system failed; see: systemctl status greetd"
    local greeter_toml
    greeter_toml="$(mktemp)"
    sed "s/@USER@/$USER/" "$REPO/system/noctalia-greeter/greeter.toml" > "$greeter_toml"
    sudo_install_file "$greeter_toml" /var/lib/noctalia-greeter/greeter.toml 644 greeter
    rm -f "$greeter_toml"
    ok "/var/lib/noctalia-greeter/greeter.toml"

    # Lets Noctalia copy wallpaper, palette and monitor layout to the greeter without a prompt.
    if sudo noctalia-greeter passwordless-sync enable "$USER" >/dev/null 2>&1; then
        ok "passwordless greeter sync for $USER"
    else
        warn "passwordless greeter sync not enabled; Noctalia will ask for your password on each sync"
    fi

    # Another display manager would fight greetd for the screen. Both changes apply on the next boot.
    local current
    current="$(basename "$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null)" 2>/dev/null || true)"
    if [[ -n "$current" && "$current" != "greetd.service" && "$current" != "display-manager.service" ]]; then
        sudo systemctl disable "$current" >/dev/null 2>&1 && ok "disabled $current" || warn "could not disable $current"
    fi
    sudo systemctl enable greetd.service >/dev/null 2>&1 && ok "greetd.service enabled (starts on next boot)" \
        || warn "could not enable greetd.service"
}

# ── services ──────────────────────────────────────────────────────────────────

enable_services() {
    step "Services"
    local unit
    for unit in NetworkManager.service bluetooth.service power-profiles-daemon.service accounts-daemon.service; do
        if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
            sudo systemctl enable --now "$unit" >/dev/null 2>&1 && ok "$unit" || warn "failed: $unit"
        fi
    done

    systemctl --user daemon-reload
    for unit in pipewire-pulse.socket wireplumber.service gnome-keyring-daemon.socket; do
        systemctl --user enable --now "$unit" >/dev/null 2>&1 && ok "$unit (user)" || warn "failed: $unit"
    done
    if [[ $DO_WGSPLIT -eq 1 ]]; then
        systemctl --user enable --now wgsplit-anchor.service >/dev/null 2>&1 && ok "wgsplit-anchor.service (user)" \
            || warn "failed: wgsplit-anchor.service"
    fi
}

# ── Spicetify (optional) ──────────────────────────────────────────────────────

install_spicetify() {
    step "Spicetify (Spotify theme generated by Noctalia)"
    local helper spotify_dir="$DATA_HOME/spotify-launcher/install/usr/share/spotify"
    helper="$(aur_helper)"
    [[ -n "$helper" ]] || die "install the packages first (needs paru or yay)"
    "$helper" -S --needed --noconfirm spicetify-cli

    [[ -d "$spotify_dir" ]] || die "open Spotify once (spotify-launcher) and run again with --spicetify"
    [[ -f "$CONFIG_HOME/spotify/prefs" ]] || die "log in to Spotify once and run again with --spicetify"

    spicetify config spotify_path "$spotify_dir" prefs_path "$CONFIG_HOME/spotify/prefs" >/dev/null
    local themes
    themes="$(spicetify path userdata)/Themes"
    if [[ ! -d "$themes/Comfy" ]]; then
        local tmp
        tmp="$(mktemp -d)"
        git clone --depth 1 https://github.com/Comfy-Themes/Spicetify.git "$tmp/comfy"
        mkdir -p "$themes"
        cp -r "$tmp/comfy/Comfy" "$themes/"
        rm -rf "$tmp"
    fi
    spicetify config current_theme Comfy color_scheme Comfy >/dev/null
    spicetify config inject_css 1 replace_colors 1 overwrite_assets 1 inject_theme_js 1 >/dev/null
    spicetify -n -q apply || spicetify -n -q backup apply
    ok "Comfy applied"

    # spotify-launcher updates Spotify in place; this re-applies the patch after each update.
    install_file "$REPO/extras/spicetify/spicetify-reapply.path" "$CONFIG_HOME/systemd/user/spicetify-reapply.path"
    install_file "$REPO/extras/spicetify/spicetify-reapply.service" "$CONFIG_HOME/systemd/user/spicetify-reapply.service"
    systemctl --user daemon-reload
    systemctl --user enable --now spicetify-reapply.path >/dev/null 2>&1 && ok "spicetify-reapply.path (user)" \
        || warn "failed: spicetify-reapply.path"

    warn "now add \"spicetify\" to community_ids in ~/.config/noctalia/config.toml (or Settings → Templates)"
}

# ── main ──────────────────────────────────────────────────────────────────────

[[ $DO_PACKAGES -eq 1 ]] && install_packages
[[ $DO_CONFIGS -eq 1 ]] && install_configs
[[ $DO_PLUGINS -eq 1 ]] && install_plugins
[[ $DO_WGSPLIT -eq 1 ]] && install_wgsplit
[[ $DO_GREETER -eq 1 ]] && setup_greeter
[[ $DO_SERVICES -eq 1 ]] && enable_services
[[ $DO_SPICETIFY -eq 1 ]] && install_spicetify

step "Done"
cat <<EOF
  Reboot: greetd shows the Noctalia Greeter with the Umbriel session selected.
  (Without the greeter, log in on a TTY and run: start-umbriel)

  Noctalia starts with Umbriel. Then:
    - noctalia config validate        checks the shell config
    - umbriel config validate         checks the compositor config
    - wgsplit up / wgsplit status     tries the split tunnel
EOF
