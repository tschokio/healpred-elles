-- tests/wowenv.lua
-- Mock World of Warcraft environment sufficient to load and exercise the addon
-- under a plain Lua interpreter. Nothing here is shipped to the client.

local unpack = unpack or table.unpack
local Mocks = {}
_G.Mocks = Mocks

-- ReadFile is provided by tests/run.lua (from an embedded source map under
-- fengari, or io.open under a real Lua interpreter).
local function readSource(path)
	if _G.ReadFile then return _G.ReadFile(path) end
	return nil
end

------------------------------------------------------------------------------
-- secret values: any arithmetic/comparison/index/len raises, like the client
------------------------------------------------------------------------------

local secretMT = {}
for _, op in ipairs({
	"__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm", "__idiv",
	"__lt", "__le", "__gt", "__ge", "__eq", "__concat", "__len", "__index", "__newindex", "__call",
}) do
	secretMT[op] = function() error("attempt to use a secret value", 2) end
end

function Mocks.MakeSecret()
	local t = setmetatable({}, secretMT)
	rawset(t, "__secret", true)
	return t
end

function Mocks.IsSecretlike(v)
	return type(v) == "table" and rawget(v, "__secret") == true
end

------------------------------------------------------------------------------
-- frame widget mock
------------------------------------------------------------------------------

local FrameMT = {}
FrameMT.__index = FrameMT
local frameSeq = 0

local function newTexture(owner)
	return {
		_owner = owner,
		_path = nil,
		_points = {},
		_masks = {},
		_rotation = 0,
		SetTexture = function(self, p) self._path = p end,
		GetTexture = function(self) return self._path end,
		SetPoint = function(self, ...) self._points[#self._points + 1] = { ... } end,
		ClearAllPoints = function(self) self._points = {} end,
		AddMaskTexture = function(self, m) self._masks[#self._masks + 1] = m end,
		RemoveMaskTexture = function(self, m)
			for i = #self._masks, 1, -1 do if self._masks[i] == m then table.remove(self._masks, i) end end
		end,
		GetMaskTextureCount = function(self) return #self._masks end,
		SetRotation = function(self, r) self._rotation = r end,
		GetRotation = function(self) return self._rotation end,
	}
end

local function newFrame(frameType, name, parent, template)
	frameSeq = frameSeq + 1
	local f = setmetatable({
		_type = frameType or "Frame",
		_template = template,
		_name = name,
		_parent = parent,
		_points = {},
		_shown = true,
		_width = 100, _height = 20,
		_min = 0, _max = 1, _value = 0,
		_orientation = "HORIZONTAL", _reverse = false,
		_color = { 1, 1, 1 }, _alpha = 1,
		_level = 1, _strata = "MEDIUM",
		_scripts = {}, _events = {}, _children = {},
		_text = "", _selStart = 0, _selEnd = 0, _focus = false,
		_seq = frameSeq,
	}, FrameMT)
	f._sbTexture = newTexture(f)
	if parent and parent._children then
		parent._children[#parent._children + 1] = f
	end
	-- Named frames are global in the real client; mirror that so tests can assert
	-- one reusable frame and so named globals can be cleaned up between envs.
	if name then
		_G[name] = f
		if Mocks.namedGlobals then Mocks.namedGlobals[name] = f end
	end
	Mocks.frames[#Mocks.frames + 1] = f
	return f
end

-- A minimal FontString: enough to record what the window sets and to read it
-- back in tests. Widgets in the real client also expose these methods.
local function newFontString(owner)
	return {
		_owner = owner,
		_text = "",
		_points = {},
		SetText = function(self, t) self._text = tostring(t or "") end,
		GetText = function(self) return self._text end,
		SetFont = function(self, ...) self._font = { ... } end,
		GetFont = function(self) return self._font and unpack(self._font) end,
		SetTextColor = function(self, r, g, b, a) self._color = { r, g, b, a } end,
		GetTextColor = function(self)
			local c = self._color or { 1, 1, 1, 1 }
			return c[1], c[2], c[3], c[4]
		end,
		SetJustifyH = function(self, j) self._justifyH = j end,
		SetJustifyV = function(self, j) self._justifyV = j end,
		SetWordWrap = function(self, w) self._wordWrap = w end,
		SetPoint = function(self, ...) self._points[#self._points + 1] = { ... } end,
		ClearAllPoints = function(self) self._points = {} end,
		SetWidth = function(self, w) self._width = w end,
		GetWidth = function(self) return self._width end,
		SetSize = function(self, w, h) self._width, self._height = w, h end,
		GetStringWidth = function(self) return #self._text * 6 end,
		GetStringHeight = function(self)
			local columns = math.max(1, math.floor((self._width or 556) / 6))
			local rows = 0
			for line in (self._text .. "\n"):gmatch("([^\n]*)\n") do
				rows = rows + math.max(1, math.ceil(#line / columns))
			end
			return rows * 12
		end,
		Hide = function(self) self._shown = false end,
	}
end

function FrameMT:SetPoint(...)
	local args = { ... }
	-- normalise optional relativeTo omitted form
	if #args >= 2 and type(args[2]) ~= "table" and args[2] ~= nil then
		-- point, x, y form relative to parent
		args = { args[1], self._parent, args[1], args[2], args[3], args[4] }
	end
	self._points[#self._points + 1] = args
end
function FrameMT:ClearAllPoints() self._points = {} end
function FrameMT:SetAllPoints(ref) self._points = { { "ALL", ref or self._parent } } end
function FrameMT:GetPoint(i)
	local p = self._points[i or 1]
	if not p then return nil end
	return unpack(p)
end
function FrameMT:SetSize(w, h) self._width, self._height = w, h end
function FrameMT:SetWidth(w) self._width = w end
function FrameMT:SetHeight(h) self._height = h end
function FrameMT:GetWidth() return self._width end
function FrameMT:GetHeight() return self._height end
function FrameMT:Show() self._shown = true end
-- Hiding fires OnHide (like the client) so an OnHide-based cleanup is exercised.
function FrameMT:Hide()
	local was = self._shown
	self._shown = false
	if was and self._scripts["OnHide"] then pcall(self._scripts["OnHide"], self) end
end
function FrameMT:SetShown(v)
	if v then self:Show() else self:Hide() end
end
function FrameMT:IsShown() return self._shown end
function FrameMT:GetParent() return self._parent end
function FrameMT:SetParent(p) self._parent = p end
function FrameMT:GetName() return self._name end
function FrameMT:GetAttribute(name) return self._attributes and self._attributes[name] end
function FrameMT:SetAttribute(name, v) self._attributes = self._attributes or {}; self._attributes[name] = v end
function FrameMT:GetFrameLevel() return self._level end
function FrameMT:SetFrameLevel(l) self._level = l end
function FrameMT:GetFrameStrata() return self._strata end
function FrameMT:SetFrameStrata(s) self._strata = s end
function FrameMT:CreateTexture() return newTexture(self) end
function FrameMT:GetStatusBarTexture() return self._sbTexture end
function FrameMT:SetStatusBarTexture(t)
	if type(t) == "string" then
		self._sbTexture._path = t
	elseif type(t) == "table" then
		self._sbTexture = t
	end
end
function FrameMT:SetMinMaxValues(a, b)
	if Mocks.rejectSecretRange and Mocks.IsSecretlike(b) then
		error("setter refuses secret range")
	end
	self._min, self._max = a, b
end
function FrameMT:GetMinMaxValues() return self._min, self._max end
function FrameMT:SetValue(v) self._value = v end
function FrameMT:GetValue() return self._value end
function FrameMT:SetStatusBarColor(r, g, b) self._color = { r, g, b } end
function FrameMT:GetStatusBarColor() return self._color[1], self._color[2], self._color[3] end
function FrameMT:SetStatusBarAlpha(a) self._sbAlpha = a end
function FrameMT:GetStatusBarAlpha() return self._sbAlpha or self._alpha end
function FrameMT:SetAlpha(a) self._alpha = a end
function FrameMT:GetAlpha() return self._alpha end
function FrameMT:SetOrientation(o) self._orientation = o end
function FrameMT:GetOrientation() return self._orientation end
function FrameMT:SetReverseFill(v) self._reverse = v and true or false end
function FrameMT:IsReverseFill() return self._reverse end
function FrameMT:GetReverseFill() return self._reverse end
function FrameMT:RegisterEvent(e)
	self._events[e] = true
	if Mocks.registrationAttempts then
		Mocks.registrationAttempts[e] = (Mocks.registrationAttempts[e] or 0) + 1
	end
end
function FrameMT:UnregisterEvent(e) self._events[e] = nil end
function FrameMT:SetScript(name, fn) self._scripts[name] = fn end
function FrameMT:GetScript(name) return self._scripts[name] end
function FrameMT:HookScript(name, fn)
	local orig = self._scripts[name]
	self._scripts[name] = function(...) if orig then orig(...) end return fn(...) end
end

-- Layout / behaviour toggles used by the debug window (real frame methods).
function FrameMT:EnableMouse(v) self._mouseEnabled = v and true or false end
function FrameMT:SetMovable(v) self._movable = v and true or false end
function FrameMT:IsMovable() return self._movable and true or false end
function FrameMT:SetClampedToScreen(v) self._clamped = v and true or false end
function FrameMT:IsClampedToScreen() return self._clamped and true or false end
function FrameMT:SetToplevel(v) self._toplevel = v and true or false end
function FrameMT:StartMoving() self._moving = true end
function FrameMT:StopMovingOrSizing() self._moving = false end

-- FontString creation (enough for title/instruction labels).
function FrameMT:CreateFontString(name, layer, template)
	local text = newFontString(self)
	text._template = template
	self._fontStrings = self._fontStrings or {}
	self._fontStrings[#self._fontStrings + 1] = text
	return text
end

-- Text on buttons/frames.
function FrameMT:SetText(t)
	self._text = tostring(t or "")
	local cb = self._scripts["OnTextChanged"]
	if cb then cb(self, false) end
end
function FrameMT:GetText() return self._text end

-- EditBox + ScrollFrame surface. Real clients expose these on the widgets; a
-- user "typing" is modelled by SetText/Insert firing OnTextChanged.
function FrameMT:SetMultiLine(v) self._multiLine = v and true or false end
function FrameMT:IsMultiLine() return self._multiLine and true or false end
function FrameMT:SetAutoFocus(v) self._autoFocus = v and true or false end
function FrameMT:SetFont(path, size, flags) self._font = { path, size, flags } end
function FrameMT:GetFont() return self._font and unpack(self._font) end
function FrameMT:SetTextInsets(l, r, t, b) self._insets = { l, r, t, b } end
function FrameMT:SetJustifyH(j) self._justifyH = j end
function FrameMT:SetJustifyV(j) self._justifyV = j end
function FrameMT:HighlightText()
	self._selStart, self._selEnd = 0, #(self._text or "")
	self:SetFocus()
end
function FrameMT:SetFocus()
	if Mocks.focused and Mocks.focused ~= self then Mocks.focused._focus = false end
	self._focus = true
	Mocks.focused = self
end
function FrameMT:ClearFocus()
	self._focus = false
	if Mocks.focused == self then Mocks.focused = nil end
end
function FrameMT:HasFocus() return self._focus and true or false end
function FrameMT:SetCursorPosition(p)
	self._selStart = p or 0
	self._selEnd = self._selStart
end
function FrameMT:GetCursorPosition() return self._selStart or 0, self._selEnd or 0 end
function FrameMT:GetSelectedText()
	local s, e = self._selStart or 0, self._selEnd or 0
	if e > s then return (self._text or ""):sub(s + 1, e) end
	return ""
end
function FrameMT:Insert(t)
	self._text = (self._text or "") .. tostring(t or "")
	local cb = self._scripts["OnTextChanged"]
	if cb then cb(self, false) end
end
function FrameMT:SetScrollChild(c) self._scrollChild = c end
function FrameMT:GetScrollChild() return self._scrollChild end
function FrameMT:SetVerticalScroll(v) self._vscroll = v end
function FrameMT:GetVerticalScroll() return self._vscroll or 0 end
function FrameMT:SetHorizontalScroll(v) self._hscroll = v end
function FrameMT:GetHorizontalScroll() return self._hscroll or 0 end
function FrameMT:GetVerticalScrollRange()
	return math.max(0, (self._scrollChild and self._scrollChild:GetHeight() or 0) - self:GetHeight())
end
function FrameMT:UpdateScrollChildRect() self._scrollUpdated = true end
function FrameMT:EnableMouseWheel(v) self._wheelEnabled = v end
function FrameMT:SetClipsChildren(v) self._clipsChildren = v end
function FrameMT:RegisterForDrag(...) self._dragButtons = { ... } end
function FrameMT:SetMaxLetters(v) self._maxLetters = v end
function FrameMT:SetBackdrop(v) self._backdrop = v end
function FrameMT:SetBackdropColor(...) self._backdropColor = { ... } end
function FrameMT:SetBackdropBorderColor(...) self._borderColor = { ... } end
function FrameMT:SetTextColor(r, g, b, a) self._textColor = { r, g, b, a } end
function FrameMT:GetTextColor()
	local c = self._textColor or { 1, 1, 1, 1 }
	return c[1], c[2], c[3], c[4]
end

------------------------------------------------------------------------------
-- global mock environment
------------------------------------------------------------------------------

function Mocks.Reset()
	-- Clean up named frames from the previous environment so a named-global test
	-- (the debug window) cannot leak a stale frame into the next one.
	if Mocks.namedGlobals then
		for name in pairs(Mocks.namedGlobals) do _G[name] = nil end
	end
	Mocks.namedGlobals = {}
	Mocks.frames = {}
	Mocks.chat = {}
	Mocks.hooks = {}
	Mocks.tickers = {}
	Mocks.registrationAttempts = {}
	Mocks._ns = nil
	Mocks.focused = nil
	Mocks.now = 100
	Mocks.playerGUID = "Player-0001"
	Mocks.health = 5000
	Mocks.maxHealth = 5000
	Mocks.healAbsorb = 0
	Mocks.inCombat = false
	Mocks.auras = {}
	Mocks.auraCalls = 0
	Mocks.cleu = nil
	Mocks.powerCalls = 0
	Mocks.healAbsorbApiPresent = true
	Mocks.rejectSecretRange = false

	_G.EllesmereUI_HoTPredictionDB = nil

	_G.UIParent = newFrame("Frame", "UIParent", nil)
	_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) Mocks.chat[#Mocks.chat + 1] = msg end }
	_G.SlashCmdList = {}
	-- Escape-to-close registry consumed by the client's FrameXML; the debug
	-- window appends its one named frame here. Reset per environment.
	_G.UISpecialFrames = {}
	_G.STANDARD_TEXT_FONT = "Fonts\\FRIZQT__.TTF"

	_G.CreateFrame = function(t, n, p, template) return newFrame(t, n, p, template) end
	_G.GetTime = function() return Mocks.now end
	-- Default mocked build is a clean (non-restricted) engine so the automatic
	-- learning tests exercise guarded CLEU registration. Restricted-client tests
	-- override this via Mocks.SetBuild / Mocks.NewEnv{ build = ... }.
	_G.GetBuildInfo = function() return "11.0.5", 58000, "2024-01-01", 110005 end
	_G.InCombatLockdown = function() return Mocks.inCombat end
	_G.UnitGUID = function() return Mocks.playerGUID end
	_G.UnitExists = function() return true end
	_G.UnitHealth = function() return Mocks.health end
	_G.UnitHealthMax = function() return Mocks.maxHealth end
	_G.UnitPower = function() Mocks.powerCalls = Mocks.powerCalls + 1; return 100000 end
	_G.UnitGetTotalHealAbsorbs = function()
		if not Mocks.healAbsorbApiPresent then error("missing heal absorb API") end
		return Mocks.healAbsorb
	end
	_G.UnitGetTotalAbsorbs = function() return 0 end
	_G.issecretvalue = Mocks.IsSecretlike
	_G.hooksecurefunc = function(tbl, name, fn)
		local orig = tbl[name]
		tbl[name] = function(...)
			if orig then orig(...) end
			return fn(...)
		end
		Mocks.hooks[#Mocks.hooks + 1] = { tbl = tbl, name = name, fn = fn }
		return true
	end
	_G.C_Timer = { NewTicker = function(interval, fn) Mocks.tickers[#Mocks.tickers + 1] = { interval = interval, fn = fn }; return { Cancel = function() end } end }
	_G.C_UnitAuras = {
		GetAuraDataByIndex = function(unit, i, filter)
			Mocks.auraCalls = Mocks.auraCalls + 1
			if unit ~= "player" then return nil end
			if not Mocks.auras or not Mocks.auras[i] then return nil end
			return Mocks.auras[i]
		end,
	}
	_G.CombatLogGetCurrentEventInfo = function()
		local t = Mocks.cleu
		if not t then return nil end
		local n = t.n or #t
		return unpack(t, 1, n)
	end
	_G.EllesmereUI = nil
end

function Mocks.SetNow(t) Mocks.now = t end
function Mocks.SetAuras(list, opts)
	Mocks.auras = list or {}
	if not (opts and opts.noInvalidate) and Mocks._ns and Mocks._ns.api then
		Mocks._ns.api.InvalidateAuraCache()
	end
end
function Mocks.SetCLEU(tuple)
	if type(tuple) ~= "table" then
		Mocks.cleu = nil
		return
	end
	if tuple.n == nil then tuple.n = #tuple end
	Mocks.cleu = tuple
end

-- Force the mocked GetBuildInfo tuple. `toc` is the 4th return (interface).
function Mocks.SetBuild(version, build, date, toc)
	_G.GetBuildInfo = function() return version, build, date, toc end
end
function Mocks.PackCLEU(...)
	return { n = select("#", ...), ... }
end
function Mocks.Fire(event, ...)
	-- route through the addon's own dispatcher
	if Mocks._ns and Mocks._ns.dispatch then
		return Mocks._ns.dispatch(event, ...)
	end
end

------------------------------------------------------------------------------
-- fake EllesmereUIUnitFrames
------------------------------------------------------------------------------

function Mocks.BuildEUF()
	local player = newFrame("Frame", "EUF_Player", _G.UIParent)
	player:SetFrameLevel(5)
	player:SetFrameStrata("MEDIUM")
	player._euiUnit = "player"

	local hp = newFrame("StatusBar", "EUF_PlayerHealth", player)
	hp:SetSize(200, 30)
	hp:SetMinMaxValues(0, Mocks.maxHealth)
	hp:SetValue(Mocks.health)
	hp:SetStatusBarTexture("Interface\\health.blp")
	hp:SetStatusBarColor(0, 1, 0)

	local missClip = newFrame("Frame", "EUF_MissClip", hp)
	local predMy = newFrame("StatusBar", "EUF_PredMy", missClip)
	predMy:SetMinMaxValues(0, Mocks.maxHealth)
	predMy:SetValue(0)
	predMy:SetStatusBarTexture("Interface\\pred.blp")
	predMy:SetStatusBarColor(102 / 255, 243 / 255, 102 / 255)

	local predOther = newFrame("StatusBar", "EUF_PredOther", missClip)
	predOther:SetMinMaxValues(0, Mocks.maxHealth)
	predOther:SetValue(0)
	predOther:SetStatusBarTexture("Interface\\pred.blp")
	predOther:SetStatusBarColor(40 / 255, 40 / 255, 40 / 255)
	predOther:Hide()

	local absorbMask = newFrame("Frame", "EUF_AbsorbMask", hp)
	local blizzMask = newFrame("Frame", "EUF_BlizzMask", hp)
	hp._blizzMask = blizzMask

	local ab = {
		_predOn = true,
		_isVert = false,
		_isReversed = false,
		_missClip = missClip,
		_predMy = predMy,
		_predOther = predOther,
		_absorbMask = absorbMask,
		_blizzMask = blizzMask,
		_blizzMaskOn = false,
	}
	player.Health = hp
	player.HealthPrediction = { damageAbsorb = ab }

	_G.EllesmereUI = {
		_ModuleNS = {
			EllesmereUIUnitFrames = {
				frames = { player = player },
				UF_HealPredApply = function() end,
				UF_AnchorHealPred = function() end,
				UF_HealPredLayout = function() end,
				UF_PaintHealPred = function() end,
			},
		},
	}
	return { player = player, hp = hp, ab = ab }
end

------------------------------------------------------------------------------
-- addon loader
------------------------------------------------------------------------------

local TOC_FILE = "EllesmereUI_HoTPrediction/EllesmereUI_HoTPrediction.toc"

local function parseTOC(src)
	local files = {}
	for line in src:gmatch("[^\r\n]+") do
		local trimmed = line:gsub("%s+$", "")
		if trimmed ~= "" and not trimmed:match("^##") then
			files[#files + 1] = trimmed
		end
	end
	return files
end

function Mocks.LoadAddon(addonName)
	addonName = addonName or "EllesmereUI_HoTPrediction"
	local root = _G.__HOT_ROOT or "."
	local toc = readSource(root .. "/" .. TOC_FILE)
	if not toc then error("cannot read TOC " .. TOC_FILE) end
	local files = parseTOC(toc)

	local ns = {}
	Mocks._ns = ns
	for _, file in ipairs(files) do
		local path = root .. "/EllesmereUI_HoTPrediction/" .. file
		local src = readSource(path)
		if not src then error("cannot read addon file " .. path) end
		local chunk = assert(load(src, "@" .. path))
		chunk(addonName, ns)
	end
	return ns
end

function Mocks.NewEnv(opts)
	Mocks.Reset()
	if opts and opts.build then
		Mocks.SetBuild(opts.build[1], opts.build[2], opts.build[3], opts.build[4])
	end
	if opts and opts.noCLEU then
		_G.CombatLogGetCurrentEventInfo = nil
	end
	local euf = Mocks.BuildEUF()
	local ns = Mocks.LoadAddon()
	Mocks.Fire("ADDON_LOADED", "EllesmereUI_HoTPrediction")
	Mocks.Fire("PLAYER_LOGIN")
	return { ns = ns, mocks = Mocks, euf = euf, player = euf.player, hp = euf.hp, ab = euf.ab }
end
