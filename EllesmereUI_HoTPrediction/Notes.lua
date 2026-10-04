-- EllesmereUI_HoTPrediction / Notes.lua
-- A tiny player-owned notepad. The text and its presentation persist in
-- SavedVariables; the optional floating window can be moved, collapsed, closed
-- and restyled. Editing is allowed out of combat and becomes read-only during
-- combat so the note never steals gameplay keys or fights the client. No idle
-- timers: the only OnUpdate is created by the client while the frame is dragged.
local _, ns = ...

local notes = {}
ns.notes = notes

local FONT = "Fonts\\FRIZQT__.TTF"
local TITLE_HEIGHT = 30
local MAX_TEXT = 20000
local LIMITS = {
	width = { 180, 900 },
	height = { 80, 800 },
	fontSize = { 8, 32 },
}

local function safe(obj, method, ...)
	if obj and type(obj[method]) == "function" then return obj[method](obj, ...) end
end

local function clamp(n, lo, hi)
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

local function data()
	if not ns.db then return nil end
	if type(ns.db.notes) ~= "table" then ns.db.notes = {} end
	return ns.db.notes
end

-- Persisted text, always a plain string. A secret or non-string value is refused
-- rather than coerced, consistent with the rest of the addon.
function notes.Text()
	local d = ns.db and ns.db.notes
	local t = d and d.text
	if ns.isSecret(t) or type(t) ~= "string" then return "" end
	return t
end

-- Every live editor, so a change in one mirrors to the other(s).
function notes.Editors()
	local list = {}
	if notes.tabEditor then list[#list + 1] = notes.tabEditor end
	if notes.window and notes.window.edit then list[#list + 1] = notes.window.edit end
	return list
end

function notes.SetText(value)
	if ns.isSecret(value) or type(value) ~= "string" then return false end
	if #value > MAX_TEXT then value = value:sub(1, MAX_TEXT) end
	local d = data()
	if not d then return false end
	d.text = value
	notes.Mirror(value)
	return true
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
	notes.SetText((editor and editor.GetText) and editor:GetText() or "")
end

function notes.RefreshText()
	notes.Mirror(notes.Text())
end

function notes.IsEditable()
	if ns.api and ns.api.InCombat then return not ns.api.InCombat() end
	return not (ns.inCombat == true)
end

-- Combat lock: out of combat the note is editable; during combat it is read-only
-- and loses focus so the player's keys are not swallowed.
function notes.RefreshEditable()
	local editable = notes.IsEditable()
	for _, e in ipairs(notes.Editors()) do
		if not editable then safe(e, "ClearFocus") end
		safe(e, "SetEnabled", editable)
	end
	-- The floating hint stays short so it cannot grow into the editor; the tab
	-- has room for the longer explanation.
	if notes.window and notes.window.hint then notes.window.hint:SetText(editable and "" or "Combat: read-only") end
	if notes.tabHint then
		notes.tabHint:SetText(editable and "Edits save as you type. Notes are read-only during combat."
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
	local tc = type(d.textColor) == "table" and d.textColor or { 0.90, 0.94, 0.98 }
	local bg = type(d.background) == "table" and d.background or { 0.05, 0.07, 0.10, 0.85 }
	return {
		width = clamp(width, LIMITS.width[1], LIMITS.width[2]),
		height = clamp(height, LIMITS.height[1], LIMITS.height[2]),
		fontSize = clamp(fontSize, LIMITS.fontSize[1], LIMITS.fontSize[2]),
		textColor = { tc[1] or 0.90, tc[2] or 0.94, tc[3] or 0.98 },
		background = { bg[1] or 0.05, bg[2] or 0.07, bg[3] or 0.10, bg[4] or 0.85 },
	}
end

function notes.SetStyle(style)
	if type(style) ~= "table" then return false, "No style values supplied." end
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
	local tc, bg = style.textColor, style.background
	if type(tc) ~= "table" or type(bg) ~= "table" then return false, "Missing color values." end
	for i = 1, 3 do
		local v = ns.toNumber(tc[i])
		if not (ns.isFinite(v) and v <= 1) then return false, "Text RGB must be 0-1 each." end
	end
	for i = 1, 4 do
		local v = ns.toNumber(bg[i])
		if not (ns.isFinite(v) and v <= 1) then return false, "Background RGBA must be 0-1 each." end
	end
	local d = data()
	if not d then return false, "Settings unavailable." end
	d.width, d.height, d.fontSize = width, height, fontSize
	d.textColor = { ns.toNumber(tc[1]), ns.toNumber(tc[2]), ns.toNumber(tc[3]) }
	d.background = { ns.toNumber(bg[1]), ns.toNumber(bg[2]), ns.toNumber(bg[3]), ns.toNumber(bg[4]) }
	notes.ApplyStyle()
	return true
end

function notes.ApplyStyle()
	local s = notes.Style()
	local f = notes.window
	if f then
		safe(f, "SetBackdropColor", s.background[1], s.background[2], s.background[3], s.background[4])
		f:SetSize(s.width, notes.IsCollapsed() and TITLE_HEIGHT or s.height)
		if f.edit then f.edit:SetSize(s.width - 16, math.max(16, s.height - TITLE_HEIGHT - 32)) end
		if f.title then safe(f.title, "SetFont", FONT, s.fontSize + 2, "") end
	end
	if notes.tabEditor then safe(notes.tabEditor, "SetFont", FONT, s.fontSize, "") end
	for _, e in ipairs(notes.Editors()) do
		safe(e, "SetFont", FONT, s.fontSize, "")
		safe(e, "SetTextColor", s.textColor[1], s.textColor[2], s.textColor[3], 1)
	end
	if f and f.hint then
		safe(f.hint, "SetTextColor", math.min(1, s.textColor[1] + 0.08), math.min(1, s.textColor[2] + 0.08), math.min(1, s.textColor[3] + 0.08), 1)
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

function notes.ApplyCollapsed()
	local f = notes.window
	if not f then return end
	local collapsed = notes.IsCollapsed()
	local s = notes.Style()
	if f.edit then if collapsed then f.edit:Hide() else f.edit:Show() end end
	if f.hint then if collapsed then f.hint:Hide() else f.hint:Show() end end
	f:SetHeight(collapsed and TITLE_HEIGHT or s.height)
	if f.collapse then f.collapse:SetText(collapsed and "Expand" or "Collapse") end
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

local function button(parent, title, width, point, x, action)
	local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
	b:SetSize(width, 20)
	b:SetPoint(point, parent, point, x, -5)
	b:SetText(title)
	b:SetScript("OnClick", action)
	return b
end

function notes.EnsureWindow()
	if notes.window then return notes.window end
	if type(CreateFrame) ~= "function" then return nil end
	local s = notes.Style()
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
	-- Hiding a focused editor must release focus so it cannot swallow keys while
	-- the window is closed (Close, Escape or a reload).
	f:SetScript("OnHide", function() if f.edit then safe(f.edit, "ClearFocus") end end)
	f:SetSize(s.width, s.height)
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	f:SetBackdropBorderColor(0.18, 0.38, 0.4, 0.9)

	local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	title:SetPoint("TOPLEFT", f, "TOPLEFT", 10, -8)
	title:SetWidth(160)
	title:SetJustifyH("LEFT")
	title:SetText("Notes")
	f.title = title

	f.collapse = button(f, notes.IsCollapsed() and "Expand" or "Collapse", 74, "TOPRIGHT", -30,
		function() notes.SetCollapsed(not notes.IsCollapsed()) end)
	f.close = button(f, "X", 20, "TOPRIGHT", -6, function() notes.Close() end)

	local edit = CreateFrame("EditBox", nil, f, "BackdropTemplate")
	edit:SetMultiLine(true)
	edit:SetAutoFocus(false)
	edit:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -TITLE_HEIGHT)
	edit:SetTextInsets(6, 6, 6, 6)
	edit:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	edit:SetBackdropColor(0, 0, 0, 0.35)
	edit:SetBackdropBorderColor(0.2, 0.3, 0.34, 0.8)
	edit:SetScript("OnTextChanged", function(self) notes.OnEditorChanged(self) end)
	edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
	f.edit = edit

	local hint = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
	hint:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 10, 5)
	hint:SetWidth(s.width - 20)
	hint:SetJustifyH("LEFT")
	hint:SetText("")
	f.hint = hint

	notes.RestorePosition()
	notes.ApplyStyle()
	notes.ApplyCollapsed()
	notes.RefreshText()
	notes.RefreshEditable()
	return f
end

function notes.Open()
	local f = notes.EnsureWindow()
	if not f then return nil end
	local d = data()
	if d then d.shown = true end
	notes.RefreshText()
	notes.RefreshEditable()
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
