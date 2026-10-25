--!nonstrict
-- wg-split panel: tunnel switch and stats, configured apps to launch through
-- the tunnel, a free-form command runner, what is in the tunnel right now, and
-- moving an already-running app in. Read-only: every action goes to the
-- service through `wgsplit.cmd`.

local status = noctalia.state.get("wgsplit.status")
local isOpen = false

local runDraft = ""
local runKey = 0
local attachDraft = ""
local attachKey = 0

-- ── helpers ───────────────────────────────────────────────────────────────

local function send(op, arg)
  noctalia.state.set("wgsplit.cmd", { op = op, arg = arg, nonce = math.random() })
end

local function formatBytes(n)
  n = tonumber(n) or 0
  local units = { "B", "KiB", "MiB", "GiB", "TiB" }
  local i = 1
  while n >= 1024 and i < #units do
    n /= 1024
    i += 1
  end
  if i == 1 then
    return string.format("%d %s", n, units[i])
  end
  return string.format("%.1f %s", n, units[i])
end

local function handshakeText(ts)
  ts = tonumber(ts) or 0
  if ts <= 0 then
    return noctalia.tr("panel.never")
  end
  local ago = math.max(0, os.time() - ts)
  if ago < 60 then
    return noctalia.tr("panel.seconds_ago", { n = ago })
  end
  if ago < 3600 then
    return noctalia.tr("panel.minutes_ago", { n = ago // 60 })
  end
  return noctalia.tr("panel.hours_ago", { n = ago // 3600 })
end

local function programOf(command)
  local program = command:match("^(%S+)") or command
  return (program:match("([^/]+)$") or program):lower()
end

local function isRunning(command)
  if status == nil or type(status.apps) ~= "table" then
    return false
  end
  local program = programOf(command)
  for _, app in ipairs(status.apps) do
    local name = string.lower(app.name or "")
    if name ~= "" and (program:sub(1, #name) == name or name:sub(1, #program) == program) then
      return true
    end
  end
  return false
end

local function sectionTitle(text)
  return ui.label({ text = text, fontSize = 12, fontWeight = "bold", color = "on_surface_variant" })
end

local function detailRow(label, value)
  return ui.row({ key = "detail-" .. label, gap = 8, align = "center" }, {
    ui.label({ text = label, fontSize = 12, color = "on_surface_variant", width = 110 }),
    ui.label({ text = value, fontSize = 12, flexGrow = 1, maxLines = 1 }),
  })
end

-- ── sections ──────────────────────────────────────────────────────────────

local function header()
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = "shield-lock", size = 20, color = "primary" }),
    ui.label({ text = noctalia.tr("title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
    ui.button({ glyph = "refresh", variant = "ghost", tooltip = noctalia.tr("panel.refresh"), onClick = function()
      send("refresh")
    end }),
    ui.button({ glyph = "settings", variant = "ghost", tooltip = noctalia.tr("panel.settings"), onClick = function()
      noctalia.openSettings()
    end }),
    ui.button({ glyph = "x", variant = "ghost", onClick = function()
      panel.close()
    end }),
  })
end

local function unavailableCard()
  return ui.column({ gap = 8, padding = 12, radius = 12, fill = "surface_variant/0.6" }, {
    ui.row({ gap = 8, align = "center" }, {
      ui.glyph({ name = "shield-x", size = 18, color = "error" }),
      ui.label({ text = noctalia.tr("panel.unavailable"), fontWeight = "bold", flexGrow = 1 }),
    }),
    ui.label({
      text = status ~= nil and status.error ~= "" and status.error or noctalia.tr("panel.unavailable_hint"),
      fontSize = 12,
      color = "on_surface_variant",
      maxLines = 4,
    }),
  })
end

local function statusCard()
  local up = status.up == true
  local stateText = if up then noctalia.tr("panel.state_up")
    elseif status.killswitch then noctalia.tr("panel.state_killswitch")
    else noctalia.tr("panel.state_down")

  local rows = {
    ui.row({ gap = 10, align = "center" }, {
      ui.box({ width = 10, height = 10, radius = 5, fill = if up then "primary" elseif status.killswitch then "error" else "outline" }),
      ui.label({ text = stateText, fontWeight = "bold", flexGrow = 1 }),
      ui.toggle({
        checked = up,
        enabled = status.busy ~= true,
        onChange = function(value)
          send(value == "true" and "up" or "down")
        end,
      }),
    }),
  }

  if up then
    table.insert(rows, detailRow(noctalia.tr("panel.endpoint"), status.endpoint ~= "" and status.endpoint or "-"))
    table.insert(rows, detailRow(noctalia.tr("panel.handshake"), handshakeText(status.latest_handshake)))
    table.insert(rows, detailRow(noctalia.tr("panel.traffic"),
      `↓ {formatBytes(status.rx_bytes)}   ↑ {formatBytes(status.tx_bytes)}`))
    local servers = type(status.dns_servers) == "table" and status.dns_servers or {}
    local dnsText = if #servers == 0 then noctalia.tr("panel.dns_system")
      elseif status.dns_active then table.concat(servers, ", ")
      else noctalia.tr("panel.dns_down")
    table.insert(rows, detailRow(noctalia.tr("panel.dns"), dnsText))
  elseif status.killswitch then
    table.insert(rows, ui.label({ text = noctalia.tr("panel.killswitch_hint"), fontSize = 12, color = "on_surface_variant", maxLines = 3 }))
    table.insert(rows, ui.button({
      text = noctalia.tr("panel.release"),
      glyph = "shield-off",
      variant = "outline",
      controlSize = "sm",
      enabled = status.busy ~= true,
      onClick = function()
        send("release")
      end,
    }))
  end

  return ui.column({ gap = 8, padding = 12, radius = 12, fill = "surface_variant/0.6" }, rows)
end

local function appsSection()
  local canLaunch = status.up == true or status.killswitch == true
  local rows = { sectionTitle(noctalia.tr("panel.apps")) }
  local apps = type(status.configured) == "table" and status.configured or {}

  if #apps == 0 then
    table.insert(rows, ui.label({ text = noctalia.tr("panel.apps_empty"), fontSize = 12, color = "on_surface_variant", maxLines = 2 }))
  end

  for i, command in ipairs(apps) do
    local running = isRunning(command)
    table.insert(rows, ui.row({ key = `app-{i}-{command}`, gap = 8, align = "center" }, {
      ui.glyph({ name = running and "shield-check" or "apps", size = 16, color = running and "primary" or "on_surface_variant" }),
      ui.label({ text = command, fontSize = 13, flexGrow = 1, maxLines = 1 }),
      ui.button({
        glyph = "player-play",
        variant = "ghost",
        controlSize = "sm",
        enabled = canLaunch,
        tooltip = noctalia.tr("panel.launch"),
        onClick = function()
          send("run", command)
        end,
      }),
    }))
  end

  table.insert(rows, ui.row({ gap = 8, align = "center" }, {
    ui.input({
      key = "run-" .. runKey,
      placeholder = noctalia.tr("panel.run_placeholder"),
      controlSize = "sm",
      flexGrow = 1,
      enabled = canLaunch,
      onChange = function(value)
        runDraft = value
      end,
      onSubmit = function(value)
        runDraft = value
        submitRun()
      end,
    }),
    ui.button({ text = noctalia.tr("panel.run"), variant = "primary", controlSize = "sm", enabled = canLaunch, onClick = "submitRun" }),
  }))

  return ui.column({ gap = 6 }, rows)
end

local function tunnelSection()
  local rows = { sectionTitle(noctalia.tr("panel.in_tunnel")) }
  local apps = type(status.apps) == "table" and status.apps or {}
  if #apps == 0 then
    table.insert(rows, ui.label({ text = noctalia.tr("panel.in_tunnel_empty"), fontSize = 12, color = "on_surface_variant" }))
  end
  for _, app in ipairs(apps) do
    local count = type(app.pids) == "table" and #app.pids or 0
    table.insert(rows, ui.row({ key = "proc-" .. tostring(app.name), gap = 8, align = "center" }, {
      ui.glyph({ name = "route", size = 14, color = "primary" }),
      ui.label({ text = tostring(app.name), fontSize = 13, flexGrow = 1, maxLines = 1 }),
      ui.label({ text = noctalia.trp("panel.processes", count), fontSize = 12, color = "on_surface_variant" }),
    }))
  end
  return ui.column({ gap = 6 }, rows)
end

local function attachSection()
  return ui.column({ gap = 6 }, {
    sectionTitle(noctalia.tr("panel.attach")),
    ui.label({ text = noctalia.tr("panel.attach_hint"), fontSize = 11, color = "on_surface_variant", maxLines = 3 }),
    ui.row({ gap = 8, align = "center" }, {
      ui.input({
        key = "attach-" .. attachKey,
        placeholder = noctalia.tr("panel.attach_placeholder"),
        controlSize = "sm",
        flexGrow = 1,
        onChange = function(value)
          attachDraft = value
        end,
        onSubmit = function(value)
          attachDraft = value
          submitAttach()
        end,
      }),
      ui.button({ text = noctalia.tr("panel.attach_button"), variant = "outline", controlSize = "sm", onClick = "submitAttach" }),
    }),
  })
end

-- ── render ────────────────────────────────────────────────────────────────

local function render()
  if not isOpen then
    return
  end
  local body
  if status == nil or not status.available then
    body = { unavailableCard() }
  else
    body = {
      statusCard(),
      appsSection(),
      ui.separator({}),
      tunnelSection(),
      ui.separator({}),
      attachSection(),
    }
  end
  panel.render(ui.column({ gap = 14, flexGrow = 1 }, {
    header(),
    ui.scroll({ gap = 14, flexGrow = 1 }, body),
  }))
end

function submitRun()
  local command = noctalia.string.trim(runDraft)
  if command == "" then
    return
  end
  send("run", command)
  runDraft = ""
  runKey += 1
  render()
end

function submitAttach()
  local target = noctalia.string.trim(attachDraft)
  if target == "" then
    return
  end
  send("attach", target)
  attachDraft = ""
  attachKey += 1
  render()
end

noctalia.state.watch("wgsplit.status", function(value)
  status = type(value) == "table" and value or nil
  render()
end)

function onOpen()
  isOpen = true
  status = noctalia.state.get("wgsplit.status")
  panel.setWantsSecondTicks(true)
  send("refresh")
  render()
end

function onClose()
  isOpen = false
end

function update()
  render()
end
