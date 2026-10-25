--!nonstrict
-- spotify service: follows Spotify's MPRIS metadata with `playerctl --follow`,
-- polls the playback position while playing, caches album art, and publishes
-- everything as `spotify.track` for the bar widget and the panel.

local common = require("./lib/common.luau")

local SEP = "\t"
local FIELDS = {
  "{{status}}",
  "{{xesam:artist}}",
  "{{xesam:title}}",
  "{{xesam:album}}",
  "{{mpris:artUrl}}",
  "{{mpris:length}}",
  "{{mpris:trackid}}",
}
local ART_CACHE_LIMIT = 60

local track = { running = false, status = "Stopped", position = 0, length = 0 }
local polling = false

local function log(msg)
  noctalia.log(`spotify: {msg}`)
end

local function publish()
  noctalia.state.set(common.STATE_KEY, track)
end

-- ── album art ─────────────────────────────────────────────────────────────

local function artDir()
  local dir = noctalia.pluginDataDir()
  if dir == nil then
    return nil
  end
  dir ..= "/art"
  noctalia.mkdirAll(dir)
  return dir
end

local function pruneArt(dir, keep)
  local files = noctalia.listDir(dir)
  if type(files) ~= "table" or #files <= ART_CACHE_LIMIT then
    return
  end
  for _, name in ipairs(files) do
    local path = dir .. "/" .. name
    if path ~= keep then
      noctalia.removeFile(path)
    end
  end
end

local function resolveArt(url)
  track.artPath = nil
  if type(url) ~= "string" or url == "" then
    return
  end
  if url:sub(1, 7) == "file://" then
    track.artPath = noctalia.string.urlDecode(url:sub(8))
    return
  end
  if url:sub(1, 8) ~= "https://" then
    return
  end
  local dir = artDir()
  local id = url:match("([%w]+)$")
  if dir == nil or id == nil then
    return
  end
  local dest = `{dir}/{id}.jpg`
  if noctalia.fileExists(dest) then
    track.artPath = dest
    return
  end
  noctalia.download(url, dest, function(ok)
    if ok and track.artUrl == url then
      track.artPath = dest
      publish()
      pruneArt(dir, dest)
    elseif not ok then
      log("art download failed: " .. url)
    end
  end)
end

-- ── metadata stream ───────────────────────────────────────────────────────

local function trackUrl(trackId)
  local id = type(trackId) == "string" and trackId:match("track[:/](%w+)$")
  if id then
    return "https://open.spotify.com/track/" .. id
  end
  return nil
end

local function onLine(line)
  if line == nil or noctalia.string.trim(line) == "" then
    track = { running = false, status = "Stopped", position = 0, length = 0 }
    publish()
    return
  end
  local parts = string.split(line, SEP)
  local artUrl = parts[5] or ""
  local previousId = track.trackId
  local previousArt = track.artUrl

  track.running = true
  track.status = parts[1] or "Stopped"
  track.artist = parts[2] or ""
  track.title = parts[3] or ""
  track.album = parts[4] or ""
  track.length = (tonumber(parts[6]) or 0) / 1e6
  track.trackId = parts[7] or ""
  track.url = trackUrl(track.trackId)
  track.artUrl = artUrl
  if previousId ~= track.trackId then
    track.position = 0
  end
  if previousArt ~= artUrl then
    resolveArt(artUrl)
  end
  publish()
end

local function startStream()
  if not noctalia.commandExists("playerctl") then
    log("playerctl not found; install it to use this plugin")
    track.error = noctalia.tr("errors.no_playerctl")
    publish()
    return
  end
  local cmd = `playerctl -p {common.player()} --follow metadata --format '{table.concat(FIELDS, SEP)}'`
  if not noctalia.runStream(cmd, onLine) then
    log("failed to start: " .. cmd)
  end
end

-- ── position ──────────────────────────────────────────────────────────────

local function pollPosition()
  if polling or not track.running or track.status ~= "Playing" then
    return
  end
  polling = true
  noctalia.runAsync({ "playerctl", "-p", common.player(), "position" }, function(res)
    polling = false
    local position = tonumber(noctalia.string.trim(res.stdout or ""))
    if res.exitCode == 0 and position ~= nil and track.running then
      track.position = position
      publish()
    end
  end, 3000)
end

function update()
  pollPosition()
end

-- noctalia msg plugin zmiguel/spotify:service all <play-pause|next|previous|window|vpn>
function onIpc(event)
  if event == "play-pause" or event == "next" or event == "previous" then
    common.control(event)
  elseif event == "window" then
    common.toggleWindow()
  elseif event == "vpn" then
    common.launchThroughVpn()
  end
end

noctalia.setUpdateInterval(1000)
publish()
startStream()
