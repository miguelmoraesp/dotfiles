--!nonstrict
-- wg-split service: the only entry that talks to the `wgsplit` CLI. It polls
-- `wgsplit status --json`, publishes the result as `wgsplit.status`, and runs
-- the commands the bar, panel, shortcut and launcher send through `wgsplit.cmd`.

local STATUS_KEY = "wgsplit.status"
local CMD_KEY = "wgsplit.cmd"

local status = {
  available = false,
  up = false,
  killswitch = false,
  busy = false,
  endpoint = "",
  latest_handshake = 0,
  rx_bytes = 0,
  tx_bytes = 0,
  dns_servers = {},
  dns_active = false,
  apps = {},
  error = "",
}
local busy = false
local polling = false
local firstPoll = true

-- ── helpers ───────────────────────────────────────────────────────────────

local function log(msg)
  noctalia.log(`wg-split: {msg}`)
end

local function trim(s)
  return noctalia.string.trim(s or "")
end

local function firstLine(s)
  s = trim(s)
  local nl = s:find("\n")
  if nl ~= nil then
    return s:sub(1, nl - 1)
  end
  return s
end

local function cfgBool(key, default)
  local v = noctalia.getConfig(key)
  if type(v) == "boolean" then
    return v
  end
  return default
end

local function pollSeconds()
  local v = tonumber(noctalia.getConfig("poll_interval_seconds")) or 5
  return math.clamp(math.floor(v), 2, 60)
end

local function cliPath()
  local path = noctalia.getConfig("cli")
  if type(path) ~= "string" or trim(path) == "" then
    path = "~/.local/bin/wgsplit"
  end
  return noctalia.expandPath(trim(path))
end

-- Published with the status so the launcher, which may not see plugin settings, can list them.
local function configuredApps()
  local apps = noctalia.getConfig("apps")
  local list = {}
  if type(apps) == "table" then
    for _, command in ipairs(apps) do
      if type(command) == "string" and trim(command) ~= "" then
        table.insert(list, trim(command))
      end
    end
  end
  return list
end

local function publish()
  status.busy = busy
  status.configured = configuredApps()
  noctalia.state.set(STATUS_KEY, status)
end

local function notifyChange(wasUp, wasKillswitch)
  if not cfgBool("notify", true) or firstPoll then
    return
  end
  if status.up and not wasUp then
    noctalia.notify(noctalia.tr("title"), noctalia.tr("notifications.up"))
  elseif not status.up and wasUp then
    noctalia.notify(noctalia.tr("title"), status.killswitch and noctalia.tr("notifications.down_killswitch")
      or noctalia.tr("notifications.down"))
  elseif wasKillswitch and not status.killswitch and not status.up then
    noctalia.notify(noctalia.tr("title"), noctalia.tr("notifications.released"))
  end
end

local function failError(msg)
  status.available = false
  status.error = msg
  publish()
end

-- ── polling ───────────────────────────────────────────────────────────────

local refresh
local handle

local function maybeAutoUp()
  if firstPoll and cfgBool("auto_up", false) and status.available and not status.up then
    log("auto_up enabled; bringing the tunnel up")
    handle("up")
  end
  firstPoll = false
end

refresh = function()
  if polling then
    return
  end
  local cli = cliPath()
  if not noctalia.fileExists(cli) then
    failError(noctalia.tr("errors.cli_missing", { path = cli }))
    firstPoll = false
    return
  end
  polling = true
  local accepted = noctalia.runAsync({ cli, "status", "--json" }, function(res)
    polling = false
    if res.exitCode ~= 0 then
      failError(firstLine(res.stderr ~= "" and res.stderr or res.stdout))
      firstPoll = false
      return
    end
    local data = noctalia.json.decode(res.stdout)
    if type(data) ~= "table" then
      failError(noctalia.tr("errors.bad_status"))
      firstPoll = false
      return
    end
    local wasUp, wasKillswitch = status.up, status.killswitch
    status.available = true
    status.error = ""
    status.up = data.up == true
    status.killswitch = data.killswitch == true
    status.endpoint = type(data.endpoint) == "string" and data.endpoint or ""
    status.latest_handshake = tonumber(data.latest_handshake) or 0
    status.rx_bytes = tonumber(data.rx_bytes) or 0
    status.tx_bytes = tonumber(data.tx_bytes) or 0
    status.dns_servers = type(data.dns_servers) == "table" and data.dns_servers or {}
    status.dns_active = data.dns_active == true
    status.apps = type(data.apps) == "table" and data.apps or {}
    if type(data.stats_error) == "string" and data.stats_error ~= "" then
      log("stats: " .. firstLine(data.stats_error))
    end
    notifyChange(wasUp, wasKillswitch)
    publish()
    maybeAutoUp()
  end, 10000)
  if not accepted then
    polling = false
    log("failed to start " .. cli)
  end
end

-- ── commands ──────────────────────────────────────────────────────────────

local function runCli(args)
  if busy then
    return
  end
  busy = true
  publish()
  local argv = { cliPath() }
  for _, a in ipairs(args) do
    table.insert(argv, a)
  end
  local accepted = noctalia.runAsync(argv, function(res)
    busy = false
    if res.exitCode ~= 0 or res.timedOut then
      local msg = firstLine(res.stderr ~= "" and res.stderr or res.stdout)
      noctalia.notifyError(noctalia.tr("title"), msg ~= "" and msg or noctalia.tr("errors.command_failed"))
    elseif args[1] == "attach" and cfgBool("notify", true) then
      noctalia.notify(noctalia.tr("title"), noctalia.tr("notifications.attached", { target = args[2] or "" }))
    end
    publish()
    refresh()
  end, 30000)
  if not accepted then
    busy = false
    publish()
    noctalia.notifyError(noctalia.tr("title"), noctalia.tr("errors.command_failed"))
  end
end

local function downArgs()
  if cfgBool("kill_switch", true) then
    return { "down", "--keep-killswitch" }
  end
  return { "down" }
end

-- `wgsplit run` blocks for the app's whole lifetime (it execs systemd-run
-- --scope), so it is started detached; everything it would reject is checked here.
local function launch(command)
  command = trim(command)
  if command == "" then
    return
  end
  local program = command:match("^(%S+)")
  if program == nil or not noctalia.commandExists(program) then
    noctalia.notifyError(noctalia.tr("title"), noctalia.tr("errors.not_found", { command = program or command }))
    return
  end
  if not status.up and not status.killswitch then
    noctalia.notifyError(noctalia.tr("title"), noctalia.tr("errors.tunnel_down", { command = program }))
    return
  end
  if not noctalia.runAsync({ cliPath(), "run", "sh", "-c", command }) then
    noctalia.notifyError(noctalia.tr("title"), noctalia.tr("errors.command_failed"))
    return
  end
  if cfgBool("notify", true) then
    noctalia.notify(noctalia.tr("title"), noctalia.tr("notifications.launched", { command = program }))
  end
end

handle = function(op, arg)
  if op == "up" then
    runCli({ "up" })
  elseif op == "down" then
    runCli(downArgs())
  elseif op == "release" then
    runCli({ "down" })
  elseif op == "toggle" then
    if status.up then
      runCli(downArgs())
    else
      runCli({ "up" })
    end
  elseif op == "run" then
    launch(arg or "")
  elseif op == "attach" then
    arg = trim(arg)
    if arg ~= "" then
      runCli({ "attach", arg })
    end
  elseif op == "refresh" then
    refresh()
  else
    log("unknown command: " .. tostring(op))
  end
end

noctalia.state.watch(CMD_KEY, function(cmd)
  if type(cmd) == "table" then
    noctalia.state.set(CMD_KEY, nil)
    handle(cmd.op, cmd.arg)
  end
end)

-- noctalia msg plugin zmiguel/wg-split:service all <toggle|up|down|release|run|attach|refresh|status> [payload]
function onIpc(event, payload)
  if event == "status" then
    local text = if status.up then noctalia.tr("panel.state_up")
      elseif status.killswitch then noctalia.tr("panel.state_killswitch")
      else noctalia.tr("panel.state_down")
    noctalia.notify(noctalia.tr("title"), text)
    return
  end
  handle(event, payload)
end

function onConfigChanged()
  noctalia.setUpdateInterval(pollSeconds() * 1000)
  refresh()
end

function update()
  if not busy then
    refresh()
  end
end

noctalia.setUpdateInterval(pollSeconds() * 1000)
publish()
refresh()
