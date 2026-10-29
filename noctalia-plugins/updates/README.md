# Updates

Pending pacman and AUR updates for Noctalia.

| Entry | Kind | What it does |
| --- | --- | --- |
| `service` | service | Runs `checkupdates` and `yay -Qua` every `interval_minutes` (60), notifies when the count goes up |
| `bar` | bar widget | Package glyph with the pending count; left click opens the panel, right click checks now |
| `panel` | panel | Totals, last check, the packages from the repositories and the AUR (`old → new`), Upgrade button |

`checkupdates` (from `pacman-contrib`) syncs a temporary copy of the database, so checking never leaves the
system half-synced (no partial upgrades). Upgrade opens `kitty -e yay -Syu`; the terminal and the command are
settings. When the upgrade ends, the script asks the service to check again.

```sh
noctalia msg plugin zmiguel/updates:service all refresh   # also: upgrade
noctalia msg panel-toggle zmiguel/updates:panel
```

Requires `pacman-contrib`; the AUR list needs `yay` (or `paru`, in the `AUR helper` setting).
