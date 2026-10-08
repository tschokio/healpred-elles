-- DoHelper / Notes.lua
-- A tiny player-owned notepad with several named topics. Each topic keeps its
-- own text; the presentation (size, colour, position, collapsed state) is shared
-- and persists in SavedVariables. The optional floating window can be moved,
-- collapsed to a compact "Do ^" pill and restyled; the Notes tab mirrors every
-- editor. Editing is allowed out of combat and becomes read-only during combat
-- so the note never steals gameplay keys or fights the client. No idle timers:
-- the only OnUpdate is created by the client while the frame is dragged.
local _, ns = ...

local notes = {}
ns.notes = notes

local FONT = ns.ui.FONT
local TITLE_HEIGHT = 22
local SITE_ROW = 24
local COLLAPSED_WIDTH = 60
local COLLAPSED_HEIGHT = 22
local MAX_TEXT = 20000
local MAX_TITLE = 60
local MAX_SITES = 50
local LIMITS = {
	width = { 180, 900 },
	height = { 80, 800 },
	fontSize = { 8, 32 },
}

-- Exposed so the options UI and commands share the exact same bounds.
notes.MAX_TEXT = MAX_TEXT
notes.MAX_TITLE = MAX_TITLE
notes.MAX_SITES = MAX_SITES
notes.COLLAPSED_WIDTH = COLLAPSED_WIDTH
notes.COLLAPSED_HEIGHT = COLLAPSED_HEIGHT

local DEFAULT_TEXT_COLOR = { 0.90, 0.94, 0.98 }
local DEFAULT_TITLE_COLOR = { 0.32, 0.83, 0.73 }
local DEFAULT_BORDER_COLOR = { 0.20, 0.30, 0.34 }
local DEFAULT_BACKGROUND = { 0.05, 0.07, 0.10, 0.85 }
local DEFAULT_EDITOR_BG = { 0.00, 0.00, 0.00, 0.35 }

if ns.DEFAULTS and ns.DEFAULTS.notes then
	local d = ns.DEFAULTS.notes
	d.titleColor = d.titleColor or { DEFAULT_TITLE_COLOR[1], DEFAULT_TITLE_COLOR[2], DEFAULT_TITLE_COLOR[3] }
	d.borderColor = d.borderColor or { DEFAULT_BORDER_COLOR[1], DEFAULT_BORDER_COLOR[2], DEFAULT_BORDER_COLOR[3] }
	d.editorBackground = d.editorBackground or { DEFAULT_EDITOR_BG[1], DEFAULT_EDITOR_BG[2], DEFAULT_EDITOR_BG[3], DEFAULT_EDITOR_BG[4] }
	if d.outline == nil then d.outline = false end
end

-- Widgets (other than the editors) that must be enabled only out of combat:
-- the options tab and the floating window both add their topic controls here.
notes.lockables = {}

local function safe(obj, method, ...)
	if obj and type(obj[method]) == "function" then return obj[method](obj, ...) end
end

local function clamp(n, lo, hi)
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

local function component(t, index, fallback)
	if ns.isSecret(t) or type(t) ~= "table" then return fallback end
	local raw = t[index]
	if ns.isSecret(raw) then return fallback end
	if raw == nil then return fallback end
	if type(raw) ~= "number" and type(raw) ~= "string" then return fallback end
	local v = tonumber(raw)
	if v == nil or v < 0 or v > 1 or v ~= v or v == math.huge or v == -math.huge then return fallback end
	return v
end

local function validRGB(t, name)
	local err = (name or "Text") .. " RGB must be 0-1 each."
	if ns.isSecret(t) or type(t) ~= "table" then return nil, err end
	local out = {}
	for i = 1, 3 do
		local raw = t[i]
		if ns.isSecret(raw) then return nil, err end
		if raw == nil then return nil, err end
		if type(raw) ~= "number" and type(raw) ~= "string" then return nil, err end
		local v = tonumber(raw)
		if v == nil or v ~= v or v == math.huge or v == -math.huge or v < 0 or v > 1 then
			return nil, err
		end
		out[i] = v
	end
	return out
end

local function validRGBA(t, name)
	local err = (name or "Background") .. " RGBA must be 0-1 each."
	if ns.isSecret(t) or type(t) ~= "table" then return nil, err end
	local out = {}
	for i = 1, 4 do
		local raw = t[i]
		if ns.isSecret(raw) then return nil, err end
		if raw == nil then return nil, err end
		if type(raw) ~= "number" and type(raw) ~= "string" then return nil, err end
		local v = tonumber(raw)
		if v == nil or v ~= v or v == math.huge or v == -math.huge or v < 0 or v > 1 then
			return nil, err
		end
		out[i] = v
	end
	return out
end


local function data()
	if not ns.db then return nil end
	if type(ns.db.notes) ~= "table" then ns.db.notes = {} end
	return ns.db.notes
end

-- A plain string or nil. A secret or non-string value is refused rather than
-- coerced, consistent with the rest of the addon.
local function cleanText(v)
	if ns.isSecret(v) or type(v) ~= "string" then return nil end
	if #v > MAX_TEXT then return v:sub(1, MAX_TEXT) end
	return v
end

local function cleanTitle(v, fallback)
	if ns.isSecret(v) or type(v) ~= "string" then return fallback end
	v = v:gsub("[\r\n]", " "):gsub("^%s+", ""):gsub("%s+$", "")
	if v == "" then return fallback end
	if #v > MAX_TITLE then v = v:sub(1, MAX_TITLE) end
	return v
end

local function findSite(d, id)
	if not d or type(d.sites) ~= "table" or type(id) ~= "string" then return nil end
	for index, site in ipairs(d.sites) do
		if type(site) == "table" and site.id == id then return site, index end
	end
	return nil
end

local function hasSite(d, id)
	return findSite(d, id) ~= nil
end

-- Ensure a valid, non-empty topic list and a valid active id. A legacy single
-- `text` string (the pre-topics schema) is migrated into the first topic; it is
-- never discarded, and valid topics in a partially corrupt list are salvaged.
-- Safe to call repeatedly: it repairs only what is invalid.
function notes.EnsureSites()
	local d = data()
	if not d then return nil end
	local raw = d.sites
	if type(raw) ~= "table" or #raw == 0 then
		local legacy = cleanText(d.text) or ""
		d.sites = { { id = "site-1", title = "General", text = legacy } }
		d.activeId = "site-1"
		d.nextSiteId = 2
		d.text = nil
	else
		local clean, seen, repaired = {}, {}, false
		for _, site in ipairs(raw) do
			if type(site) == "table" and not ns.isSecret(site.id)
				and type(site.id) == "string" and site.id ~= "" and not seen[site.id] then
				seen[site.id] = true
				local title = cleanTitle(site.title, "Note " .. tostring(#clean + 1))
				local text = cleanText(site.text) or ""
				if site.title ~= title or site.text ~= text then repaired = true end
				clean[#clean + 1] = { id = site.id, title = title, text = text }
			else
				repaired = true
			end
		end
		if #clean == 0 then
			clean = { { id = "site-1", title = "General", text = cleanText(d.text) or "" } }
			d.text = nil
			repaired = true
		end
		if repaired then d.sites = clean end
	end
	while #d.sites > MAX_SITES do table.remove(d.sites) end
	local maxN = 0
	for _, site in ipairs(d.sites) do
		local n = tonumber((tostring(site.id)):match("^site%-(%d+)$") or "")
		if n and n > maxN then maxN = n end
	end
	local nextId = ns.toNumber(d.nextSiteId)
	if not nextId or nextId < 1 or nextId ~= math.floor(nextId) or nextId <= maxN then
		nextId = maxN + 1
	end
	d.nextSiteId = nextId
	if not hasSite(d, d.activeId) then d.activeId = d.sites[1].id end
	return d
end

-- Sanitized view of the topic list (the stored tables themselves).
function notes.Sites()
	local d = notes.EnsureSites()
	return d and d.sites or {}
end

function notes.ActiveId()
	local d = notes.EnsureSites()
	return d and d.activeId or nil
end

function notes.ActiveSite()
	local d = notes.EnsureSites()
	if not d then return nil end
	return (findSite(d, d.activeId))
end

function notes.SiteTitle(id)
	local d = notes.EnsureSites()
	if not d then return "" end
	local site = findSite(d, id or d.activeId)
	return site and site.title or ""
end

-- Persisted topic text. Sanitizes on read so a corrupt saved value can never
-- reach an editor as a non-string.
function notes.SiteText(id)
	local d = notes.EnsureSites()
	if not d then return "" end
	local site = findSite(d, id or d.activeId)
	if not site then return "" end
	local value = cleanText(site.text)
	if value == nil then site.text = ""; return "" end
	site.text = value
	return value
end

function notes.SetSiteText(id, value)
	if ns.isSecret(value) or type(value) ~= "string" then return false end
	if #value > MAX_TEXT then value = value:sub(1, MAX_TEXT) end
	local d = notes.EnsureSites()
	if not d then return false end
	local site = findSite(d, id or d.activeId)
	if not site then return false end
	site.text = value
	if site.id == d.activeId then notes.Mirror(value) end
	return true
end

-- Backwards-compatible single-topic accessors: they act on the active topic.
function notes.Text()
	return notes.SiteText(notes.ActiveId())
end

function notes.SetText(value)
	return notes.SetSiteText(notes.ActiveId(), value)
end

-- Every live editor, so a change in one mirrors to the other(s).
function notes.Editors()
	local list = {}
	if notes.tabEditor then list[#list + 1] = notes.tabEditor end
	if notes.window and notes.window.edit then list[#list + 1] = notes.window.edit end
	return list
end

function notes.Mirror(value)
	notes.updating = true
	for _, e in ipairs(notes.Editors()) do
		if type(e.GetText) == "function" and type(e.SetText) == "function" and e:GetText() ~= value then
			e:SetText(value)
		end
	end
	notes.updating = false
end

-- Called from each editor's OnTextChanged. Programmatic mirroring sets the
-- guard flag first, so it never recurses.
function notes.OnEditorChanged(editor)
	if notes.updating then return end
	local value = (editor and editor.GetText) and editor:GetText() or ""
	notes.SetSiteText(notes.ActiveId(), value)
end

function notes.RefreshText()
	notes.Mirror(notes.Text())
end

-- Push the active topic's title into the floating window and mirror its text.
function notes.RefreshSites()
	local f = notes.window
	local d = notes.EnsureSites()
	if not d then return end
	if f and f.siteTitle and type(f.siteTitle.SetText) == "function" then
		local site = findSite(d, d.activeId)
		notes.updating = true
		f.siteTitle:SetText(site and site.title or "")
		notes.updating = false
	end
	notes.RefreshText()
end

-- One hook for the options tab: it refreshes its own topic controls whenever the
-- active topic, list or titles change from anywhere (window, slash, tab).
function notes.NotifyChanged()
	notes.RefreshSites()
	if type(notes.onChanged) == "function" then pcall(notes.onChanged) end
end

function notes.SetActive(id)
	local d = notes.EnsureSites()
	if not d then return false end
	if not hasSite(d, id) then return false end
	if d.activeId ~= id then d.activeId = id end
	notes.NotifyChanged()
	return true
end

function notes.CycleSite(delta)
	local d = notes.EnsureSites()
	if not d or #d.sites < 1 then return false end
	local index = 1
	for i, site in ipairs(d.sites) do
		if site.id == d.activeId then index = i; break end
	end
	index = index + (ns.toNumber(delta) or 0)
	if index < 1 then index = #d.sites elseif index > #d.sites then index = 1 end
	d.activeId = d.sites[index].id
	notes.NotifyChanged()
	return true
end

function notes.AddSite(title)
	local d = notes.EnsureSites()
	if not d then return nil, "Settings unavailable." end
	if #d.sites >= MAX_SITES then return nil, "Topic limit reached (" .. MAX_SITES .. ")." end
	local id = "site-" .. tostring(math.floor(d.nextSiteId or 1))
	d.nextSiteId = math.floor(d.nextSiteId or 1) + 1
	local site = { id = id, title = cleanTitle(title, "Note " .. tostring(#d.sites + 1)), text = "" }
	d.sites[#d.sites + 1] = site
	d.activeId = id
	notes.NotifyChanged()
	return site
end

function notes.RenameSite(id, title)
	if ns.isSecret(title) or type(title) ~= "string" then return false end
	local d = notes.EnsureSites()
	if not d then return false end
	local site = findSite(d, id or d.activeId)
	if not site then return false end
	site.title = cleanTitle(title, site.title or "Note")
	notes.NotifyChanged()
	return true
end

function notes.RemoveSite(id)
	local d = notes.EnsureSites()
	if not d then return false, "Settings unavailable." end
	if #d.sites <= 1 then return false, "At least one topic must remain." end
	local site, index = findSite(d, id or d.activeId)
	if not site then return false, "Topic not found." end
	table.remove(d.sites, index)
	if d.activeId == site.id then
		local nextSite = d.sites[math.min(index, #d.sites)]
		d.activeId = nextSite.id
	end
	notes.NotifyChanged()
	return true, "Topic deleted."
end

function notes.IsEditable()
	if ns.api and ns.api.InCombat then return not ns.api.InCombat() end
	return not (ns.inCombat == true)
end

-- Combat lock: out of combat the note is editable; during combat it is read-only
-- and loses focus so the player's keys are not swallowed.
function notes.RefreshEditable()
	local editable = notes.IsEditable()
	local s = notes.Style()
	for _, e in ipairs(notes.Editors()) do
		if not editable then safe(e, "ClearFocus") end
		safe(e, "SetEnabled", editable)
		if e.uiInput then
			ns.ui.InputState(e)
			local focused = e.HasFocus and e:HasFocus()
			if not focused then
				local colors = notes.EffectiveColors(s)
				safe(e, "SetBackdropBorderColor", colors.borderColor[1], colors.borderColor[2], colors.borderColor[3], 1)
			end
		end
	end
	for _, w in ipairs(notes.lockables) do
		if not editable then safe(w, "ClearFocus") end
		safe(w, "SetEnabled", editable)
		if w.uiFill then ns.ui.PaintButton(w) end
		if w.uiInput then ns.ui.InputState(w) end
	end
	-- The floating hint stays short so it cannot grow into the editor; the tab
	-- has room for the longer explanation.
	if notes.window and notes.window.hint then notes.window.hint:SetText(editable and "" or "Combat: read-only") end
	if notes.tabHint then
		notes.tabHint:SetText(editable and "Edits save as you type. Choose a topic; notes are read-only during combat."
			or "Combat: notes are read-only. Editing unlocks when combat ends.")
	end
end

-- Validated, clamped presentation. Style() is forgiving (used for live apply);
-- SetStyle() rejects out-of-range input atomically so no partial edit lands.
function notes.Style()
	local d = data() or {}
	local width = ns.isFinite(d.width) and d.width or 320
	local height = ns.isFinite(d.height) and d.height or 240
	local fontSize = ns.isFinite(d.fontSize) and d.fontSize or 14
	local tc = d.textColor
	local titc = d.titleColor
	local bc = d.borderColor
	local bg = d.background
	local ebg = d.editorBackground
	return {
		width = clamp(width, LIMITS.width[1], LIMITS.width[2]),
		height = clamp(height, LIMITS.height[1], LIMITS.height[2]),
		fontSize = clamp(fontSize, LIMITS.fontSize[1], LIMITS.fontSize[2]),
		outline = d.outline and true or false,
		textColor = {
			component(tc, 1, DEFAULT_TEXT_COLOR[1]),
			component(tc, 2, DEFAULT_TEXT_COLOR[2]),
			component(tc, 3, DEFAULT_TEXT_COLOR[3]),
		},
		titleColor = {
			component(titc, 1, DEFAULT_TITLE_COLOR[1]),
			component(titc, 2, DEFAULT_TITLE_COLOR[2]),
			component(titc, 3, DEFAULT_TITLE_COLOR[3]),
		},
		borderColor = {
			component(bc, 1, DEFAULT_BORDER_COLOR[1]),
			component(bc, 2, DEFAULT_BORDER_COLOR[2]),
			component(bc, 3, DEFAULT_BORDER_COLOR[3]),
		},
		background = {
			component(bg, 1, DEFAULT_BACKGROUND[1]),
			component(bg, 2, DEFAULT_BACKGROUND[2]),
			component(bg, 3, DEFAULT_BACKGROUND[3]),
			component(bg, 4, DEFAULT_BACKGROUND[4]),
		},
		editorBackground = {
			component(ebg, 1, DEFAULT_EDITOR_BG[1]),
			component(ebg, 2, DEFAULT_EDITOR_BG[2]),
			component(ebg, 3, DEFAULT_EDITOR_BG[3]),
			component(ebg, 4, DEFAULT_EDITOR_BG[4]),
		},
	}
end

function notes.UsesSkinColors()
	return not (ns.db and ns.db.notes and ns.db.notes.useSkinColors == false)
end

function notes.EffectiveColors(style)
	style = style or notes.Style()
	if not notes.UsesSkinColors() or not ns.ui then
		return {
			textColor = style.textColor, titleColor = style.titleColor, borderColor = style.borderColor,
			background = style.background, editorBackground = style.editorBackground,
		}
	end
	local c = ns.ui.colors
	return {
		textColor = c.noteText, titleColor = c.noteTitle, borderColor = c.noteBorder,
		background = c.noteWindow, editorBackground = c.noteEditor,
	}
end

function notes.SetUseSkinColors(value)
	local d = data()
	if not d then return false end
	d.useSkinColors = value and true or false
	notes.ApplyStyle()
	return true
end

function notes.SetStyle(style)
	if ns.isSecret(style) or type(style) ~= "table" then return false, "No style values supplied." end
	local width, height, fontSize = ns.toNumber(style.width), ns.toNumber(style.height), ns.toNumber(style.fontSize)
	if not (ns.isFinite(width) and width >= LIMITS.width[1] and width <= LIMITS.width[2]) then
		return false, "Width must be 180-900."
	end
	if not (ns.isFinite(height) and height >= LIMITS.height[1] and height <= LIMITS.height[2]) then
		return false, "Height must be 80-800."
	end
	if not (ns.isFinite(fontSize) and fontSize >= LIMITS.fontSize[1] and fontSize <= LIMITS.fontSize[2]) then
		return false, "Font size must be 8-32."
	end

	local tc, tcErr = validRGB(style.textColor, "Text")
	if not tc then return false, tcErr or "Text RGB must be 0-1 each." end

	local bg, bgErr = validRGBA(style.background, "Background")
	if not bg then return false, bgErr or "Background RGBA must be 0-1 each." end

	local titc, bc, ebg = nil, nil, nil
	if style.titleColor ~= nil then
		local err
		titc, err = validRGB(style.titleColor, "Title")
		if not titc then return false, err or "Title RGB must be 0-1 each." end
	end
	if style.borderColor ~= nil then
		local err
		bc, err = validRGB(style.borderColor, "Border")
		if not bc then return false, err or "Border RGB must be 0-1 each." end
	end
	if style.editorBackground ~= nil then
		local err
		ebg, err = validRGBA(style.editorBackground, "Editor background")
		if not ebg then return false, err or "Editor background RGBA must be 0-1 each." end
	end

	local outline = nil
	if style.outline ~= nil then
		outline = style.outline and true or false
	end

	local d = data()
	if not d then return false, "Settings unavailable." end

	d.width, d.height, d.fontSize = width, height, fontSize
	d.textColor = tc
	d.background = bg
	if titc then d.titleColor = titc end
	if bc then d.borderColor = bc end
	if ebg then d.editorBackground = ebg end
	if outline ~= nil then d.outline = outline end
	d.useSkinColors = false

	notes.ApplyStyle()
	return true
end

function notes.EditorHeight(style)
	return math.max(16, style.height - TITLE_HEIGHT - SITE_ROW - 2 - 18)
end

function notes.ApplyStyle()
	local s = notes.Style()
	local colors = notes.EffectiveColors(s)
	local fontFlags = s.outline and "OUTLINE" or ""
	local f = notes.window
	if f then
		safe(f, "SetBackdropColor", colors.background[1], colors.background[2], colors.background[3], colors.background[4])
		safe(f, "SetBackdropBorderColor", colors.borderColor[1], colors.borderColor[2], colors.borderColor[3], 1)
		local collapsed = notes.IsCollapsed()
		f:SetSize(collapsed and COLLAPSED_WIDTH or s.width, collapsed and COLLAPSED_HEIGHT or s.height)
		if f.edit then
			f.edit:SetSize(s.width - 16, notes.EditorHeight(s))
			safe(f.edit, "SetBackdropColor", colors.editorBackground[1], colors.editorBackground[2], colors.editorBackground[3], colors.editorBackground[4])
			safe(f.edit, "SetBackdropBorderColor", colors.borderColor[1], colors.borderColor[2], colors.borderColor[3], 1)
		end
		if f.siteTitle then
			f.siteTitle:SetSize(math.max(60, s.width - 112), 20)
			safe(f.siteTitle, "SetFont", FONT, 12, "")
			safe(f.siteTitle, "SetTextColor", colors.titleColor[1], colors.titleColor[2], colors.titleColor[3], 1)
			safe(f.siteTitle, "SetBackdropBorderColor", colors.borderColor[1], colors.borderColor[2], colors.borderColor[3], 1)
		end
		if f.title then
			safe(f.title, "SetFont", FONT, 12, "")
			safe(f.title, "SetTextColor", colors.titleColor[1], colors.titleColor[2], colors.titleColor[3], 1)
		end
	end
	if notes.tabEditor then
		safe(notes.tabEditor, "SetFont", FONT, s.fontSize, fontFlags)
		safe(notes.tabEditor, "SetBackdropColor", colors.editorBackground[1], colors.editorBackground[2], colors.editorBackground[3], colors.editorBackground[4])
		safe(notes.tabEditor, "SetBackdropBorderColor", colors.borderColor[1], colors.borderColor[2], colors.borderColor[3], 1)
	end
	if notes.tabTitle then
		safe(notes.tabTitle, "SetTextColor", colors.titleColor[1], colors.titleColor[2], colors.titleColor[3], 1)
		safe(notes.tabTitle, "SetBackdropBorderColor", colors.borderColor[1], colors.borderColor[2], colors.borderColor[3], 1)
	end
	for _, e in ipairs(notes.Editors()) do
		safe(e, "SetFont", FONT, s.fontSize, fontFlags)
		safe(e, "SetTextColor", colors.textColor[1], colors.textColor[2], colors.textColor[3], 1)
	end
	if f and f.hint then
		safe(f.hint, "SetTextColor", math.min(1, colors.textColor[1] + 0.08), math.min(1, colors.textColor[2] + 0.08), math.min(1, colors.textColor[3] + 0.08), 1)
	end
end

function notes.IsCollapsed()
	return (ns.db and ns.db.notes and ns.db.notes.collapsed) and true or false
end

function notes.SetCollapsed(value)
	local d = data()
	if not d then return end
	d.collapsed = value and true or false
	notes.ApplyCollapsed()
end

function notes.SetOutline(value)
	local d = data()
	if not d then return end
	d.outline = value and true or false
	notes.ApplyStyle()
end


function notes.ApplyCollapsed()
	local f = notes.window
	if not f then return end
	local collapsed = notes.IsCollapsed()
	local s = notes.Style()
	local function show(widget, shown) safe(widget, "SetShown", shown) end
	show(f.edit, not collapsed)
	show(f.hint, not collapsed)
	show(f.close, not collapsed)
	show(f.siteTitle, not collapsed)
	show(f.sitePrev, not collapsed)
	show(f.siteNext, not collapsed)
	show(f.siteAdd, not collapsed)
	show(f.siteDel, not collapsed)
	if f.collapse then f.collapse:SetText(collapsed and "^" or "v") end
	f:SetSize(collapsed and COLLAPSED_WIDTH or s.width, collapsed and COLLAPSED_HEIGHT or s.height)
	if f.edit then f.edit:SetSize(s.width - 16, notes.EditorHeight(s)) end
end

function notes.RestorePosition()
	local f = notes.window
	if not f or not UIParent or type(f.SetPoint) ~= "function" then return end
	local d = data() or {}
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", ns.toNumber(d.x) or 0, ns.toNumber(d.y) or 0)
end

function notes.SavePosition()
	local f = notes.window
	if not f or not UIParent or type(f.GetCenter) ~= "function" then return end
	local cx, cy = f:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if type(cx) ~= "number" or type(cy) ~= "number" or type(ux) ~= "number" or type(uy) ~= "number" then return end
	local d = data()
	if not d then return end
	d.x, d.y = cx - ux, cy - uy
end

function notes.EnsureWindow()
	if notes.window then return notes.window end
	if type(CreateFrame) ~= "function" then return nil end
	local s = notes.Style()
	notes.EnsureSites()
	local f = CreateFrame("Frame", "EllesmereUI_HoTPredictionNotes", UIParent, "BackdropTemplate")
	notes.window = f
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) safe(self, "StartMoving") end)
	f:SetScript("OnDragStop", function(self)
		safe(self, "StopMovingOrSizing")
		notes.SavePosition()
	end)
	f:SetScript("OnShow", function()
		local d = data()
		if d then d.shown = true end
	end)
	-- Hiding a focused editor must release focus so it cannot swallow keys while
	-- the window is closed (Close, Escape or a reload). Also synchronize shown
	-- state so direct frame Hide or any UI close accurately updates SavedVariables.
	f:SetScript("OnHide", function()
		local d = data()
		if d then d.shown = false end
		if f.edit then safe(f.edit, "ClearFocus") end
		if f.siteTitle then safe(f.siteTitle, "ClearFocus") end
	end)
	f:SetSize(s.width, s.height)
	ns.ui.Surface(f)

	-- Header: the compact "Do" label with its collapse arrow right next to it.
	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 9, -5)
	title:SetWidth(40)
	title:SetJustifyH("LEFT")
	title:SetText("Do")
	ns.ui.Text(title, "section")
	f.title = title

	local collapse = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	collapse:SetSize(22, 18)
	collapse:SetPoint("TOPLEFT", f, "TOPLEFT", 34, -3)
	collapse:SetText(notes.IsCollapsed() and "^" or "v")
	collapse:SetScript("OnClick", function() notes.SetCollapsed(not notes.IsCollapsed()) end)
	f.collapse = collapse
	ns.ui.Button(collapse)

	local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
	close:SetSize(18, 18)
	close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -3)
	close:SetText("X")
	close:SetScript("OnClick", function() notes.Close() end)
	f.close = close
	ns.ui.Button(close)

	-- Topic row: previous / next cycle topics, an editable title and add/delete.
	local siteY = -TITLE_HEIGHT - 2
	local function siteButton(text, x, width, anchorRight, action)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(width, 20)
		if anchorRight then b:SetPoint("TOPRIGHT", f, "TOPRIGHT", x, siteY)
		else b:SetPoint("TOPLEFT", f, "TOPLEFT", x, siteY) end
		b:SetText(text)
		b:SetScript("OnClick", action)
		ns.ui.Button(b)
		return b
	end
	f.sitePrev = siteButton("<", 8, 20, false, function() notes.CycleSite(-1) end)
	f.siteNext = siteButton(">", -52, 20, true, function() notes.CycleSite(1) end)
	f.siteAdd = siteButton("+", -30, 20, true, function() notes.AddSite() end)
	f.siteDel = siteButton("-", -8, 20, true, function() notes.RemoveSite(notes.ActiveId()) end)
	ns.ui.Button(f.siteDel, "danger")

	local titleBox = CreateFrame("EditBox", nil, f, "BackdropTemplate")
	titleBox:SetAutoFocus(false)
	titleBox:SetMaxLetters(MAX_TITLE)
	titleBox:SetPoint("TOPLEFT", f, "TOPLEFT", 32, siteY)
	titleBox:SetSize(math.max(60, s.width - 112), 20)
	titleBox:SetScript("OnEnterPressed", function(self)
		notes.RenameSite(notes.ActiveId(), self:GetText())
		self:ClearFocus()
	end)
	titleBox:SetScript("OnEditFocusLost", function(self) notes.RenameSite(notes.ActiveId(), self:GetText()) end)
	titleBox:SetScript("OnEscapePressed", function(self) notes.RefreshSites(); self:ClearFocus() end)
	ns.ui.Input(titleBox)
	f.siteTitle = titleBox

	local edit = CreateFrame("EditBox", nil, f, "BackdropTemplate")
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -(TITLE_HEIGHT + SITE_ROW + 2))
	edit:SetTextInsets(6, 6, 6, 6)
	edit:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	edit:SetBackdropColor(0, 0, 0, 0.35)
	edit:SetBackdropBorderColor(0.2, 0.3, 0.34, 0.8)
	edit:SetScript("OnTextChanged", function(self) notes.OnEditorChanged(self) end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	ns.ui.Input(edit, true)
	if edit.HookScript then
		edit:HookScript("OnEditFocusLost", function(self)
			local s = notes.EffectiveColors(notes.Style())
			safe(self, "SetBackdropBorderColor", s.borderColor[1], s.borderColor[2], s.borderColor[3], 1)
		end)
	end
	f.edit = edit

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 5)
	hint:SetWidth(s.width - 20)
	hint:SetJustifyH("LEFT")
	hint:SetText("")
	ns.ui.Text(hint, "muted")
	f.hint = hint

	-- Topic management mutates saved notes, so it locks with the editors.
	notes.lockables[#notes.lockables + 1] = titleBox
	notes.lockables[#notes.lockables + 1] = f.siteAdd
	notes.lockables[#notes.lockables + 1] = f.siteDel

	notes.RestorePosition()
	notes.ApplyStyle()
	notes.ApplyCollapsed()
	notes.RefreshSites()
	notes.RefreshEditable()
	return f
end

function notes.Open()
	local f = notes.EnsureWindow()
	if not f then return nil end
	local d = data()
	if d then d.shown = true end
	notes.RefreshSites()
	notes.RefreshEditable()
	notes.ApplyStyle()
	notes.ApplyCollapsed()
	f:Show()
	return f
end

function notes.Close()
	if notes.window then notes.window:Hide() end
	local d = data()
	if d then d.shown = false end
end

function notes.Toggle()
	if notes.window and notes.window:IsShown() then notes.Close() else notes.Open() end
end

-- Combat/login events use this module's own frame, so the notes still lock and
-- restore even when the healing helper itself is disabled.
function notes.HandleEvent(event)
	if event == "PLAYER_LOGIN" then
		local d = ns.db and ns.db.notes
		if d and d.shown then notes.Open() end
	end
	if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD"
		or event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
		notes.RefreshEditable()
	end
end

function notes.Setup()
	if notes.eventFrame then return end
	if type(CreateFrame) ~= "function" then return end
	local f = CreateFrame("Frame")
	notes.eventFrame = f
	for _, event in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		pcall(f.RegisterEvent, f, event)
	end
	f:SetScript("OnEvent", function(_, event) notes.HandleEvent(event) end)
end

-- Key-bindable entry point (Bindings.xml). Toggles the floating notes window.
function EllesmereUI_HoTPrediction_ToggleNotes()
	if ns.notes and ns.notes.Toggle then ns.notes.Toggle() end
end

-- Friendly names in the Blizzard Key Bindings UI (Bindings.xml declares the keys).
BINDING_HEADER_ELLESMEREUI_HOTPRED = "DoHelper"
BINDING_NAME_ELLESMEREUI_HOTPRED_TOGGLE_NOTES = "Toggle notes window"
