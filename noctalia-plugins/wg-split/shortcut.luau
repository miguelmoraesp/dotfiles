--!nonstrict
-- wg-split control-center tile: toggles the tunnel; right click opens the panel.

local status = nil

local function render()
  local up = status ~= nil and status.up == true
  shortcut.setLabel(noctalia.tr("shortcut.label"))
  shortcut.setIcon("shield-lock-filled", "shield-off")
  shortcut.setActive(up)
  shortcut.setEnabled(status ~= nil and status.available == true and status.busy ~= true)
end

noctalia.state.watch("wgsplit.status", function(value)
  status = type(value) == "table" and value or nil
  render()
end)

function onClick()
  noctalia.state.set("wgsplit.cmd", { op = "toggle", nonce = math.random() })
end

function onRightClick()
  noctalia.togglePanel("zmiguel/wg-split:panel")
end

status = noctalia.state.get("wgsplit.status")
render()
