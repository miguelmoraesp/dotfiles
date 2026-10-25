#!/usr/bin/env bash
# Instala o ambiente Umbriel + Noctalia numa instalação limpa do Arch.
#
#   ./install.sh                       tudo
#   ./install.sh --wg-conf ~/proton.conf   também instala a config do WireGuard
#   ./install.sh --no-packages         só configs, plugins e wgsplit
#   ./install.sh --spicetify           tema do Spotify via Spicetify (abra o Spotify uma vez antes)
#
# Opções: --no-packages --no-configs --no-plugins --no-wgsplit --no-services
#         --wg-conf <arquivo> --spicetify --help
#
# Rode como seu usuário (não root); o sudo é pedido quando preciso.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
STAMP="$(date +%Y%m%d-%H%M%S)"

DO_PACKAGES=1
DO_CONFIGS=1
DO_PLUGINS=1
DO_WGSPLIT=1
DO_SERVICES=1
DO_SPICETIFY=0
WG_CONF=""

c_info=$'\e[1;34m' c_ok=$'\e[1;32m' c_warn=$'\e[1;33m' c_err=$'\e[1;31m' c_off=$'\e[0m'
step() { printf '\n%s==>%s %s\n' "$c_info" "$c_off" "$*"; }
ok() { printf '  %s✓%s %s\n' "$c_ok" "$c_off" "$*"; }
warn() { printf '  %s!%s %s\n' "$c_warn" "$c_off" "$*" >&2; }
die() {
    printf '%serro:%s %s\n' "$c_err" "$c_off" "$*" >&2
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
        --no-services) DO_SERVICES=0 ;;
        --spicetify) DO_SPICETIFY=1 ;;
        --wg-conf)
            [[ $# -ge 2 ]] || die "--wg-conf precisa de um arquivo"
            WG_CONF="$2"
            shift
            ;;
        -h | --help) usage 0 ;;
        *)
            warn "opção desconhecida: $1"
            usage 2
            ;;
    esac
    shift
done

[[ $EUID -ne 0 ]] || die "rode como seu usuário, não como root"
[[ -f /etc/arch-release ]] || die "este script é para Arch Linux"
command -v sudo >/dev/null || die "instale o sudo e coloque seu usuário no grupo wheel"
if [[ -n "$WG_CONF" && ! -f "$WG_CONF" ]]; then
    die "config do WireGuard não encontrada: $WG_CONF"
fi

# Lê uma lista de pacotes ignorando comentários e linhas vazias.
read_list() {
    sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e '/^$/d' "$1"
}

# Copia um arquivo para o destino; se já existir algo diferente, guarda um backup.
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

aur_helper() {
    if command -v paru >/dev/null; then
        echo paru
    elif command -v yay >/dev/null; then
        echo yay
    fi
}

# ── pacotes ───────────────────────────────────────────────────────────────────

install_packages() {
    step "Pacotes oficiais"
    mapfile -t pkgs < <(read_list "$REPO/packages/pacman.txt")
    sudo pacman -Syu --needed --noconfirm "${pkgs[@]}"
    ok "${#pkgs[@]} pacotes do pacman"

    step "Pacotes do AUR"
    local helper
    helper="$(aur_helper)"
    if [[ -z "$helper" ]]; then
        local tmp
        tmp="$(mktemp -d)"
        git clone --depth 1 https://aur.archlinux.org/paru-bin.git "$tmp/paru-bin"
        (cd "$tmp/paru-bin" && makepkg -si --noconfirm)
        rm -rf "$tmp"
        helper=paru
        ok "paru instalado"
    fi
    mapfile -t aur < <(read_list "$REPO/packages/aur.txt")
    "$helper" -S --needed --noconfirm "${aur[@]}"
    ok "${#aur[@]} pacotes do AUR com $helper"
}

# ── configs ───────────────────────────────────────────────────────────────────

install_configs() {
    step "Configs em $CONFIG_HOME"
    local src rel count=0
    while IFS= read -r -d '' src; do
        rel="${src#"$REPO/config/"}"
        install_file "$src" "$CONFIG_HOME/$rel"
        count=$((count + 1))
    done < <(find "$REPO/config" -type f -print0)
    ok "$count arquivos copiados (os templates do Noctalia editam alguns deles, por isso são cópias e não links)"

    mkdir -p "$HOME/wallpapers"
    if command -v xdg-user-dirs-update >/dev/null; then
        xdg-user-dirs-update
    fi
    if [[ ! -f "$HOME/wallpapers/blackhole.png" ]]; then
        warn "coloque seus wallpapers em ~/wallpapers (a config usa ~/wallpapers/blackhole.png)"
    fi
}

# ── plugins do Noctalia ───────────────────────────────────────────────────────

install_plugins() {
    step "Plugins do Noctalia em $DATA_HOME/noctalia/plugins"
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

# ── wgsplit (split tunnel WireGuard) ──────────────────────────────────────────

install_wgsplit() {
    step "wgsplit (split tunnel por aplicativo)"
    install -Dm755 "$REPO/wgsplit/wgsplit" "$HOME/.local/bin/wgsplit"
    ok "~/.local/bin/wgsplit"

    sudo install -Dm755 -o root -g root "$REPO/wgsplit/wgsplit-root" /usr/local/bin/wgsplit-root
    ok "/usr/local/bin/wgsplit-root"

    # Só o helper root, só para este usuário, sem senha: é o que o plugin usa.
    local sudoers
    sudoers="$(mktemp)"
    printf '%s ALL=(root) NOPASSWD: /usr/local/bin/wgsplit-root\n' "$USER" > "$sudoers"
    if sudo visudo -cqf "$sudoers"; then
        sudo install -Dm440 -o root -g root "$sudoers" /etc/sudoers.d/wgsplit
        ok "/etc/sudoers.d/wgsplit"
    else
        warn "sudoers gerado é inválido; pulei /etc/sudoers.d/wgsplit"
    fi
    rm -f "$sudoers"

    if [[ -n "$WG_CONF" ]]; then
        sudo install -Dm600 -o root -g root "$WG_CONF" /etc/wireguard/wgsplit.conf
        ok "/etc/wireguard/wgsplit.conf"
    elif ! sudo test -f /etc/wireguard/wgsplit.conf; then
        warn "falta a config do WireGuard: sudo install -Dm600 sua.conf /etc/wireguard/wgsplit.conf"
    fi

    # Perfil separado: um Firefox já aberto não entra no túnel, uma instância nova com outro perfil entra.
    if command -v firefox >/dev/null \
        && ! grep -qs '^Name=vpn$' "$HOME/.mozilla/firefox/profiles.ini" "$CONFIG_HOME/mozilla/firefox/profiles.ini"; then
        firefox --headless -CreateProfile vpn >/dev/null 2>&1 && ok "perfil 'vpn' do Firefox criado" \
            || warn "não consegui criar o perfil 'vpn' do Firefox (crie com: firefox -P)"
    fi
}

# ── serviços ──────────────────────────────────────────────────────────────────

enable_services() {
    step "Serviços"
    local unit
    for unit in NetworkManager.service bluetooth.service power-profiles-daemon.service; do
        if systemctl list-unit-files "$unit" >/dev/null 2>&1; then
            sudo systemctl enable --now "$unit" >/dev/null 2>&1 && ok "$unit" || warn "falhou: $unit"
        fi
    done

    systemctl --user daemon-reload
    for unit in pipewire-pulse.socket wireplumber.service gnome-keyring-daemon.socket; do
        systemctl --user enable --now "$unit" >/dev/null 2>&1 && ok "$unit (usuário)" || warn "falhou: $unit"
    done
    if [[ $DO_WGSPLIT -eq 1 ]]; then
        systemctl --user enable --now wgsplit-anchor.service >/dev/null 2>&1 && ok "wgsplit-anchor.service (usuário)" \
            || warn "falhou: wgsplit-anchor.service"
    fi
}

# ── spicetify (opcional) ──────────────────────────────────────────────────────

install_spicetify() {
    step "Spicetify (tema do Spotify gerado pelo Noctalia)"
    local helper spotify_dir="$DATA_HOME/spotify-launcher/install/usr/share/spotify"
    helper="$(aur_helper)"
    [[ -n "$helper" ]] || die "instale os pacotes antes (precisa de paru ou yay)"
    "$helper" -S --needed --noconfirm spicetify-cli

    [[ -d "$spotify_dir" ]] || die "abra o Spotify uma vez (spotify-launcher) e rode de novo com --spicetify"
    [[ -f "$CONFIG_HOME/spotify/prefs" ]] || die "faça login no Spotify uma vez e rode de novo com --spicetify"

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
    spicetify backup apply >/dev/null 2>&1 || spicetify apply >/dev/null
    ok "Comfy aplicado"
    warn "agora adicione \"spicetify\" em community_ids no ~/.config/noctalia/config.toml (ou em Settings → Templates)"
}

# ── main ──────────────────────────────────────────────────────────────────────

[[ $DO_PACKAGES -eq 1 ]] && install_packages
[[ $DO_CONFIGS -eq 1 ]] && install_configs
[[ $DO_PLUGINS -eq 1 ]] && install_plugins
[[ $DO_WGSPLIT -eq 1 ]] && install_wgsplit
[[ $DO_SERVICES -eq 1 ]] && enable_services
[[ $DO_SPICETIFY -eq 1 ]] && install_spicetify

step "Pronto"
cat <<EOF
  Entre no Umbriel pelo TTY com:  start-umbriel
  (ou escolha a sessão "Umbriel" no seu display manager)

  O Noctalia sobe sozinho (autostart do Umbriel). Depois:
    - noctalia config validate        confere a config do shell
    - umbriel config validate         confere a config do compositor
    - wgsplit up / wgsplit status     testa o split tunnel
EOF
