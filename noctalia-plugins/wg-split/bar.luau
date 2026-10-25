--!nonstrict
-- wg-split bar widget: shield that mirrors the tunnel state. Left click opens
-- the panel, right click toggles the tunnel.

local status = nil

local function appCount()
  local n = 0
  if status ~= nil and type(status.apps) == "table" then
    for _, app in ipairs(status.apps) do
      n += type(app.pids) == "table" and #app.pids or 0
    end
  end
  return n
end

local function render()
  if status == nil or not status.available then
    barWidget.setGlyph("shield-x")
    barWidget.setGlyphColor("error")
    barWidget.setText("")
    barWidget.setTooltip(status ~= nil and status.error ~= "" and status.error or noctalia.tr("tooltip.unavailable"))
    return
  end

  if status.up then
    barWidget.setGlyph("shield-lock-filled")
    barWidget.setGlyphColor("primary")
    local n = appCount()
    barWidget.setText(n > 0 and tostring(n) or "")
    barWidget.setTooltip({
      { noctalia.tr("tooltip.state"), noctalia.tr("panel.state_up") },
      { noctalia.tr("panel.endpoint"), status.endpoint ~= "" and status.endpoint or "-" },
      { noctalia.tr("tooltip.processes"), tostring(n) },
    })
  elseif status.killswitch then
    barWidget.setGlyph("shield-x")
    barWidget.setGlyphColor("error")
    barWidget.setText("")
    barWidget.setTooltip(noctalia.tr("panel.state_killswitch"))
  else
    barWidget.setGlyph("shield-off")
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setText("")
    barWidget.setTooltip(noctalia.tr("panel.state_down"))
  end
end

noctalia.state.watch("wgsplit.status", function(value)
  status = type(value) == "table" and value or nil
  render()
end)

function onClick()
  noctalia.togglePanel("zmiguel/wg-split:panel")
end

function onRightClick()
  noctalia.state.set("wgsplit.cmd", { op = "toggle", nonce = math.random() })
end

status = noctalia.state.get("wgsplit.status")
render()
