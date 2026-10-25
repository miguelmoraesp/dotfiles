--!nonstrict
-- spotify panel: artwork, track info, a seek slider, playback controls, and
-- shortcuts to show Spotify's scratchpad, copy the track link, or start
-- Spotify through the WireGuard split tunnel.

local common = require("./lib/common.luau")

local track = noctalia.state.get(common.STATE_KEY)
local isOpen = false
local seeking = nil

local function showVpn()
  return noctalia.getConfig("show_vpn_launch") ~= false
end

local function header()
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = "brand-spotify", size = 20, color = "primary" }),
    ui.label({ text = "Spotify", fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
    ui.button({ glyph = "x", variant = "ghost", onClick = function()
      panel.close()
    end }),
  })
end

local function idleView()
  local buttons = {
    ui.button({ text = noctalia.tr("panel.open"), glyph = "brand-spotify", variant = "primary", onClick = function()
      common.toggleWindow()
      panel.close()
    end }),
  }
  if showVpn() then
    table.insert(buttons, ui.button({ text = noctalia.tr("panel.open_vpn"), glyph = "shield-lock", variant = "outline", onClick = function()
      common.launchThroughVpn()
      panel.close()
    end }))
  end

  return ui.column({ gap = 12, align = "center", justify = "center", flexGrow = 1 }, {
    ui.glyph({ name = "music", size = 48, color = "on_surface_variant" }),
    ui.label({
      text = type(track) == "table" and track.error or noctalia.tr("panel.not_running"),
      color = "on_surface_variant",
      maxLines = 3,
      textAlign = "center",
    }),
    ui.column({ gap = 8, align = "stretch", width = 240 }, buttons),
  })
end

local function artwork()
  if type(track.artPath) == "string" and track.artPath ~= "" then
    return ui.image({ key = "art", path = track.artPath, width = 240, height = 240, radius = 14, fit = "cover" })
  end
  return ui.column({ key = "art", width = 240, height = 240, radius = 14, fill = "surface_variant", align = "center", justify = "center" }, {
    ui.glyph({ name = "music", size = 56, color = "on_surface_variant" }),
  })
end

local function progress()
  local length = tonumber(track.length) or 0
  local position = seeking or tonumber(track.position) or 0
  if length <= 0 then
    return ui.spacer({ height = 4 })
  end
  return ui.column({ gap = 2 }, {
    ui.slider({
      min = 0,
      max = length,
      step = 1,
      value = math.min(position, length),
      controlSize = "sm",
      onChange = function(value)
        seeking = tonumber(value)
      end,
      onDragEnd = function(value)
        local target = tonumber(value) or seeking
        seeking = nil
        if target ~= nil then
          common.seek(target)
        end
      end,
    }),
    ui.row({ align = "center" }, {
      ui.label({ text = common.formatTime(position), fontSize = 11, color = "on_surface_variant", flexGrow = 1 }),
      ui.label({ text = common.formatTime(length), fontSize = 11, color = "on_surface_variant" }),
    }),
  })
end

local function controls()
  local playing = track.status == "Playing"
  return ui.row({ gap = 12, align = "center", justify = "center" }, {
    ui.button({ glyph = "player-skip-back", variant = "ghost", controlSize = "lg", onClick = function()
      common.control("previous")
    end }),
    ui.button({
      glyph = playing and "player-pause-filled" or "player-play-filled",
      variant = "primary",
      controlSize = "lg",
      onClick = function()
        common.control("play-pause")
      end,
    }),
    ui.button({ glyph = "player-skip-forward", variant = "ghost", controlSize = "lg", onClick = function()
      common.control("next")
    end }),
  })
end

local function actions()
  local buttons = {
    ui.button({ glyph = "external-link", variant = "outline", controlSize = "sm", tooltip = noctalia.tr("panel.show_window"), onClick = function()
      common.toggleWindow()
      panel.close()
    end }),
    ui.button({
      glyph = "link",
      variant = "outline",
      controlSize = "sm",
      enabled = track.url ~= nil,
      tooltip = noctalia.tr("panel.copy_link"),
      onClick = function()
        if track.url ~= nil and noctalia.copyToClipboard(track.url, "text/plain") then
          noctalia.notify("Spotify", noctalia.tr("panel.link_copied"))
        end
      end,
    }),
  }
  if showVpn() then
    table.insert(buttons, ui.button({ glyph = "shield-lock", variant = "outline", controlSize = "sm", tooltip = noctalia.tr("panel.restart_vpn"), onClick = function()
      common.launchThroughVpn()
    end }))
  end
  return ui.row({ gap = 8, align = "center", justify = "center" }, buttons)
end

local function playingView()
  return ui.column({ gap = 12, flexGrow = 1 }, {
    ui.row({ justify = "center" }, { artwork() }),
    ui.column({ gap = 2 }, {
      ui.label({ text = track.title or "", fontSize = 16, fontWeight = "bold", maxLines = 2, textAlign = "center" }),
      ui.label({ text = track.artist or "", fontSize = 13, color = "on_surface_variant", maxLines = 1, textAlign = "center" }),
      ui.label({ text = track.album or "", fontSize = 11, color = "on_surface_variant", maxLines = 1, textAlign = "center" }),
    }),
    progress(),
    controls(),
    actions(),
  })
end

local function render()
  if not isOpen then
    return
  end
  local running = type(track) == "table" and track.running == true
  panel.render(ui.column({ gap = 12, flexGrow = 1 }, {
    header(),
    running and playingView() or idleView(),
  }))
end

noctalia.state.watch(common.STATE_KEY, function(value)
  track = value
  render()
end)

function onOpen()
  isOpen = true
  seeking = nil
  track = noctalia.state.get(common.STATE_KEY)
  render()
end

function onClose()
  isOpen = false
end
