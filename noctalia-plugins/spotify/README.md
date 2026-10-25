# Spotify

Spotify now-playing widget and panel for Noctalia on Umbriel.

| Entry | Kind | What it does |
| --- | --- | --- |
| `service` | service | Follows `playerctl --follow`, polls the position, caches album art |
| `bar` | bar widget | `Artist – Title`; left click opens the panel, right click plays/pauses, scroll skips |
| `panel` | panel | Artwork, seek slider, controls, show window, copy link, start through the VPN |

"Show window" toggles the Umbriel scratchpad named in the `scratchpad` setting (`music`); a scratchpad with
`spawn_when_empty = "spotify-launcher"` starts Spotify when it is closed. "Through the VPN" asks the
`zmiguel/wg-split` service to run the launch command in the tunnel.

```sh
noctalia msg plugin zmiguel/spotify:service all play-pause   # also: next, previous, window, vpn
noctalia msg panel-toggle zmiguel/spotify:panel
```

Requires `playerctl` and `spotify-launcher`. Spotify's MPRIS does not expose shuffle, repeat or volume
reliably on Linux, so the panel does not offer them.
