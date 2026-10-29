--!nonstrict
-- updates bar widget: package glyph with the number of pending updates. Left
-- click opens the panel, right click checks again.

local status = nil

local function hideWhenNone()
  return noctalia.getConfig("hide_when_none") == true
end

local function render()
  if status == nil then
    barWidget.setVisible(not hideWhenNone())
    barWidget.setGlyph("package")
    barWidget.setGlyphColor("on_surface_variant")
    barWidget.setText("")
    barWidget.setTooltip(noctalia.tr("tooltip.checking"))
    return
  end

  local repo, aur = #status.repo, #status.aur
  local total = repo + aur
  local failed = status.repo_error ~= "" or (status.aur_enabled and status.aur_error ~= "")

  barWidget.setVisible(total > 0 or failed or not hideWhenNone())
  barWidget.setText(total > 0 and tostring(total) or "")
  if failed and total == 0 then
    barWidget.setGlyph("package-off")
    barWidget.setGlyphColor("error")
  else
    barWidget.setGlyph("package")
    barWidget.setGlyphColor(total > 0 and "primary" or "on_surface_variant")
  end

  if status.checking and status.last_check == 0 then
    barWidget.setTooltip(noctalia.tr("tooltip.checking"))
    return
  end
  local rows = {
    { noctalia.tr("panel.repo"), status.repo_error ~= "" and noctalia.tr("tooltip.error") or tostring(repo) },
  }
  if status.aur_enabled then
    table.insert(rows, { noctalia.tr("panel.aur"), status.aur_error ~= "" and noctalia.tr("tooltip.error") or tostring(aur) })
  end
  barWidget.setTooltip(rows)
end

noctalia.state.watch("updates.status", function(value)
  status = type(value) == "table" and value or nil
  render()
end)

function onClick()
  noctalia.togglePanel("zmiguel/updates:panel")
end

function onRightClick()
  noctalia.state.set("updates.cmd", { op = "refresh", nonce = math.random() })
end

function onConfigChanged()
  render()
end

status = noctalia.state.get("updates.status")
render()
