--!nonstrict
-- wg-split launcher provider (`/vpn`): launch a configured app, or any typed
-- command, through the tunnel; also toggles the tunnel and opens the panel.

local TOGGLE_ID = "__toggle"
local PANEL_ID = "__panel"
local RUN_PREFIX = "run:"

local function configuredApps()
  local status = noctalia.state.get("wgsplit.status")
  return type(status) == "table" and type(status.configured) == "table" and status.configured or {}
end

local function scoreFor(query, text)
  if query == "" then
    return 0
  end
  return noctalia.fuzzyScore(query, text)
end

local function buildResults(query)
  local status = noctalia.state.get("wgsplit.status") or {}
  local up = status.up == true
  local results = {}

  local toggleTitle = up and noctalia.tr("launcher.disconnect") or noctalia.tr("launcher.connect")
  local toggleScore = scoreFor(query, toggleTitle)
  if toggleScore ~= nil then
    table.insert(results, {
      id = TOGGLE_ID,
      title = toggleTitle,
      subtitle = up and noctalia.tr("panel.state_up") or noctalia.tr("panel.state_down"),
      glyph = up and "shield-off" or "shield-lock",
      score = toggleScore,
    })
  end

  local panelScore = scoreFor(query, noctalia.tr("launcher.open_panel"))
  if panelScore ~= nil then
    table.insert(results, {
      id = PANEL_ID,
      title = noctalia.tr("launcher.open_panel"),
      glyph = "settings",
      score = panelScore,
    })
  end

  local exact = false
  for _, command in ipairs(configuredApps()) do
    local score = scoreFor(query, command)
    if score ~= nil then
      exact = exact or command == query
      table.insert(results, {
        id = RUN_PREFIX .. command,
        title = noctalia.tr("launcher.run", { command = command }),
        subtitle = noctalia.tr("launcher.configured"),
        glyph = "route",
        score = score + 1,
      })
    end
  end

  if query ~= "" and not exact then
    table.insert(results, {
      id = RUN_PREFIX .. query,
      title = noctalia.tr("launcher.run", { command = query }),
      subtitle = noctalia.tr("launcher.custom"),
      glyph = "terminal-2",
      score = -1,
    })
  end

  table.sort(results, function(a, b)
    return (a.score or 0) > (b.score or 0)
  end)
  return results
end

function onQuery(text)
  launcher.setResults(text, buildResults(noctalia.string.trim(text)))
end

function onActivate(id)
  if id == TOGGLE_ID then
    noctalia.state.set("wgsplit.cmd", { op = "toggle", nonce = math.random() })
  elseif id == PANEL_ID then
    noctalia.togglePanel("zmiguel/wg-split:panel")
  elseif id:sub(1, #RUN_PREFIX) == RUN_PREFIX then
    noctalia.state.set("wgsplit.cmd", { op = "run", arg = id:sub(#RUN_PREFIX + 1), nonce = math.random() })
  end
end
