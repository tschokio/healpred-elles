-- EllesmereUI_HoTPrediction / Overlay.lua
-- Owns the single overlay bar that draws our conservative remainder segment at
-- the leading edge of the native incoming-heal chain. It never modifies native
-- frames, textures or functions: it only reads them, creates its own StatusBar
-- with its own texture, and secure-hooks native callbacks read-only.
--
-- Structural work (create/reparent/hooks) is deferred out of combat. Native
-- hook callbacks only queue deferred work; they never run Resolve synchronously
-- inside a native protected stack.

local addonName, ns = ...
local overlay = {}
ns.overlay = overlay

local TICK_INTERVAL = 0.15
local IDLE_PROBE_INTERVAL = 1.0 -- cheap structure/health probe while idle

overlay.state = {
	frame = nil,
	ab = nil,
	player = nil,
	hp = nil,
	parent = nil,
	module = nil,
	chain = nil,
	pending = false,
	hooksInstalled = false,
	structureDirty = true,
	paintRequested = true,
	styleDirty = true,
	active = false,
	lastIdleProbe = -1,
	vertical = false,
	reversed = false,
	masks = {},
	maskCount = 0,
	lastDebugKey = nil,
	lastTickError = nil,
}

local function safeCall(fn, ...)
	if type(fn) ~= "function" then return false end
	local ok, a, b, c = pcall(fn, ...)
	if not ok then return false end
	return a, b, c
end

local function getStatusBarTexture(f)
	if not f or not f.GetStatusBarTexture then return nil end
	local ok, tex = pcall(f.GetStatusBarTexture, f)
	if ok then return tex end
	return nil
end

function overlay.IsCombat()
	return ns.api and ns.api.InCombat and ns.api.InCombat()
end

------------------------------------------------------------------------------
-- lifecycle / deferral flags (safe to call from hooks or events)
------------------------------------------------------------------------------

function overlay.InvalidateStructure()
	overlay.state.structureDirty = true
	overlay.state.paintRequested = true
end

function overlay.RequestPaint()
	overlay.state.paintRequested = true
end

function overlay.RequestStyle()
	overlay.state.styleDirty = true
	overlay.state.paintRequested = true
end

------------------------------------------------------------------------------
-- frame lifecycle
------------------------------------------------------------------------------

-- Never creates the overlay for the first time while in combat.
function overlay.EnsureFrame()
	local f = overlay.state.frame
	if f then return f end
	if overlay.IsCombat() then return nil end
	if type(CreateFrame) ~= "function" then return nil end
	local parent = (UIParent and UIParent) or nil
	f = CreateFrame("StatusBar", "EllesmereUI_HoTPredictionOverlay", parent)
	if f.SetMinMaxValues then f:SetMinMaxValues(0, 1) end
	if f.SetValue then f:SetValue(0) end
	-- Our OWN texture; the native file is copied as a path, never reused as an
	-- object (so masks/rotation are applied to our texture, not the vendor one).
	if f.SetStatusBarTexture then f:SetStatusBarTexture("Interface\\Buttons\\WHITE8X8") end
	if f.Hide then f:Hide() end
	overlay.state.frame = f
	return f
end

local function anchorTo(refBar, hpBar, ours, vertical, reversed)
	if not refBar or not ours then return false end
	local ref = refBar
	if refBar.GetStatusBarTexture then
		local tex = safeCall(refBar.GetStatusBarTexture, refBar)
		if tex then ref = tex end
	end
	if not ours.ClearAllPoints or not ours.SetPoint then return false end
	ours:ClearAllPoints()
	if not vertical and not reversed then
		ours:SetPoint("LEFT", ref, "RIGHT", 0, 0)
	elseif not vertical and reversed then
		ours:SetPoint("RIGHT", ref, "LEFT", 0, 0)
	elseif vertical and not reversed then
		ours:SetPoint("BOTTOM", ref, "TOP", 0, 0)
	else
		ours:SetPoint("TOP", ref, "BOTTOM", 0, 0)
	end
	if ours.SetOrientation then ours:SetOrientation(vertical and "VERTICAL" or "HORIZONTAL") end
	if ours.SetReverseFill then ours:SetReverseFill(reversed) end
	if hpBar and ours.SetSize and hpBar.GetWidth and hpBar.GetHeight then
		ours:SetSize(hpBar:GetWidth(), hpBar:GetHeight())
	end
	local above = nil
	if refBar.GetFrameLevel then above = ns.toNumber(safeCall(refBar.GetFrameLevel, refBar)) end
	if above and ours.SetFrameLevel then ours:SetFrameLevel(above + 1) end
	return true
end

-- Pick orientation/reverse from the native prediction bar, else the health bar.
local function resolveAxes(ab, hp)
	local info = ns.api.GetBarInfo(ab and ab._predMy)
	if info and info.orientation then
		return info.orientation == "VERTICAL", info.reversed and true or false
	end
	info = ns.api.GetBarInfo(hp)
	return (info and info.orientation == "VERTICAL") or false, (info and info.reversed) and true or false
end

-- Bounds masks: reproduce the native clipping on OUR fill, never touch vendor
-- textures. Old masks we added are removed on change.
local function copyMasks(ab, hp, f)
	local ourTex = getStatusBarTexture(f)
	if not ourTex or not ourTex.AddMaskTexture then
		overlay.state.masks = {}
		overlay.state.maskCount = 0
		return
	end
	local desired = {}
	if ab and ab._absorbMask then desired[#desired + 1] = ab._absorbMask end
	local blizzMask = (hp and hp._blizzMask) or (ab and ab._blizzMask)
	if ab and ab._blizzMaskOn and blizzMask then desired[#desired + 1] = blizzMask end

	local old = overlay.state.masks or {}
	local next = {}
	for i = 1, #desired do
		local m = desired[i]
		next[m] = true
		if not old[m] then
			pcall(ourTex.AddMaskTexture, ourTex, m)
		end
	end
	for m in pairs(old) do
		if not next[m] then
			if ourTex.RemoveMaskTexture then pcall(ourTex.RemoveMaskTexture, ourTex, m) end
		end
	end
	overlay.state.masks = next
	overlay.state.maskCount = #desired
end

local function applyStyle(ab, player, hp, f)
	local info = ns.api.GetBarInfo(ab and ab._predMy)
	-- Copy the texture PATH (string) so we keep our own texture object.
	if info and info.texture and f.SetStatusBarTexture then
		pcall(f.SetStatusBarTexture, f, info.texture)
	end

	local r, g, b, baseAlpha
	if ns.db.shareNativeStyle and info and info.color then
		r, g, b = info.color[1], info.color[2], info.color[3]
		baseAlpha = info.colorAlpha or info.alpha or 1
	else
		local c = ns.db.overlayColor or { 1, 0.82, 0 }
		r, g, b = c[1], c[2], c[3]
		baseAlpha = 1
	end
	if f.SetStatusBarColor then pcall(f.SetStatusBarColor, f, r, g, b) end
	-- Subtly distinguish the HoT segment from native direct healing via alpha.
	local a = (ns.toNumber(ns.db.alpha) or 0.6) * (ns.toNumber(baseAlpha) or 1)
	if f.SetAlpha then f:SetAlpha(a) end

	if info and info.level and f.SetFrameLevel then pcall(f.SetFrameLevel, f, info.level + 1) end
	if player and player.GetFrameStrata and f.SetFrameStrata then
		local strata = safeCall(player.GetFrameStrata, player)
		if strata then pcall(f.SetFrameStrata, f, strata) end
	end

	-- Texture rotation (guarded; not present in all clients).
	local ourTex = getStatusBarTexture(f)
	local natTex = info and info.textureObject
	if ourTex and ourTex.SetRotation and natTex and natTex.GetRotation then
		local rot = safeCall(natTex.GetRotation, natTex)
		if rot ~= nil then pcall(ourTex.SetRotation, ourTex, rot) end
	end

	copyMasks(ab, hp, f)
	overlay.state.styleDirty = false
end

-- Re-apply the native-derived style to our existing frame (hooks queue this via
-- styleDirty rather than doing it synchronously).
function overlay.ApplyStyle()
	local f = overlay.state.frame
	local ab = overlay.state.ab
	if f and ab then
		applyStyle(ab, overlay.state.player, overlay.state.hp, f)
	end
end

-- Structural resolve: find the native module, hook it once per module, and
-- re-parent/re-anchor our own frame. Deferred entirely while in combat when the
-- structure is missing or has been replaced.
function overlay.Resolve()
	local ab, player, hp = ns.api.GetAbsorbFrame()
	if not ab or not player or not hp then
		overlay.HideHard("native prediction structure missing")
		if overlay.IsCombat() then overlay.state.pending = true end
		return false
	end
	-- The native chain is REQUIRED: no unbounded fallback parent.
	if not ab._missClip or not ab._predMy or not ab._predOther then
		overlay.HideHard("native prediction subframes missing")
		if overlay.IsCombat() then overlay.state.pending = true end
		return false
	end

	-- Vehicle / unknown-unit: never paint.
	local unit, uerr = ns.api.GetFrameUnit(player)
	if unit ~= "player" then
		overlay.HideHard("frame unit " .. tostring(unit) .. " (" .. tostring(uerr) .. ")")
		return false
	end

	local f = overlay.state.frame
	local structuralChange = (overlay.state.ab ~= ab) or (overlay.state.player ~= player)
		or (overlay.state.hp ~= hp) or (f == nil)

	if overlay.IsCombat() then
		if structuralChange then
			-- Replacing/creating the vendor chain mid-combat is unsafe: hide and
			-- wait for regen rather than painting a stale frame.
			overlay.state.pending = true
			overlay.Hide("structure pending; applies after combat")
			return false
		end
		-- Same structure: safe to update our own size/orientation/anchors.
	else
		overlay.state.pending = false
	end

	overlay.state.ab, overlay.state.player, overlay.state.hp = ab, player, hp

	if not f then
		f = overlay.EnsureFrame()
		if not f then
			overlay.state.pending = true
			return false
		end
	end

	local module = ns.api.GetEUF()
	if not overlay.IsCombat() then
		if overlay.state.parent ~= ab._missClip then
			pcall(f.SetParent, f, ab._missClip)
			overlay.state.parent = ab._missClip
		end
	end
	overlay.InstallHooks(module)

	local vertical, reversed = resolveAxes(ab, hp)
	overlay.state.vertical = vertical
	overlay.state.reversed = reversed
	local chain = ns.api.GetNativeChain(ab)
	overlay.state.chain = chain
	-- Chain AFTER the last shown native bar (native shows both when both exist).
	local ref = chain[#chain] or ab._predMy or hp
	anchorTo(ref, hp, f, vertical, reversed)

	applyStyle(ab, player, hp, f)
	overlay.state.structureDirty = false
	overlay.state.module = module
	return true
end

-- Secure hooks: only queue deferred own work. Never Resolve synchronously.
function overlay.InstallHooks(module)
	if not module then return end
	if overlay.state.hooksInstalled and overlay.state.module == module then return end
	if type(hooksecurefunc) ~= "function" then return end
	local function queued()
		overlay.RequestPaint()
		overlay.state.styleDirty = true
	end
	for _, name in ipairs({ "UF_HealPredApply", "UF_AnchorHealPred", "UF_HealPredLayout", "UF_PaintHealPred" }) do
		if type(module[name]) == "function" then
			local ok = pcall(hooksecurefunc, module, name, queued)
			if ok then ns.debug("hook installed: " .. name) end
		end
	end
	overlay.state.hooksInstalled = true
	overlay.state.module = module
end

-- Cheap identity probe: has the module/frame/hp/clip/native fill been replaced?
function overlay.StructureChanged()
	local ab, player, hp = ns.api.GetAbsorbFrame()
	if not ab or not player or not hp then return true end
	if overlay.state.ab ~= ab or overlay.state.player ~= player or overlay.state.hp ~= hp then return true end
	if not ab._missClip or not ab._predMy or not ab._predOther then return true end
	if overlay.state.parent ~= ab._missClip then return true end
	return false
end

function overlay.ApplyPending()
	if overlay.state.pending then
		overlay.InvalidateStructure()
		overlay.Resolve()
	end
end

------------------------------------------------------------------------------
-- rendering
------------------------------------------------------------------------------

function overlay.Hide(reason)
	local f = overlay.state.frame
	if f and f.Hide then f:Hide() end
	if reason then ns.session.lastSuppress = reason end
end

-- Structural failure: drop handles and suppress rather than paint stale ones.
function overlay.HideHard(reason)
	local f = overlay.state.frame
	if f and f.Hide then f:Hide() end
	overlay.state.ab = nil
	overlay.state.parent = nil
	overlay.state.masks = {}
	overlay.state.maskCount = 0
	if reason then ns.session.lastSuppress = reason end
end

local function resolveMax(ab)
	if ab and ab._predMy and ab._predMy.GetMinMaxValues then
		local ok, _min, max = pcall(ab._predMy.GetMinMaxValues, ab._predMy)
		if ok and ns.toNumber(max) and max > 0 then return max end
	end
	local health = ns.api.GetHealthNumbers and ns.api.GetHealthNumbers()
	if health and health.max and health.max > 0 then return health.max end
	return nil
end

function overlay.RenderValue(value, reason)
	if not ns.db or not ns.db.enabled then
		overlay.Hide("addon disabled")
		return
	end
	local f = overlay.state.frame
	if not f then
		-- Do NOT create the overlay first time in combat.
		if overlay.IsCombat() then
			overlay.state.pending = true
			overlay.Hide("overlay not created; applies after combat")
			return
		end
		overlay.InvalidateStructure()
		overlay.Resolve()
		f = overlay.state.frame
		if not f then
			overlay.Hide("no native prediction frame")
			return
		end
	end
	local ab = overlay.state.ab
	if not ab then
		overlay.Hide("no native prediction frame")
		return
	end
	if not value or value <= 0 then
		overlay.Hide(reason or "nothing to append")
		return
	end
	local max = resolveMax(ab)
	if not max then
		overlay.Hide("no readable max for overlay scaling")
		return
	end
	if f.SetMinMaxValues then f:SetMinMaxValues(0, max) end
	if f.SetValue then f:SetValue(value) end
	if f.Show then f:Show() end
end

------------------------------------------------------------------------------
-- periodic evaluation
------------------------------------------------------------------------------

local function debugChange(key, fmt, ...)
	if not (ns.db and ns.db.debug) then return end
	if key == overlay.state.lastDebugKey then return end
	overlay.state.lastDebugKey = key
	ns.debug(string.format(fmt, ...))
end

function overlay.Tick(force)
	if not ns.db or not ns.db.enabled then
		overlay.Hide("addon disabled")
		return
	end
	local now = ns.now()

	-- Cheap identity probe; if the vendor structure changed, resolve (deferred
	-- in combat) rather than painting stale handles.
	if overlay.StructureChanged() then
		overlay.state.structureDirty = true
	end

	local fake = ns.session.fake
	local needPaint = force or overlay.state.paintRequested or overlay.state.structureDirty
		or fake ~= nil or overlay.state.active

	if not needPaint then
		-- Idle: throttle. A ~1s cheap probe keeps attachment current without a
		-- full rescan or any aura API calls.
		if now - (overlay.state.lastIdleProbe or -1) >= IDLE_PROBE_INTERVAL then
			overlay.state.lastIdleProbe = now
			if overlay.state.structureDirty or not overlay.state.ab then
				overlay.Resolve()
			end
		end
		return
	end

	overlay.state.paintRequested = false

	if overlay.state.structureDirty then
		local ok = overlay.Resolve()
		if not ok and overlay.state.pending then
			return
		end
	end
	if not overlay.state.ab then
		overlay.Hide("no native prediction frame")
		return
	end

	-- Native apply/layout/mask hooks only queue this deferred style refresh.
	if overlay.state.styleDirty then
		overlay.ApplyStyle()
	end

	if fake then
		local res = ns.model.Evaluate(now, { fake = true, ab = overlay.state.ab })
		ns.session.lastStatus = res
		if res.suppressed or not fake.value or fake.value <= 0 then
			overlay.state.active = false
			overlay.Hide(res.reason or "fake test")
		else
			overlay.state.active = true
			overlay.RenderValue(fake.value, "fake test")
		end
		debugChange("fake|" .. tostring(fake.value) .. "|" .. tostring(res.suppressed),
			"fake render value=%s native=%s hot=%s reason=%s", tostring(fake.value),
			tostring(res.native and res.native.total), tostring(res.hotEstimate), tostring(res.reason))
		return
	end

	local res = ns.model.Evaluate(now, { ab = overlay.state.ab })
	ns.session.lastStatus = res
	overlay.state.active = (res.hotEstimate and res.hotEstimate > 0) and true or false
	if res.added and res.added > 0 then
		overlay.RenderValue(res.added, res.reason)
	else
		overlay.Hide(res.reason)
	end
	debugChange(tostring(res.added) .. "|" .. tostring(res.reason) .. "|" .. tostring(res.hotEstimate),
		"tick hot=%s native=%s added=%s reason=%s", tostring(res.hotEstimate),
		tostring(res.native and res.native.total), tostring(res.added), tostring(res.reason))
end

function overlay.Setup()
	overlay.InvalidateStructure()
	overlay.RequestPaint()
	local function safeTick()
		local ok, err = pcall(overlay.Tick)
		if not ok then
			-- Report one actionable error, never a repeated Lua exception stream.
			if overlay.state.lastTickError ~= err then
				overlay.state.lastTickError = err
				ns.print("tick error (protected): " .. tostring(err))
			end
		end
	end
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(TICK_INTERVAL, safeTick)
	elseif type(CreateFrame) == "function" then
		local t = CreateFrame("Frame")
		local elapsed = 0
		t:SetScript("OnUpdate", function(_, dt)
			elapsed = elapsed + (dt or 0)
			if elapsed >= TICK_INTERVAL then
				elapsed = 0
				safeTick()
			end
		end)
	end
end
