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

-- Lua 5.1 exposes a global `unpack`; 5.3+ moved it to table.unpack.
local unpackValues = table.unpack or unpack

local FrameMT = {}
FrameMT.__index = FrameMT
local frameSeq = 0
local regionSeq = 0

local function newTexture(owner, layer)
	regionSeq = regionSeq + 1
	return {
		_owner = owner,
		_layer = layer or "ARTWORK",
		_seq = regionSeq,
		_path = nil,
		_points = {},
		_masks = {},
		_rotation = 0,
		_width = nil, _height = nil, _shown = true,
		SetTexture = function(self, p) self._path = p end,
		GetTexture = function(self) return self._path end,
		SetColorTexture = function(self, ...) self._path = "Interface\\Buttons\\WHITE8X8"; self._color = { ... } end,
		SetVertexColor = function(self, r, g, b, a) self._vertexColor = { r, g, b, a } end,
		GetVertexColor = function(self)
			local c = self._vertexColor or { 1, 1, 1, 1 }
			return c[1], c[2], c[3], c[4]
		end,
		SetDrawLayer = function(self, l) self._layer = l end,
		GetDrawLayer = function(self) return self._layer end,
		SetPoint = function(self, ...) self._points[#self._points + 1] = { ... } end,
		GetPoint = function(self, i)
			local p = self._points[i or 1]
			if not p then return nil end
			return unpackValues(p)
		end,
		ClearAllPoints = function(self) self._points = {} end,
		SetSize = function(self, w, h) self._width, self._height = w, h end,
		SetWidth = function(self, w) self._width = w end,
		SetHeight = function(self, h) self._height = h end,
		GetWidth = function(self) return self._width end,
		GetHeight = function(self) return self._height end,
		SetAllPoints = function(self, ref) self._points = { { "ALL", ref or owner } } end,
		Show = function(self) self._shown = true end,
		Hide = function(self) self._shown = false end,
		SetShown = function(self, v) self._shown = v and true or false end,
		IsShown = function(self) return self._shown end,
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
		-- Faithful to the client: a child frame starts one frame level above its
		-- parent (parentless roots start at 0). This is what makes an opaque
		-- child panel cover its parent's own FontStrings until the panel is
		-- replaced with same-frame BACKGROUND draw-layer textures.
		_level = parent and ((parent._level or 0) + 1) or 0,
		_strata = parent and parent._strata or "MEDIUM",
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
local function newFontString(owner, layer)
	regionSeq = regionSeq + 1
	return {
		_owner = owner,
		_layer = layer or "OVERLAY",
		_seq = regionSeq,
		_text = "",
		_points = {},
		SetText = function(self, t) self._text = tostring(t or "") end,
		GetText = function(self) return self._text end,
		SetFont = function(self, ...) self._font = { ... } end,
		GetFont = function(self)
			local f = self._font
			if f then return f[1], f[2], f[3] end
		end,
		SetTextColor = function(self, r, g, b, a) self._color = { r, g, b, a } end,
		GetTextColor = function(self)
			local c = self._color or { 1, 1, 1, 1 }
			return c[1], c[2], c[3], c[4]
		end,
		SetJustifyH = function(self, j) self._justifyH = j end,
		SetWordWrap = function(self, v) self._wordWrap = v end,
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
		Show = function(self) self._shown = true end,
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
	return unpackValues(p)
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
function FrameMT:CreateTexture(name, layer)
	local t = newTexture(self, layer)
	t._name = name
	self._textures = self._textures or {}
	self._textures[#self._textures + 1] = t
	return t
end
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
function FrameMT:RegisterUnitEvent(e, unit)
	self:RegisterEvent(e)
	self._unitEvents = self._unitEvents or {}
	self._unitEvents[e] = unit
end
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
	local text = newFontString(self, layer)
	text._template = template
	self._fontStrings = self._fontStrings or {}
	self._fontStrings[#self._fontStrings + 1] = text
	return text
end

-- Text on buttons/frames.
function FrameMT:SetText(t)
	self._text = tostring(t or "")
	if self._buttonFontString then self._buttonFontString:SetText(self._text) end
	local cb = self._scripts["OnTextChanged"]
	if cb then cb(self, false) end
end
function FrameMT:GetText() return self._text end
function FrameMT:SetFontString(text) self._buttonFontString = text end
function FrameMT:GetFontString() return self._buttonFontString end

-- EditBox + ScrollFrame surface. Real clients expose these on the widgets; a
-- user "typing" is modelled by SetText/Insert firing OnTextChanged.
function FrameMT:SetMultiLine(v) self._multiLine = v and true or false end
function FrameMT:IsMultiLine() return self._multiLine and true or false end
function FrameMT:SetAutoFocus(v) self._autoFocus = v and true or false end
function FrameMT:SetEnabled(v) self._enabled = v and true or false end
function FrameMT:IsEnabled() return self._enabled ~= false end
function FrameMT:SetFont(path, size, flags) self._font = { path, size, flags } end
function FrameMT:GetFont()
	local f = self._font
	if f then return f[1], f[2], f[3] end
end
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
function FrameMT:RegisterForClicks(...) self._clickButtons = { ... } end
function FrameMT:SetChecked(v) self._checked = v end
function FrameMT:GetChecked() return self._checked end
function FrameMT:SetCheckedTexture(path)
	self._checkedTexture = self._checkedTexture or newTexture(self)
	self._checkedTexture:SetTexture(path)
end
function FrameMT:GetCheckedTexture() return self._checkedTexture end
function FrameMT:SetHighlightTexture(path) self._highlightTexture = path end
function FrameMT:GetCenter() return 100, 100 end
function FrameMT:GetEffectiveScale() return self._scale or 1 end
function FrameMT:SetScale(v) self._scale = v end
function FrameMT:GetScale() return self._scale or 1 end
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
-- deterministic layering model
--
-- Enough of the client's render order to make a hidden label a test failure:
-- frames are ordered by strata, then frame level, then creation order; a
-- FontString shares its owner's frame level but renders above the owner's own
-- BACKGROUND textures. An opaque frame is one that called SetBackdrop (or has
-- a solid background texture); such a frame occludes a region when it stacks
-- above the region's owner and its rectangle overlaps.
------------------------------------------------------------------------------

local STRATA_RANK = {
	BACKGROUND = 0, LOW = 1, MEDIUM = 2, HIGH = 3,
	DIALOG = 4, FULLSCREEN = 5, FULLSCREEN_DIALOG = 6, TOOLTIP = 7,
}
local LAYER_RANK = { BACKGROUND = 0, BORDER = 1, ARTWORK = 2, OVERLAY = 3, HIGHLIGHT = 4 }

function Mocks.LayerRank(layer) return LAYER_RANK[layer] end
function Mocks.StrataRank(strata) return STRATA_RANK[strata] end

-- Resolve a frame's top-left in a shared coordinate space (UIParent origin),
-- following TOPLEFT/TOP/CENTER/BOTTOM anchors used by the options window.
local function absTopLeft(frame, seen)
	seen = seen or {}
	if seen[frame] then return 0, 0 end
	seen[frame] = true
	local p = frame._points and frame._points[1]
	if not p then
		if frame._parent then return absTopLeft(frame._parent, seen) end
		return 0, 0
	end
	local point = p[1]
	local rel = p[2] or frame._parent
	local relPoint = p[3] or point
	local ox, oy = p[4] or 0, p[5] or 0
	if not rel then return ox, oy end
	local rx, ry = absTopLeft(rel, seen)
	local relW, relH = rel._width or 0, rel._height or 0
	if relPoint == "CENTER" then rx, ry = rx + relW / 2, ry - relH / 2
	elseif relPoint == "TOPRIGHT" then rx = rx + relW
	elseif relPoint == "BOTTOMLEFT" or relPoint == "BOTTOM" then ry = ry - relH
	elseif relPoint == "BOTTOMRIGHT" then rx, ry = rx + relW, ry - relH
	elseif relPoint == "RIGHT" then rx, ry = rx + relW, ry - relH / 2 end
	if point == "CENTER" then
		local fw, fh = frame._width or 0, frame._height or 0
		return rx + ox - fw / 2, ry + oy + fh / 2
	elseif point == "TOPRIGHT" then
		local fw = frame._width or 0
		return rx + ox - fw, ry + oy
	elseif point == "TOP" then
		local fw = frame._width or 0
		return rx + ox - fw / 2, ry + oy
	end
	return rx + ox, ry + oy
end

local function frameAbsRect(f)
	local x, y = absTopLeft(f)
	return x, y - (f._height or 0), x + (f._width or 0), y
end

-- A region's top-left is anchored to another frame (its owner by default) and
-- its rectangle extends down and to the right, like the client.
local function regionAbsRect(r)
	local owner = r._owner
	local x, y
	local p = r._points and r._points[1]
	if p then
		local point = p[1]
		local rel = p[2] or owner
		local relPoint = p[3] or point
		local ox, oy = p[4] or 0, p[5] or 0
		local relW = rel and (rel._width or 0) or 0
		local relH = rel and (rel._height or 0) or 0
		local rx, ry = 0, 0
		if rel then rx, ry = absTopLeft(rel) end
		if relPoint == "CENTER" then rx, ry = rx + relW / 2, ry - relH / 2
		elseif relPoint == "TOPRIGHT" then rx = rx + relW
		elseif relPoint == "BOTTOMLEFT" or relPoint == "BOTTOM" then ry = ry - relH
		elseif relPoint == "BOTTOMRIGHT" then rx, ry = rx + relW, ry - relH end
		x, y = rx + ox, ry + oy
	else
		x, y = absTopLeft(owner)
	end
	local w = r._width or 100
	local h = r._height
	if not h and r.GetStringHeight then h = r:GetStringHeight() end
	return x, y - (h or 12), x + w, y
end

-- Public geometry helpers for layout tests: axis-aligned rects with top > bottom.
function Mocks.FrameRect(f)
	local l, b, r, t = frameAbsRect(f)
	return { left = l, bottom = b, right = r, top = t }
end

function Mocks.RegionRect(region)
	local l, b, r, t = regionAbsRect(region)
	return { left = l, bottom = b, right = r, top = t }
end

function Mocks.RectsOverlap(a, b)
	if not a or not b then return false end
	return a.left < b.right and b.left < a.right and a.bottom < b.top and b.bottom < a.top
end

local function effectivelyShown(f)
	while f do
		if f._shown == false then return false end
		f = f._parent
	end
	return true
end

local function isAncestor(anc, f)
	local p = f and f._parent
	while p do
		if p == anc then return true end
		p = p._parent
	end
	return false
end

-- True when a region would actually be drawn: no shown opaque frame that stacks
-- above the region's owner covers the same rectangle.
function Mocks.IsRegionVisible(region)
	if not region or region._shown == false then return false end
	local owner = region._owner
	if not owner or not effectivelyShown(owner) then return false end
	local l, b, rr, t = regionAbsRect(region)
	local osr = STRATA_RANK[owner._strata] or STRATA_RANK.MEDIUM
	for _, f in ipairs(Mocks.frames) do
		if f ~= owner and f._backdrop and f._backdrop.bgFile
			and (not f._backdropColor or (f._backdropColor[4] or 1) > 0)
			and effectivelyShown(f) and not isAncestor(f, owner) then
			local sr = STRATA_RANK[f._strata] or STRATA_RANK.MEDIUM
			local above
			if sr ~= osr then above = sr > osr
			elseif (f._level or 0) ~= (owner._level or 0) then above = (f._level or 0) > (owner._level or 0)
			else above = (f._seq or 0) > (owner._seq or 0) end
			if above then
				local fl, fb, fr, ft = frameAbsRect(f)
				if fl < rr and l < fr and fb < t and b < ft then return false end
			end
		end
	end
	return true
end

function Mocks.FindFontString(frame, fragment)
	for _, l in ipairs(frame._fontStrings or {}) do
		if l:GetText():find(fragment, 1, true) then return l end
	end
	return nil
end

function Mocks.FindTexture(frame, layer)
	for _, t in ipairs(frame._textures or {}) do
		if not layer or t._layer == layer then return t end
	end
	return nil
end

-- Opaque child frames (those with a backdrop) are the ones that hide a
-- parent's own FontStrings.
function Mocks.OpaqueChildFrames(frame)
	local out = {}
	for _, f in ipairs(Mocks.frames or {}) do
		if f._parent == frame and f._backdrop ~= nil then out[#out + 1] = f end
	end
	return out
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
	Mocks.healingPower = 0
	Mocks.descriptions = {}
	Mocks.channel = nil
	Mocks.rage = 0
	-- Weapon training map-adapter state (only used by spec_weapon_training).
	Mocks.waypoint = nil
	Mocks.superTracked = nil

	_G.EllesmereUI_HoTPredictionDB = nil

	_G.UIParent = newFrame("Frame", "UIParent", nil)
	_G.UIParent:SetSize(1920, 1080)
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
	_G.UnitCanAttack = nil
	_G.IsAutoRepeatAction = nil
	_G.GetSpellInfo = nil
	_G.UnitIsDeadOrGhost = nil
	_G.UnitHealth = function() return Mocks.health end
	_G.UnitHealthMax = function() return Mocks.maxHealth end
	_G.UnitPower = function(_, powerType)
		Mocks.powerCalls = Mocks.powerCalls + 1
		return powerType == 1 and Mocks.rage or 100000
	end
	_G.UnitChannelInfo = function()
		if not Mocks.channel then return nil end
		local c = Mocks.channel
		return "channel", nil, nil, c.start, c.finish, false, false, c.id
	end
	_G.GetSpellBonusHealing = function() return Mocks.healingPower end
	_G.GetLocale = function() return "enUS" end
	_G.C_Spell = { GetSpellDescription = function(id) return Mocks.descriptions[id] end }
	_G.C_TooltipInfo = nil
	-- Optional map / waypoint / tracking APIs. WeaponsTraining degrades gracefully
	-- when these are absent; the spec installs its own mocks per case.
	_G.C_Map = nil
	_G.UiMapPoint = nil
	_G.C_SuperTrack = nil
	_G.TomTom = nil
	_G.ToggleWorldMap = nil
	_G.OpenWorldMap = nil
	_G.WorldMapFrame = nil
	_G.C_AddOns = nil
	_G.Enum = nil
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
	_G.C_Timer = { NewTicker = function(interval, fn)
		local ticker = { interval = interval, fn = fn, cancelled = false }
		function ticker:Cancel() self.cancelled = true end
		Mocks.tickers[#Mocks.tickers + 1] = ticker
		return ticker
	end }
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
		return unpackValues(t, 1, n)
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

local TOC_FILE = "DoHelper/DoHelper.toc"

local function parseTOC(src)
	local files = {}
	for line in src:gmatch("[^\r\n]+") do
		local trimmed = line:gsub("%s+$", "")
		-- Only Lua sources are loaded by this interpreter. XML manifests
		-- (Bindings.xml) are declared in the TOC for the game client only.
		if trimmed ~= "" and not trimmed:match("^##") and not trimmed:match("%.xml$") then
			files[#files + 1] = trimmed
		end
	end
	return files
end

function Mocks.LoadAddon(addonName)
	addonName = addonName or "DoHelper"
	local root = _G.__HOT_ROOT or "."
	local toc = readSource(root .. "/" .. TOC_FILE)
	if not toc then error("cannot read TOC " .. TOC_FILE) end
	local files = parseTOC(toc)

	local ns = {}
	Mocks._ns = ns
	for _, file in ipairs(files) do
		local path = root .. "/DoHelper/" .. file
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
	if opts and opts.disabled then _G.EllesmereUI_HoTPredictionDB = { enabled = false } end
	if opts and opts.noTimer then _G.C_Timer = nil end
	local euf = Mocks.BuildEUF()
	local ns = Mocks.LoadAddon()
	Mocks.Fire("ADDON_LOADED", "DoHelper")
	Mocks.Fire("PLAYER_LOGIN")
	return { ns = ns, mocks = Mocks, euf = euf, player = euf.player, hp = euf.hp, ab = euf.ab }
end
