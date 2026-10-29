--!nonstrict
-- updates service: the only entry that runs the package tools. Every
-- `interval_minutes` it runs `checkupdates` (repos) and `<aur_helper> -Qua`
-- (AUR) side by side, publishes both lists as `updates.status`, and handles the
-- `refresh` and `upgrade` commands the bar and panel send through `updates.cmd`.

local STATUS_KEY = "updates.status"
local CMD_KEY = "updates.cmd"

local status = {
  checking = false,
  last_check = 0,
  repo = {},
  aur = {},
  repo_error = "",
  aur_error = "",
  aur_enabled = true,
}
local pending = 0
local notifiedTotal = 0

-- ── helpers ───────────────────────────────────────────────────────────────

local function log(msg)
  noctalia.log(`updates: {msg}`)
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

local function cfgString(key, default)
  local v = noctalia.getConfig(key)
  if type(v) ~= "string" or trim(v) == "" then
    return default
  end
  return trim(v)
end

local function intervalMs()
  local v = tonumber(noctalia.getConfig("interval_minutes")) or 60
  return math.clamp(math.floor(v), 5, 1440) * 60 * 1000
end

-- "name old -> new", the format of both checkupdates and yay/paru -Qua. Colour
-- codes are stripped in case a tool ignores that stdout is not a terminal.
local function parse(output)
  local list = {}
  for line in (output or ""):gmatch("[^\n]+") do
    line = line:gsub("\27%[[%d;]*m", "")
    local name, old, new = line:match("^(%S+)%s+(%S+)%s+%->%s+(%S+)")
    if name ~= nil then
      table.insert(list, { name = name, old = old, new = new })
    end
  end
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  return list
end

local function publish()
  status.aur_enabled = cfgBool("check_aur", true)
  noctalia.state.set(STATUS_KEY, status)
end

local function maybeNotify()
  local total = #status.repo + #status.aur
  if total < notifiedTotal then
    notifiedTotal = total
  end
  if total == 0 or total == notifiedTotal or not cfgBool("notify", true) then
    return
  end
  notifiedTotal = total
  noctalia.notify(noctalia.tr("title"), noctalia.trp("notifications.available", total))
end

-- ── checking ──────────────────────────────────────────────────────────────

local function finishOne()
  pending -= 1
  if pending > 0 then
    publish()
    return
  end
  status.checking = false
  status.last_check = os.time()
  publish()
  maybeNotify()
end

-- checkupdates: 0 = updates listed, 2 = none, anything else = failure.
local function checkRepo()
  if not noctalia.commandExists("checkupdates") then
    status.repo = {}
    status.repo_error = noctalia.tr("errors.no_checkupdates")
    return false
  end
  local accepted = noctalia.runAsync({ "checkupdates" }, function(res)
    if res.timedOut then
      status.repo_error = noctalia.tr("errors.timeout")
    elseif res.exitCode == 0 or res.exitCode == 2 then
      status.repo = parse(res.stdout)
      status.repo_error = ""
    else
      local msg = firstLine(res.stderr ~= "" and res.stderr or res.stdout)
      status.repo_error = msg ~= "" and msg or noctalia.tr("errors.check_failed")
      log("checkupdates: " .. status.repo_error)
    end
    finishOne()
  end, 120000)
  if not accepted then
    status.repo_error = noctalia.tr("errors.check_failed")
  end
  return accepted
end

-- `-Qua` exits 1 with no output when nothing is outdated, so only stderr counts as a failure.
local function checkAur()
  if not cfgBool("check_aur", true) then
    status.aur = {}
    status.aur_error = ""
    return false
  end
  local helper = cfgString("aur_helper", "yay")
  if not noctalia.commandExists(helper) then
    status.aur = {}
    status.aur_error = noctalia.tr("errors.no_helper", { helper = helper })
    return false
  end
  local accepted = noctalia.runAsync({ helper, "-Qua", "--color", "never" }, function(res)
    local err = firstLine(res.stderr)
    if res.timedOut then
      status.aur_error = noctalia.tr("errors.timeout")
    elseif res.exitCode == 0 or (trim(res.stdout) == "" and err == "") then
      status.aur = parse(res.stdout)
      status.aur_error = ""
    else
      status.aur_error = err ~= "" and err or noctalia.tr("errors.check_failed")
      log(`{helper} -Qua: {status.aur_error}`)
    end
    finishOne()
  end, 120000)
  if not accepted then
    status.aur_error = noctalia.tr("errors.check_failed")
  end
  return accepted
end

local function refresh()
  if status.checking then
    return
  end
  status.checking = true
  pending = 2
  publish()
  if not checkRepo() then
    finishOne()
  end
  if not checkAur() then
    finishOne()
  end
end

-- ── upgrade ───────────────────────────────────────────────────────────────

-- Runs detached in a terminal; the script itself asks this service to re-check
-- once the upgrade ends, so the count is right as soon as the window closes.
local function upgrade()
  local terminal = cfgString("terminal", "kitty")
  if not noctalia.commandExists(terminal) then
    noctalia.notifyError(noctalia.tr("title"), noctalia.tr("errors.no_terminal", { terminal = terminal }))
    return
  end
  local command = cfgString("upgrade_command", "yay -Syu")
  local script = command
    .. '; noctalia msg plugin zmiguel/updates:service all refresh >/dev/null 2>&1'
    .. '; printf "\\n%s" "$1"; read -r _'
  if not noctalia.runAsync({ terminal, "-e", "sh", "-c", script, "sh", noctalia.tr("upgrade.close_prompt") }) then
    noctalia.notifyError(noctalia.tr("title"), noctalia.tr("errors.no_terminal", { terminal = terminal }))
  end
end

local function handle(op)
  if op == "refresh" then
    refresh()
  elseif op == "upgrade" then
    upgrade()
  else
    log("unknown command: " .. tostring(op))
  end
end

noctalia.state.watch(CMD_KEY, function(cmd)
  if type(cmd) == "table" then
    noctalia.state.set(CMD_KEY, nil)
    handle(cmd.op)
  end
end)

-- noctalia msg plugin zmiguel/updates:service all <refresh|upgrade>
function onIpc(event, _payload)
  handle(event)
end

function onConfigChanged()
  noctalia.setUpdateInterval(intervalMs())
  publish()
end

function update()
  refresh()
end

noctalia.setUpdateInterval(intervalMs())
publish()
refresh()
