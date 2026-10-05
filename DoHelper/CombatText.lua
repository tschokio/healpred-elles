-- DoHelper / CombatText.lua
-- A small, centered "+ combat" / "- combat" info line shown on the combat
-- transitions, with persisted styling and an optional short scroll. It is
-- independent of the healing helper: its own event frame drives it, so it keeps
-- working when prediction is off. There is no idle timer: the only OnUpdate
-- exists while a timed line is fading out or a scroll is still running.
local _, ns = ...

local combat = {}
ns.combatText = combat

local FONT = "Fonts\\FRIZQT__.TTF"
local LIMITS = {
	fontSize = { 8, 60 },
	duration = { 0, 30 },
	fade = { 0, 5 },
	offset = { -4000, 4000 },
	distance = { 0, 100 },
	motion = { 0.1, 10 },
}
local MAX_LABEL = 40
local DEFAULT_DISTANCE = 18
local DEFAULT_MOTION = 1
local DEFAULT_ENTER_COLOR = { 0.35, 0.88, 0.55 }
local DEFAULT_LEAVE_COLOR = { 0.62, 0.74, 0.88 }
local DEFAULT_LEGACY_COLOR = { 1.0, 0.9, 0.3 }

local function safe(obj, method, ...)
	if obj and type(obj[method]) == "function" then return obj[method](obj, ...) end
end

local function clamp(n, lo, hi)
	if n < lo then return lo end
	if n > hi then return hi end
	return n
end

-- A secret or non-numeric colour component falls back to its default instead of
-- reaching a comparison (ns.toNumber refuses secrets before any arithmetic).
local function component(t, i, default)
	local v = type(t) == "table" and ns.toNumber(t[i]) or nil
	if v == nil then return default end
	return clamp(v, 0, 1)
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
	-- `color` is the legacy single-colour fallback; the new fields win when they
	-- are present and readable. A secret/invalid table falls back safely.
	local legacy = type(d.color) == "table" and d.color or DEFAULT_LEGACY_COLOR
	local enter = type(d.enterColor) == "table" and d.enterColor or legacy
	local leave = type(d.leaveColor) == "table" and d.leaveColor or legacy
	local direction = "up"
	if d.direction == "down" or d.direction == "none" then direction = d.direction end
	local distance = ns.toNumber(d.distance)
	if distance == nil then distance = DEFAULT_DISTANCE end
	local motion = ns.toNumber(d.motion)
	if motion == nil then motion = DEFAULT_MOTION end
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
		color = { component(legacy, 1, 1), component(legacy, 2, 0.9), component(legacy, 3, 0.3) },
		enterColor = { component(enter, 1, DEFAULT_ENTER_COLOR[1]), component(enter, 2, DEFAULT_ENTER_COLOR[2]), component(enter, 3, DEFAULT_ENTER_COLOR[3]) },
		leaveColor = { component(leave, 1, DEFAULT_LEAVE_COLOR[1]), component(leave, 2, DEFAULT_LEAVE_COLOR[2]), component(leave, 3, DEFAULT_LEAVE_COLOR[3]) },
		background = { component(d.background, 1, 0), component(d.background, 2, 0), component(d.background, 3, 0), component(d.background, 4, 0) },
		direction = direction,
		distance = clamp(distance, LIMITS.distance[1], LIMITS.distance[2]),
		motion = clamp(motion, LIMITS.motion[1], LIMITS.motion[2]),
	}
end

local function validRGB(t)
	if type(t) ~= "table" then return nil end
	local out = {}
	for i = 1, 3 do
		local v = ns.toNumber(t[i])
		if not (ns.isFinite(v) and v <= 1) then return nil end
		out[i] = v
	end
	return out
end

-- Atomic validation. Nothing is written unless every supplied value is
-- acceptable. `color` is the legacy single colour: an old caller that supplies
-- only `color` still works and now sets both enter and leave. Omitting the new
-- fields leaves the saved enter/leave colours untouched.
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
	local background = style.background
	if type(background) ~= "table" then return false, "Missing background values." end
	for i = 1, 4 do
		local v = ns.toNumber(background[i])
		if not (ns.isFinite(v) and v <= 1) then return false, "Background RGBA must be 0-1 each." end
	end
	local legacy, enter, leave
	if style.color ~= nil then
		legacy = validRGB(style.color)
		if not legacy then return false, "Text RGB must be 0-1 each." end
	end
	if style.enterColor ~= nil then
		enter = validRGB(style.enterColor)
		if not enter then return false, "Enter text RGB must be 0-1 each." end
	end
	if style.leaveColor ~= nil then
		leave = validRGB(style.leaveColor)
		if not leave then return false, "Leave text RGB must be 0-1 each." end
	end
	local direction
	if style.direction ~= nil then
		local v = type(style.direction) == "string" and style.direction:lower() or nil
		if v ~= "up" and v ~= "down" and v ~= "none" then
			return false, "Direction must be up, down or none."
		end
		direction = v
	end
	local distance
	if style.distance ~= nil then
		local v = ns.toNumber(style.distance)
		if not (ns.isFinite(v) and v <= LIMITS.distance[2]) then return false, "Distance must be 0-100 pixels." end
		distance = v
	end
	local motion
	if style.motion ~= nil then
		local v = ns.toNumber(style.motion)
		if not (ns.isFinite(v) and v >= LIMITS.motion[1] and v <= LIMITS.motion[2]) then
			return false, "Motion must be 0.1-10 seconds."
		end
		motion = v
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
	d.background = { ns.toNumber(background[1]), ns.toNumber(background[2]), ns.toNumber(background[3]), ns.toNumber(background[4]) }
	if legacy then d.color = { legacy[1], legacy[2], legacy[3] } end
	if enter then
		d.enterColor = { enter[1], enter[2], enter[3] }
	elseif legacy then
		d.enterColor = { legacy[1], legacy[2], legacy[3] }
	end
	if leave then
		d.leaveColor = { leave[1], leave[2], leave[3] }
	elseif legacy then
		d.leaveColor = { legacy[1], legacy[2], legacy[3] }
	end
	if direction then d.direction = direction end
	if distance ~= nil then d.distance = distance end
	if motion ~= nil then d.motion = motion end
	if enterText then d.enterText = enterText end
	if leaveText then d.leaveText = leaveText end
	if style.enabled ~= nil then d.enabled = style.enabled and true or false end
	combat.Refresh()
	return true
end

-- Move the saved base position only; an animated offset is never written here.
function combat.SetPosition(x, y)
	local nx, ny = ns.toNumber(x), ns.toNumber(y)
	if nx == nil or nx < LIMITS.offset[1] or nx > LIMITS.offset[2] then return false, "X offset must be -4000 to 4000." end
	if ny == nil or ny < LIMITS.offset[1] or ny > LIMITS.offset[2] then return false, "Y offset must be -4000 to 4000." end
	local d = data()
	if not d then return false, "Settings unavailable." end
	d.x, d.y = nx, ny
	combat.StopMotion(combat.window)
	combat.RestorePosition()
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

-- Current animated delta. RestorePosition adds it to the saved base, so the
-- saved base itself is never polluted by a running scroll.
local function motionDelta(f)
	if not f then return 0, 0 end
	return ns.toNumber(f.animX) or 0, ns.toNumber(f.animY) or 0
end

-- Stop any running scroll and reset the visible delta to zero. The frame stays
-- where RestorePosition puts it (the saved base).
function combat.StopMotion(f)
	f = f or combat.window
	if not f then return end
	f.animStart, f.animDuration = nil, nil
	f.animDx, f.animDy = 0, 0
	f.animX, f.animY = 0, 0
end

function combat.RestorePosition()
	local f = combat.window
	if not f or not UIParent or type(f.SetPoint) ~= "function" then return end
	local s = combat.Style()
	local dx, dy = motionDelta(f)
	f:ClearAllPoints()
	f:SetPoint("CENTER", UIParent, "CENTER", s.x + dx, s.y + dy)
end

function combat.SavePosition()
	local f = combat.window
	if not f or not UIParent or type(f.GetCenter) ~= "function" then return end
	local cx, cy = f:GetCenter()
	local ux, uy = UIParent:GetCenter()
	if type(cx) ~= "number" or type(cy) ~= "number" or type(ux) ~= "number" or type(uy) ~= "number" then return end
	local d = data()
	if not d then return end
	-- The frame may be mid-scroll; save the base (centre minus the animated
	-- delta) so a running animation can never overwrite the user's position.
	local dx, dy = motionDelta(f)
	d.x, d.y = cx - ux - dx, cy - uy - dy
end

function combat.ApplyStyle()
	local f = combat.window
	if not f then return end
	local s = combat.Style()
	local flags = s.outline and "OUTLINE" or ""
	-- The visible colour follows the transition: enter and leave are independent.
	local color = combat.current == "leave" and s.leaveColor or s.enterColor
	safe(f.label, "SetFont", FONT, s.fontSize, flags)
	safe(f.label, "SetTextColor", color[1], color[2], color[3], 1)
	safe(f, "SetBackdropColor", s.background[1], s.background[2], s.background[3], s.background[4])
	resize(f)
	combat.RestorePosition()
	if not f.hideAt then f:SetAlpha(s.opacity) end
end

function combat.OnUpdate(f)
	local s = combat.Style()
	local now = ns.now()
	if f.animStart then
		local elapsed = now - f.animStart
		local duration = ns.toNumber(f.animDuration) or s.motion
		local p = duration > 0 and elapsed / duration or 1
		if p < 0 then p = 0 elseif p > 1 then p = 1 end
		p = p * p * (3 - 2 * p) -- smoothstep: subtle, deterministic, seek-safe
		f.animX, f.animY = (f.animDx or 0) * p, (f.animDy or 0) * p
		combat.RestorePosition()
		if p >= 1 then
			f.animStart, f.animDuration = nil, nil
		end
	end
	local remaining = f.hideAt and (f.hideAt - now) or nil
	if remaining then
		if s.fade > 0 and remaining < s.fade then
			f:SetAlpha(math.max(0, s.opacity * (remaining / s.fade)))
		else
			f:SetAlpha(s.opacity)
		end
	end
	if remaining and remaining <= 0 then
		f.hideAt = nil
		f:SetScript("OnUpdate", nil)
		f:SetAlpha(s.opacity)
		f:Hide()
	elseif not f.hideAt and not f.animStart then
		-- A sticky line whose scroll finished: settle here, no permanent updater.
		f:SetScript("OnUpdate", nil)
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
	-- A hidden frame must never keep a scroll or fade updater alive, whichever
	-- path hid it.
	f:SetScript("OnHide", function(self)
		self.hideAt = nil
		safe(self, "SetScript", "OnUpdate", nil)
		combat.StopMotion(self)
	end)
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
	f.hideAt = nil
	f:SetScript("OnUpdate", nil)
	combat.StopMotion(f)
	combat.ApplyStyle()
	f:SetAlpha(s.opacity)
	f:Show()
	if combat.unlocked then
		-- Frozen at the saved base while unlocked, so dragging can never capture
		-- an animated offset.
		return f
	end
	local moving = s.distance > 0 and s.direction ~= "none" and s.motion > 0
	if moving then
		local sign = s.direction == "down" and -1 or 1
		f.animDx, f.animDy = 0, sign * s.distance
		f.animStart, f.animDuration = ns.now(), s.motion
		combat.RestorePosition() -- every transition restarts from the saved base
	end
	if s.duration > 0 then f.hideAt = ns.now() + s.duration end
	if f.hideAt or f.animStart then
		f:SetScript("OnUpdate", combat.OnUpdate)
	else
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
	combat.StopMotion(f)
	f:SetAlpha(combat.Style().opacity)
	f:Hide()
end

-- The line is click-through unless the user has unlocked it for dragging, and it
-- is ALWAYS click-through during combat so it can never eat a combat click even
-- if it was left unlocked.
local function applyMouse(f)
	if not f then return end
	local locked = ns.api and ns.api.InCombat and ns.api.InCombat()
	f:EnableMouse(combat.unlocked and not locked)
end

-- Session-only positioning aid: while unlocked the line is visible and mouse
-- enabled so it can be dragged; locking hides it and restores click-through.
function combat.SetUnlocked(value)
	combat.unlocked = value and true or false
	if not combat.unlocked then
		local existing = combat.window
		if not existing then return end
		applyMouse(existing)
		existing:SetScript("OnDragStart", nil)
		existing:SetScript("OnDragStop", nil)
		combat.Hide()
		return
	end
	local f = combat.EnsureFrame()
	if not f then return end
	applyMouse(f)
	safe(f, "RegisterForDrag", "LeftButton")
	f:SetScript("OnDragStart", function(self) safe(self, "StartMoving") end)
	f:SetScript("OnDragStop", function(self)
		safe(self, "StopMovingOrSizing")
		combat.SavePosition()
	end)
	f.hideAt = nil
	f:SetScript("OnUpdate", nil)
	combat.StopMotion(f) -- drag from the saved base, never from a motion offset
	if f.label:GetText() == "" then f.label:SetText(combat.Style().enterText) end
	combat.ApplyStyle()
	f:SetAlpha(combat.Style().opacity)
	f:Show()
end

function combat.Refresh()
	if not combat.Enabled() then combat.Hide() end
	if combat.window then combat.ApplyStyle() end
	if ns.optionsWindow and ns.optionsWindow.Refresh then ns.optionsWindow.Refresh() end
end

function combat.HandleEvent(event)
	if event == "PLAYER_REGEN_DISABLED" then
		combat.Show("enter")
		applyMouse(combat.window) -- force click-through during combat
	elseif event == "PLAYER_REGEN_ENABLED" then
		combat.Show("leave")
		applyMouse(combat.window) -- restore drag if the user left it unlocked
	end
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
