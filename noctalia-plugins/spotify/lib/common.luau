--!nonstrict
-- Helpers shared by the spotify entries. Each entry requires its own copy, so
-- nothing here holds state.

local M = {}

M.STATE_KEY = "spotify.track"
M.PANEL_ID = "zmiguel/spotify:panel"

function M.player()
  local name = noctalia.getConfig("player")
  if type(name) ~= "string" or not name:match("^[%w%._%-]+$") then
    return "spotify"
  end
  return name
end

function M.control(action)
  noctalia.runAsync({ "playerctl", "-p", M.player(), action })
end

function M.seek(seconds)
  noctalia.runAsync({ "playerctl", "-p", M.player(), "position", string.format("%.0f", math.max(0, seconds)) })
end

local function launchCommand()
  local command = noctalia.getConfig("launch_command")
  if type(command) ~= "string" or noctalia.string.trim(command) == "" then
    return "spotify-launcher"
  end
  return noctalia.string.trim(command)
end

-- Shows or hides Spotify's scratchpad. Umbriel's spawn_when_empty starts
-- Spotify when the scratchpad has no window yet.
function M.toggleWindow()
  local pad = noctalia.getConfig("scratchpad")
  if type(pad) == "string" and pad:match("^[%w%._%-]+$") and noctalia.commandExists("umbriel") then
    noctalia.runAsync({ "umbriel", "msg", "scratchpad-toggle:" .. pad })
  else
    noctalia.runAsync(launchCommand())
  end
end

-- Hands the launch to the zmiguel/wg-split service, which refuses it (with a
-- notification) when the tunnel is off.
function M.launchThroughVpn()
  noctalia.runAsync({ "noctalia", "msg", "plugin", "zmiguel/wg-split:service", "all", "run", launchCommand() })
end

function M.formatTime(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  local h = seconds // 3600
  local m = (seconds % 3600) // 60
  local s = seconds % 60
  if h > 0 then
    return string.format("%d:%02d:%02d", h, m, s)
  end
  return string.format("%d:%02d", m, s)
end

function M.truncate(text, maxChars)
  local len = utf8.len(text)
  if len == nil then
    len = #text
    if len <= maxChars then
      return text
    end
    return text:sub(1, maxChars - 1) .. "…"
  end
  if len <= maxChars then
    return text
  end
  return text:sub(1, utf8.offset(text, maxChars) - 1) .. "…"
end

return M
