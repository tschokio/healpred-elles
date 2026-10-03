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
		SetTexture = function(self, p) self._path = p end,
		GetTexture = function(self) return self._path end,
		SetPoint = function(self, ...) self._points[#self._points + 1] = { ... } end,
		ClearAllPoints = function(self) self._points = {} end,
	}
end

local function newFrame(frameType, name, parent)
	frameSeq = frameSeq + 1
	local f = setmetatable({
		_type = frameType or "Frame",
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
		_seq = frameSeq,
	}, FrameMT)
	f._sbTexture = newTexture(f)
	if parent and parent._children then
		parent._children[#parent._children + 1] = f
	end
	Mocks.frames[#Mocks.frames + 1] = f
	return f
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
function FrameMT:Hide() self._shown = false end
function FrameMT:SetShown(v) self._shown = v and true or false end
function FrameMT:IsShown() return self._shown end
function FrameMT:GetParent() return self._parent end
function FrameMT:SetParent(p) self._parent = p end
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
function FrameMT:SetMinMaxValues(a, b) self._min, self._max = a, b end
function FrameMT:GetMinMaxValues() return self._min, self._max end
function FrameMT:SetValue(v) self._value = v end
function FrameMT:GetValue() return self._value end
function FrameMT:SetStatusBarColor(r, g, b) self._color = { r, g, b } end
function FrameMT:GetStatusBarColor() return self._color[1], self._color[2], self._color[3] end
function FrameMT:SetAlpha(a) self._alpha = a end
function FrameMT:GetAlpha() return self._alpha end
function FrameMT:SetOrientation(o) self._orientation = o end
function FrameMT:GetOrientation() return self._orientation end
function FrameMT:SetReverseFill(v) self._reverse = v and true or false end
function FrameMT:IsReverseFill() return self._reverse end
function FrameMT:GetReverseFill() return self._reverse end
function FrameMT:RegisterEvent(e) self._events[e] = true end
function FrameMT:UnregisterEvent(e) self._events[e] = nil end
function FrameMT:SetScript(name, fn) self._scripts[name] = fn end
function FrameMT:GetScript(name) return self._scripts[name] end
function FrameMT:HookScript(name, fn)
	local orig = self._scripts[name]
	self._scripts[name] = function(...) if orig then orig(...) end return fn(...) end
end

------------------------------------------------------------------------------
-- global mock environment
------------------------------------------------------------------------------

function Mocks.Reset()
	Mocks.frames = {}
	Mocks.chat = {}
	Mocks.hooks = {}
	Mocks.tickers = {}
	Mocks.now = 100
	Mocks.playerGUID = "Player-0001"
	Mocks.health = 5000
	Mocks.maxHealth = 5000
	Mocks.healAbsorb = 0
	Mocks.inCombat = false
	Mocks.auras = {}
	Mocks.cleu = nil
	Mocks.powerCalls = 0

	_G.EllesmereUI_HoTPredictionDB = nil

	_G.UIParent = newFrame("Frame", "UIParent", nil)
	_G.DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) Mocks.chat[#Mocks.chat + 1] = msg end }
	_G.SlashCmdList = {}

	_G.CreateFrame = function(t, n, p) return newFrame(t, n, p) end
	_G.GetTime = function() return Mocks.now end
	_G.InCombatLockdown = function() return Mocks.inCombat end
	_G.UnitGUID = function() return Mocks.playerGUID end
	_G.UnitExists = function() return true end
	_G.UnitHealth = function() return Mocks.health end
	_G.UnitHealthMax = function() return Mocks.maxHealth end
	_G.UnitPower = function() Mocks.powerCalls = Mocks.powerCalls + 1; return 100000 end
	_G.UnitGetTotalHealAbsorbs = function() return Mocks.healAbsorb end
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
			if not Mocks.auras or not Mocks.auras[i] then return nil end
			return Mocks.auras[i]
		end,
	}
	_G.CombatLogGetCurrentEventInfo = function()
		if not Mocks.cleu then return nil end
		return unpack(Mocks.cleu)
	end
	_G.EllesmereUI = nil
end

function Mocks.SetNow(t) Mocks.now = t end
function Mocks.SetAuras(list) Mocks.auras = list or {} end
function Mocks.SetCLEU(tuple) Mocks.cleu = tuple end
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
	predOther:SetStatusBarColor(40 / 255, 170 / 255, 40 / 255)
	predOther:Hide()

	local ab = {
		_predOn = true,
		_isVert = false,
		_isReversed = false,
		_missClip = missClip,
		_predMy = predMy,
		_predOther = predOther,
		_predCalc = { GetIncomingHeals = function() return nil, 0, 0 end },
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

function Mocks.NewEnv()
	Mocks.Reset()
	local euf = Mocks.BuildEUF()
	local ns = Mocks.LoadAddon()
	Mocks.Fire("ADDON_LOADED", "EllesmereUI_HoTPrediction")
	Mocks.Fire("PLAYER_LOGIN")
	return { ns = ns, mocks = Mocks, euf = euf, player = euf.player, hp = euf.hp, ab = euf.ab }
end
