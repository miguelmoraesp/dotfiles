# dotfiles — Arch + Umbriel + Noctalia

Ambiente Wayland em cima do [Umbriel](https://github.com/noctalia-dev/umbriel) (compositor) com o
[Noctalia](https://github.com/noctalia-dev/noctalia) v5 como shell. O Noctalia substitui sozinho o que antes
eram waybar, rofi, dunst, hyprpaper/waypaper, powermenu e flameshot: barra, launcher, notificações, wallpaper,
lock screen, OSD, clipboard e prints.

## Instalação

Numa instalação limpa do Arch, com seu usuário no grupo `wheel`:

```sh
git clone <este repo> ~/dotfiles && cd ~/dotfiles
./install.sh --wg-conf ~/Downloads/minha-vpn.conf   # sem --wg-conf se não for usar o split tunnel agora
start-umbriel                                       # a partir do TTY
```

O `install.sh`:

1. instala os pacotes de `packages/pacman.txt` e, via `paru` (instalado se faltar), os de `packages/aur.txt`;
2. copia tudo de `config/` para `~/.config/` (arquivos diferentes viram `*.bak-<data>` antes);
3. copia os plugins de `noctalia-plugins/` para `~/.local/share/noctalia/plugins/`;
4. instala o `wgsplit` (CLI, helper root, regra de sudoers e a config do WireGuard);
5. habilita NetworkManager, bluetooth, power-profiles-daemon, pipewire e o `wgsplit-anchor.service`.

Opções: `--no-packages`, `--no-configs`, `--no-plugins`, `--no-wgsplit`, `--no-services`, `--wg-conf <arquivo>`,
`--spicetify`. Rodar de novo é seguro, então use `./install.sh --no-packages` para reaplicar as configs.

As configs são **copiadas**, não linkadas: os templates de tema do Noctalia reescrevem `umbriel/config.toml`,
`kitty/kitty.conf`, `starship.toml` e o `gtk.css`, e com symlink essas edições cairiam dentro do repo.

## Estrutura

| Caminho | O quê |
| --- | --- |
| `config/umbriel/config.toml` | Compositor: atalhos, regras de janela, scratchpads, blur |
| `config/noctalia/config.toml` | Shell: barra, tema, templates, wallpaper, idle, plugins |
| `config/kitty`, `config/starship.toml`, `config/gtk-*` | Apps; as cores vêm dos templates do Noctalia |
| `config/environment.d/10-wayland.conf` | Variáveis da sessão (Qt/Electron em Wayland, cursor, `~/.local/bin` no PATH) |
| `config/spotify-launcher.conf` | Spotify em Wayland nativo |
| `config/systemd/user/wgsplit-anchor.service` | Mantém o `wgsplit.slice` vivo |
| `noctalia-plugins/wg-split` | Plugin do split tunnel WireGuard |
| `noctalia-plugins/spotify` | Plugin do Spotify |
| `wgsplit/` | CLI `wgsplit` e o helper root `wgsplit-root` |
| `packages/` | Listas de pacotes |

## Atalhos

Os atalhos do `hyprland.conf` antigo foram mantidos. `Mod` é a tecla Super.

| Atalho | Ação |
| --- | --- |
| `Mod` (sozinho) / `Mod+R` | Launcher |
| `Mod+Q` / `Mod+Return` | Kitty |
| `Mod+C` / `Mod+Shift+C` | Fechar / matar janela |
| `Mod+E` · `Mod+B` | Dolphin · Firefox |
| `Mod+V` · `Mod+F` · `Mod+P` | Flutuar · tela cheia · fixar por cima |
| `Mod+T` · `Mod+Alt+L` | Inverter split (dwindle) · alternar dwindle/scrolling |
| `Mod+setas` / `Mod+HJKL` | Foco; com `Shift` move, com `Ctrl` troca |
| `Mod+1..0` / `Mod+Shift+1..0` | Ir para workspace / mover janela |
| `Mod+O` ou canto superior esquerdo | Overview |
| `Mod+A` · `Mod+N` · `Mod+M` | Control center · settings do Noctalia · menu de sessão |
| `Mod+Shift+S` / `Print` | Print de região (`Mod+Print` tela inteira, `Mod+Shift+A` anotar) |
| `Mod+Shift+V` · `Mod+Shift+P` | Clipboard · wallpaper |
| `Mod+Shift+L` | Bloquear a tela |
| `Mod+Space` / `Mod+Shift+Space` | Scratchpad geral: mostrar / mandar janela |
| `Mod+S` | Scratchpad do Spotify (abre o Spotify se estiver fechado) |
| `Mod+Shift+M` | Painel do Spotify |
| `Mod+W` / `Mod+Shift+W` | Painel do split tunnel / ligar e desligar o túnel |
| `Mod+F1` | Cola de atalhos do Umbriel |
| `Alt+Tab` | Alternador de janelas |

Workspaces fixos herdados: editores no 1, Firefox no 2, Discord no 7. O Spotify vai para o scratchpad `music`.

## Split tunnel WireGuard (`wgsplit` + plugin `zmiguel/wg-split`)

Só os apps que você escolher passam pela VPN; o resto continua na conexão normal.

```
app aberto com `wgsplit run`  →  scope no wgsplit.slice (systemd --user)
nftables: socket cgroupv2 == wgsplit.slice  →  fwmark 0x5157
ip rule fwmark 0x5157  →  tabela 5157  →  default dev wgsplit
```

- **Ligar/desligar:** botão da barra (clique direito), tile do control center, `Mod+Shift+W`, painel (`Mod+W`)
  ou `wgsplit up` / `wgsplit down`.
- **Abrir app pela VPN:** botão ▶ no painel, `/vpn <app>` no launcher, ou `wgsplit run <comando>`.
  Os apps fixos ficam na configuração `Apps` do plugin (padrão: `spotify-launcher` e
  `firefox --new-instance -P vpn`).
- **Mover um app já aberto:** campo "Mover app já aberto" do painel, ou `wgsplit attach spotify`.
  Só as conexões novas entram no túnel; reconectar resolve.
- **Kill switch** (ligado por padrão): ao desligar o túnel, os apps dele ficam sem rede em vez de vazarem pela
  conexão normal. "Liberar apps" no painel (ou `wgsplit down` sem `--keep-killswitch`) remove o bloqueio.
- **LAN:** os apps do túnel continuam enxergando a rede local (`ALLOW_LAN=0` em `/etc/wgsplit.env` desliga).

Config do WireGuard em `/etc/wireguard/wgsplit.conf` (a do seu provedor serve). `DNS`, `Table` e
`PostUp`/`PostDown` são ignorados, porque o `wgsplit-root` não usa o `wg-quick up`.

Limitações:

- **DNS não passa pelo túnel:** as consultas saem pelo `systemd-resolved`, que fica fora do slice. Se isso
  importa, use DNS-over-HTTPS no app (o Firefox tem a opção nas configurações).
- **App já aberto não entra pelo `run`:** chamar `firefox` com o Firefox aberto só cria uma janela no
  processo antigo, que está fora do túnel. Por isso o padrão é `--new-instance -P vpn` (o install cria o perfil).
- O `sudoers` libera **apenas** `/usr/local/bin/wgsplit-root` sem senha, e só para o seu usuário.

## Spotify (plugin `zmiguel/spotify`)

- Widget na barra com artista e música (clique abre o painel, clique direito pausa, scroll troca a faixa).
- Painel com capa, barra de progresso com seek, controles, copiar link, mostrar a janela e "abrir pela VPN".
- O Spotify roda no scratchpad `music` do Umbriel (`Mod+S`), que abre o app sozinho se ele estiver fechado.
  Para ele sempre sair pela VPN, troque o `spawn_when_empty` em `config/umbriel/config.toml` por
  `wgsplit run spotify-launcher`.
- Tema: `./install.sh --no-packages --spicetify` (abra e logue no Spotify uma vez antes) instala o Spicetify com o
  tema Comfy; depois adicione `"spicetify"` em `community_ids` para as cores seguirem o Noctalia.

## Tema

Cores vêm do Noctalia (`[theme]` em `config/noctalia/config.toml`) e são aplicadas pelos templates `umbriel`,
`kitty`, `gtk3`, `gtk4`, `qt`, `btop` e `starship`. Para o tema seguir o wallpaper, use
`source = "wallpaper"` (sugestão: `wallpaper_scheme = "m3-monochrome"`, perto do cinza do setup antigo).

## Problemas comuns

| Sintoma | Onde olhar |
| --- | --- |
| Config do Noctalia "não pega" | `~/.local/state/noctalia/settings.toml` (a GUI tem prioridade) e `noctalia config validate` |
| Atalho não funciona | `umbriel config validate`; atalhos do Noctalia: `noctalia msg ...` no terminal |
| Logs do Noctalia | `~/.cache/noctalia/noctalia.log` |
| Plugin não aparece | `noctalia msg plugins list`; habilite com `noctalia msg plugins enable zmiguel/wg-split` |
| `wgsplit up` falha | `sudo -n /usr/local/bin/wgsplit-root up $(id -u)` mostra o erro; confira `/etc/wireguard/wgsplit.conf` |
| App não sai pela VPN | `wgsplit status` lista o que está no slice; `curl ifconfig.me` vs `wgsplit run curl ifconfig.me` |
