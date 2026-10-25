--!nonstrict
-- spotify bar widget: "Artist – Title" next to the Spotify glyph. Left click
-- opens the panel, right click plays/pauses, scrolling skips tracks.

local common = require("./lib/common.luau")

local track = noctalia.state.get(common.STATE_KEY)

local function maxLength()
  return math.clamp(math.floor(tonumber(noctalia.getConfig("max_length")) or 40), 10, 120)
end

local function hideWhenIdle()
  return noctalia.getConfig("hide_when_idle") ~= false
end

local function render()
  local running = type(track) == "table" and track.running == true
  if not running then
    barWidget.setVisible(not hideWhenIdle())
    barWidget.setGlyph("brand-spotify")
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setText("")
    barWidget.setTooltip(noctalia.tr("tooltip.idle"))
    return
  end

  barWidget.setVisible(true)
  local playing = track.status == "Playing"
  local label = track.title or ""
  if track.artist ~= nil and track.artist ~= "" then
    label = `{track.artist} – {label}`
  end
  barWidget.setGlyph(playing and "brand-spotify-filled" or "brand-spotify")
  barWidget.setGlyphColor(playing and "primary" or "on_surface_variant")
  barWidget.setText(common.truncate(label, maxLength()))
  barWidget.setTooltip({
    { noctalia.tr("tooltip.title"), track.title or "" },
    { noctalia.tr("tooltip.artist"), track.artist or "" },
    { noctalia.tr("tooltip.album"), track.album or "" },
  })
end

noctalia.state.watch(common.STATE_KEY, function(value)
  track = value
  render()
end)

function onClick()
  noctalia.togglePanel(common.PANEL_ID)
end

function onRightClick()
  common.control("play-pause")
end

function onScroll(axis, steps, startsGesture)
  if axis ~= "vertical" or not startsGesture then
    return
  end
  common.control(steps > 0 and "next" or "previous")
end

render()
