--!nonstrict
-- updates panel: totals, last check, an upgrade button, and the pending
-- packages from the repositories and the AUR. Read-only: every action goes to
-- the service through `updates.cmd`.

local status = noctalia.state.get("updates.status")
local isOpen = false

-- ── helpers ───────────────────────────────────────────────────────────────

local function send(op)
  noctalia.state.set("updates.cmd", { op = op, nonce = math.random() })
end

local function lastCheckText(ts)
  ts = tonumber(ts) or 0
  if ts <= 0 then
    return noctalia.tr("panel.never")
  end
  local ago = math.max(0, os.time() - ts)
  if ago < 60 then
    return noctalia.tr("panel.just_now")
  end
  if ago < 3600 then
    return noctalia.tr("panel.minutes_ago", { n = ago // 60 })
  end
  if ago < 86400 then
    return noctalia.tr("panel.hours_ago", { n = ago // 3600 })
  end
  return noctalia.tr("panel.days_ago", { n = ago // 86400 })
end

local function sectionTitle(text, count)
  return ui.row({ gap = 8, align = "center" }, {
    ui.label({ text = text, fontSize = 12, fontWeight = "bold", color = "on_surface_variant", flexGrow = 1 }),
    ui.label({ text = tostring(count), fontSize = 12, color = "on_surface_variant" }),
  })
end

local function hint(text, color)
  return ui.label({ text = text, fontSize = 12, color = color or "on_surface_variant", maxLines = 3 })
end

-- ── sections ──────────────────────────────────────────────────────────────

local function header()
  local checking = status ~= nil and status.checking == true
  return ui.row({ gap = 8, align = "center" }, {
    ui.glyph({ name = "package", size = 20, color = "primary" }),
    ui.label({ text = noctalia.tr("title"), fontSize = 16, fontWeight = "bold", flexGrow = 1 }),
    ui.button({ glyph = "refresh", variant = "ghost", enabled = not checking, tooltip = noctalia.tr("panel.refresh"), onClick = function()
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

local function summaryCard()
  local total = #status.repo + #status.aur
  local stateText = if status.checking then noctalia.tr("panel.checking")
    elseif total == 0 then noctalia.tr("panel.up_to_date")
    else noctalia.trp("notifications.available", total)

  return ui.column({ gap = 8, padding = 12, radius = 12, fill = "surface_variant/0.6" }, {
    ui.row({ gap = 10, align = "center" }, {
      ui.glyph({ name = total > 0 and "package" or "circle-check", size = 18, color = total > 0 and "primary" or "on_surface_variant" }),
      ui.label({ text = stateText, fontWeight = "bold", flexGrow = 1 }),
      ui.button({
        text = noctalia.tr("panel.upgrade"),
        glyph = "download",
        variant = "primary",
        controlSize = "sm",
        enabled = total > 0,
        onClick = function()
          send("upgrade")
          panel.close()
        end,
      }),
    }),
    ui.label({
      text = noctalia.tr("panel.last_check", { when = lastCheckText(status.last_check) }),
      fontSize = 12,
      color = "on_surface_variant",
    }),
  })
end

local function packageList(prefix, title, list, err)
  local rows = { sectionTitle(title, #list) }
  if err ~= "" then
    table.insert(rows, hint(err, "error"))
  elseif #list == 0 then
    table.insert(rows, hint(status.last_check > 0 and noctalia.tr("panel.none") or noctalia.tr("panel.checking")))
  end
  for _, pkg in ipairs(list) do
    table.insert(rows, ui.row({ key = `{prefix}-{pkg.name}`, gap = 8, align = "center" }, {
      ui.label({ text = pkg.name, fontSize = 13, flexGrow = 1, maxLines = 1 }),
      ui.label({ text = `{pkg.old} → {pkg.new}`, fontSize = 11, color = "on_surface_variant", maxLines = 1 }),
    }))
  end
  return ui.column({ gap = 6 }, rows)
end

-- ── render ────────────────────────────────────────────────────────────────

local function render()
  if not isOpen then
    return
  end
  local body
  if status == nil then
    body = { hint(noctalia.tr("panel.checking")) }
  else
    body = {
      summaryCard(),
      packageList("repo", noctalia.tr("panel.repo"), status.repo, status.repo_error),
    }
    if status.aur_enabled then
      table.insert(body, ui.separator({}))
      table.insert(body, packageList("aur", noctalia.tr("panel.aur"), status.aur, status.aur_error))
    end
  end
  panel.render(ui.column({ gap = 14, flexGrow = 1 }, {
    header(),
    ui.scroll({ gap = 14, flexGrow = 1 }, body),
  }))
end

noctalia.state.watch("updates.status", function(value)
  status = type(value) == "table" and value or nil
  render()
end)

function onOpen()
  isOpen = true
  status = noctalia.state.get("updates.status")
  render()
end

function onClose()
  isOpen = false
end
