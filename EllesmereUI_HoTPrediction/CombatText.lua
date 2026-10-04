-- EllesmereUI_HoTPrediction / CombatText.lua
-- A small, centered "+ combat" / "- combat" info line shown on the combat
-- transitions, with persisted styling. It is independent of the healing helper:
-- its own event frame drives it, so it keeps working when prediction is off.
-- There is no idle timer: the only OnUpdate exists while a timed line is visible.
local _, ns = ...

local combat = {}
ns.combatText = combat

local FONT = "Fonts\\FRIZQT__.TTF"
local LIMITS = {
	fontSize = { 8, 60 },
	duration = { 0, 30 },
	fade = { 0, 5 },
	offset = { -4000, 4000 },
}
local MAX_LABEL = 40

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
	if type(ns.db.combatText) ~= "table" then ns.db.combatText = {} end
	return ns.db.combatText
end

local function cleanLabel(value)
	if ns.isSecret(value) or type(value) ~= "string" then return nil end
	value = value:gsub("^%s+", ""):gsub("%s+$", "")
	if value == "" then return nil end
	if #value > MAX_LABEL or value:find("[|\r\n]") then return nil end
	return value
end

function combat.Enabled()
	return (ns.db and ns.db.combatText and ns.db.combatText.enabled) and true or false
end

-- Forgiving clamp used for live apply and every render.
function combat.Style()
	local d = data() or {}
	local width = ns.isFinite(d.fontSize) and d.fontSize or 22
	local duration = ns.isFinite(d.duration) and d.duration or 2
	local fade = ns.isFinite(d.fade) and d.fade or 0.5
	local opacity = ns.isFinite(d.opacity) and d.opacity or 1
	local color = type(d.color) == "table" and d.color or { 1.0, 0.9, 0.3 }
	local background = type(d.background) == "table" and d.background or { 0, 0, 0, 0 }
	-- Offsets are signed, so they cannot use ns.isFinite (which also requires >= 0).
	local x = ns.toNumber(d.x)
	local y = ns.toNumber(d.y)
	if x == nil then x = 0 end
	if y == nil then y = 0 end
	return {
		enabled = d.enabled ~= false,
		x = clamp(x, LIMITS.offset[1], LIMITS.offset[2]),
		y = clamp(y, LIMITS.offset[1], LIMITS.offset[2]),
		enterText = cleanLabel(d.enterText) or "+ combat",
		leaveText = cleanLabel(d.leaveText) or "- combat",
		fontSize = clamp(width, LIMITS.fontSize[1], LIMITS.fontSize[2]),
		duration = clamp(duration, LIMITS.duration[1], LIMITS.duration[2]),
		fade = clamp(fade, LIMITS.fade[1], LIMITS.fade[2]),
		opacity = clamp(opacity, 0, 1),
		outline = d.outline and true or false,
		color = { clamp(color[1] or 1, 0, 1), clamp(color[2] or 0.9, 0, 1), clamp(color[3] or 0.3, 0, 1) },
		background = { clamp(background[1] or 0, 0, 1), clamp(background[2] or 0, 0, 1),
			clamp(background[3] or 0, 0, 1), clamp(background[4] or 0, 0, 1) },
	}
end

-- Atomic validation. Nothing is written unless every value is acceptable.
function combat.SetStyle(style)
	if type(style) ~= "table" then return false, "No style values supplied." end
	local fontSize, duration, fade = ns.toNumber(style.fontSize), ns.toNumber(style.duration), ns.toNumber(style.fade)
	local opacity = ns.toNumber(style.opacity)
	local x, y = ns.toNumber(style.x), ns.toNumber(style.y)
	if not (ns.isFinite(fontSize) and fontSize >= LIMITS.fontSize[1] and fontSize <= LIMITS.fontSize[2]) then
		return false, "Font size must be 8-60."
	end
	if not (ns.isFinite(duration) and duration >= LIMITS.duration[1] and duration <= LIMITS.duration[2]) then
		return false, "Show seconds must be 0-30 (0 = until the next change)."
	end
	if not (ns.isFinite(fade) and fade >= LIMITS.fade[1] and fade <= LIMITS.fade[2]) then
		return false, "Fade seconds must be 0-5."
	end
	if not (ns.isFinite(opacity) and opacity <= 1) then return false, "Opacity must be 0-1." end
	-- x/y are signed offsets; ns.toNumber already refused secret/non-finite values.
	if x == nil or x < LIMITS.offset[1] or x > LIMITS.offset[2] then return false, "X offset must be -4000 to 4000." end
	if y == nil or y < LIMITS.offset[1] or y > LIMITS.offset[2] then return false, "Y offset must be -4000 to 4000." end
	local color, background = style.color, style.background
	if type(color) ~= "table" or type(background) ~= "table" then return false, "Missing colour values." end
	for i = 1, 3 do
		local v = ns.toNumber(color[i])
		if not (ns.isFinite(v) and v <= 1) then return false, "Text RGB must be 0-1 each." end
	end
	for i = 1, 4 do
		local v = ns.toNumber(background[i])
		if not (ns.isFinite(v) and v <= 1) then return false, "Background RGBA must be 0-1 each." end
	end
	local enterText, leaveText = nil, nil
	if style.enterText ~= nil then
		enterText = cleanLabel(style.enterText)
		if not enterText then return false, "Enter text must be 1-40 characters without | or line breaks." end
	end
	if style.leaveText ~= nil then
		leaveText = cleanLabel(style.leaveText)
		if not leaveText then return false, "Leave text must be 1-40 characters without | or line breaks." end
	end
	local d = data()
	if not d then return false, "Settings unavailable." end
	d.fontSize, d.duration, d.fade, d.opacity = fontSize, duration, fade, opacity
	d.x, d.y = x, y
	d.outline = style.outline and true or false
	d.color = { ns.toNumber(color[1]), ns.toNumber(color[2]), ns.toNumber(color[3]) }
	d.background = { ns.toNumber(background[1]), ns.toNumber(background[2]), ns.toNumber(background[3]), ns.toNumber(background[4]) }
	if enterText then d.enterText = enterText end
	if leaveText then d.leaveText = leaveText end
	combat.ApplyStyle()
	return true
end

-- Size the frame so an optional background hugs the text.
local function resize(f)
	local l = f.label
	local w = type(l.GetStringWidth) == "function" and l:GetStringWidth() or 0
	local h = type(l.GetStringHeight) == "function" and l:GetStringHeight() or 0
	w, h = ns.toNumber(w) or 0, ns.toNumber(h) or 0
	f:SetSize(math.max(1, w + 16), math.max(1, h + 8))
end

function combat.RestorePosition()
	local f = combat.window
	if not f or not UIParent or type(f.SetPoint) ~= "function" then return end
	local s = combat.Style()
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", s.x, s.y)
end

function combat.SavePosition()
	local f = combat.window
	if not f or not UIParent or type(f.GetCenter) ~= "function" then return end
	local cx, cy = f:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if type(cx) ~= "number" or type(cy) ~= "number" or type(ux) ~= "number" or type(uy) ~= "number" then return end
	local d = data()
	if not d then return end
	d.x, d.y = cx - ux, cy - uy
end

function combat.ApplyStyle()
	local f = combat.window
	if not f then return end
	local s = combat.Style()
	local flags = s.outline and "OUTLINE" or ""
	safe(f.label, "SetFont", FONT, s.fontSize, flags)
	safe(f.label, "SetTextColor", s.color[1], s.color[2], s.color[3], 1)
	safe(f, "SetBackdropColor", s.background[1], s.background[2], s.background[3], s.background[4])
	resize(f)
	combat.RestorePosition()
	if not f.hideAt then f:SetAlpha(s.opacity) end
end

function combat.OnUpdate(f)
	local s = combat.Style()
	if not f.hideAt then
		f:SetScript("OnUpdate", nil)
		return
	end
	local remaining = f.hideAt - ns.now()
	if s.fade > 0 and remaining < s.fade then
		f:SetAlpha(math.max(0, s.opacity * (remaining / s.fade)))
	else
		f:SetAlpha(s.opacity)
	end
	if remaining <= 0 then
		f.hideAt = nil
		f:SetScript("OnUpdate", nil)
		f:SetAlpha(s.opacity)
		f:Hide()
	end
end

function combat.EnsureFrame()
	if combat.window then return combat.window end
	if type(CreateFrame) ~= "function" then return nil end
	local f = CreateFrame("Frame", "EllesmereUI_HoTPredictionCombatText", UIParent, "BackdropTemplate")
	combat.window = f
	f:SetFrameStrata("DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(false) -- never intercept clicks unless the user unlocks to drag
	f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
	f:SetBackdropBorderColor(0, 0, 0, 0)
	local label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
	label:SetPoint("CENTER", f, "CENTER", 0, 0)
	label:SetJustifyH("CENTER")
	label:SetJustifyV("MIDDLE")
	label:SetText("")
	f.label = label
	combat.ApplyStyle()
	f:Hide()
	return f
end

local function display(kind)
	local f = combat.EnsureFrame()
	if not f then return nil end
	local s = combat.Style()
	f.label:SetText(kind == "leave" and s.leaveText or s.enterText)
	combat.current = kind
	combat.ApplyStyle()
	f:SetAlpha(s.opacity)
	f:Show()
	if s.duration > 0 and not combat.unlocked then
		f.hideAt = ns.now() + s.duration
		f:SetScript("OnUpdate", combat.OnUpdate)
	else
		f.hideAt = nil
		f:SetScript("OnUpdate", nil)
	end
	return f
end

function combat.Show(kind)
	if not combat.Enabled() then
		combat.Hide()
		return
	end
	display(kind)
end

function combat.Preview(kind)
	display(kind)
end

function combat.Hide()
	local f = combat.window
	if not f then return end
	f.hideAt = nil
	f:SetScript("OnUpdate", nil)
	f:SetAlpha(combat.Style().opacity)
	f:Hide()
end

-- Session-only positioning aid: while unlocked the line is visible and mouse
-- enabled so it can be dragged; locking hides it and restores click-through.
function combat.SetUnlocked(value)
	combat.unlocked = value and true or false
	if not combat.unlocked then
		local existing = combat.window
		if not existing then return end
		existing:EnableMouse(false)
		existing:SetScript("OnDragStart", nil)
		existing:SetScript("OnDragStop", nil)
		combat.Hide()
		return
	end
	local f = combat.EnsureFrame()
	if not f then return end
	f:EnableMouse(true)
	safe(f, "RegisterForDrag", "LeftButton")
	f:SetScript("OnDragStart", function(self) safe(self, "StartMoving") end)
	f:SetScript("OnDragStop", function(self)
		safe(self, "StopMovingOrSizing")
		combat.SavePosition()
	end)
	f.hideAt = nil
	f:SetScript("OnUpdate", nil)
	if f.label:GetText() == "" then f.label:SetText(combat.Style().enterText) end
	combat.ApplyStyle()
	f:SetAlpha(combat.Style().opacity)
	f:Show()
end

function combat.Refresh()
	if not combat.Enabled() then combat.Hide() end
	if combat.window then combat.ApplyStyle() end
end

function combat.HandleEvent(event)
	if event == "PLAYER_REGEN_DISABLED" then combat.Show("enter")
	elseif event == "PLAYER_REGEN_ENABLED" then combat.Show("leave") end
end

function combat.Setup()
	if combat.eventFrame then return end
	if type(CreateFrame) ~= "function" then return end
	local f = CreateFrame("Frame")
	combat.eventFrame = f
	for _, event in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED" }) do
		pcall(f.RegisterEvent, f, event)
	end
	f:SetScript("OnEvent", function(_, event) combat.HandleEvent(event) end)
end
