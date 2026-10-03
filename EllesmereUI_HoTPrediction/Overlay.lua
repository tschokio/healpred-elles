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
	counts = { ticks = 0, model = 0, resolve = 0, render = 0 },
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
	if not ns.db or not ns.db.enabled then return end
	overlay.state.paintRequested = true
end

function overlay.RequestStyle()
	overlay.state.styleDirty = true
	overlay.state.paintRequested = true
end

function overlay.RequestFormRefresh()
	if not ns.db or not ns.db.enabled then return end
	ns.api.InvalidateAuraCache()
	overlay.InvalidateStructure()
	-- Coalesce the two form notifications. No additional timer is created:
	-- the existing ticker performs two bounded retries, then returns to idle.
	overlay.state.nextFormRefresh = ns.now() + 0.25
	overlay.state.finalFormRefresh = ns.now() + 0.75
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
	if overlay.state.maskTexture ~= ourTex then
		local previous = overlay.state.maskTexture
		if previous and previous.RemoveMaskTexture then
			for mask in pairs(old) do pcall(previous.RemoveMaskTexture, previous, mask) end
		end
		old = {}
		overlay.state.maskTexture = ourTex
	end
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
	if info and info.texture and f.SetStatusBarTexture and overlay.state.texturePath ~= info.texture then
		pcall(f.SetStatusBarTexture, f, info.texture)
		overlay.state.texturePath = info.texture
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
	if not ns.db or not ns.db.enabled then return false end
	overlay.state.counts.resolve = overlay.state.counts.resolve + 1
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
		or (overlay.state.hp ~= hp) or (overlay.state.parent ~= ab._missClip) or (f == nil)

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
	overlay.state.frameUnit = unit
	overlay.state.predOn = ab._predOn

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
	overlay.state.nativeMy = ab._predMy
	overlay.state.nativeOther = ab._predOther
	overlay.state.nativeFill = getStatusBarTexture(ref)

	applyStyle(ab, player, hp, f)
	overlay.state.structureDirty = false
	overlay.state.module = module
	return true
end

-- Native callbacks are shared across units (player, target, focus, ...). Only
-- the CURRENT player frame / absorb module may force a full structural resolve;
-- a target/focus callback must be ignored instead of causing a player rescan.
-- When the client (or a test) supplies no identifying argument we stay
-- conservative and allow the deferred work.
function overlay.HookArgIsCurrent(...)
	local n = select("#", ...)
	if n == 0 then return true end
	local curAb, curPlayer, curHp
	if ns.api and ns.api.GetAbsorbFrame then
		curAb, curPlayer, curHp = ns.api.GetAbsorbFrame()
	end
	local module = overlay.state.module
	local sawIdentity = false
	for i = 1, n do
		local v = select(i, ...)
		-- A method-self module argument identifies the engine, not the unit, so
		-- it must never make a target/focus call look like the player.
		if v ~= module then
			local t = type(v)
			if t == "table" then
				sawIdentity = true
				if v == overlay.state.ab or v == overlay.state.player or v == overlay.state.hp
					or v == overlay.state.parent or v == curAb or v == curPlayer or v == curHp then
					return true
				end
			elseif t == "string" then
				sawIdentity = true
				if v == "player" then return true end
			end
		end
	end
	return not sawIdentity
end

-- Secure hooks: only queue deferred own work. Never Resolve synchronously.
function overlay.InstallHooks(module)
	if not module then return end
	if overlay.IsCombat() then return end
	if overlay.state.hooksInstalled and overlay.state.module == module then return end
	if type(hooksecurefunc) ~= "function" then return end
	for _, name in ipairs({ "UF_HealPredApply", "UF_AnchorHealPred", "UF_HealPredLayout", "UF_HealPredMasks", "UF_PaintHealPred" }) do
		if type(module[name]) == "function" then
			local paintOnly = name == "UF_PaintHealPred"
			local function queued(...)
				if not ns.db or not ns.db.enabled then return end
				if not overlay.HookArgIsCurrent(...) then return end
				if paintOnly then
					-- The native painter only ever needs a repaint of our bar.
					overlay.RequestPaint()
				else
					overlay.InvalidateStructure()
				end
			end
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
	if overlay.state.module ~= ns.api.GetEUF() then return true end
	if ns.api.GetFrameUnit(player) ~= overlay.state.frameUnit then return true end
	if ab._predOn ~= overlay.state.predOn then return true end
	if overlay.state.nativeMy ~= ab._predMy or overlay.state.nativeOther ~= ab._predOther then return true end
	if overlay.state.nativeFill ~= getStatusBarTexture(ns.api.GetNativeTail(ab)) then return true end
	return false
end

function overlay.ApplyPending()
	if not ns.db or not ns.db.enabled then return end
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
	if f and f.Hide and (not f.IsShown or f:IsShown()) then f:Hide() end
	if reason then
		ns.session.lastSuppress = reason
		ns.session.lastRenderReason = reason
	end
end

-- Structural failure: drop handles and suppress rather than paint stale ones.
function overlay.HideHard(reason)
	local f = overlay.state.frame
	if f and f.Hide then f:Hide() end
	overlay.state.ab = nil
	overlay.state.parent = nil
	-- Retain mask ownership so the next attachment can remove old masks.
	if reason then
		ns.session.lastSuppress = reason
		ns.session.lastRenderReason = reason
	end
end

-----------------------------------------------------------------------------
-- range resolution / secret-safe setter
--
-- A secret max is OPAQUE. We must never compare, calculate, stringify, index or
-- branch on it. The only allowed use is to hand it verbatim to an engine-driven
-- UI setter (exactly what native EllesmereUI does with `UnitHealthMax(unit)`).
-- Our bar's own value stays a plain public number from the model.
-----------------------------------------------------------------------------

-- PUBLIC label for a range value we already know is either a plain number or a
-- secret. Never reads the value itself.
local function rangeVisibility(v)
	if ns.isSecret(v) then return "restricted" end
	return "public"
end

-- Read the native prediction range through its protected getter. The secret test
-- happens BEFORE any numeric check. Returns raw, usable, reason:
--   usable = true  -> raw is a finite >0 number OR a secret value
--   usable = false -> raw is nil; reason is a short PUBLIC explanation
local function readNativeRange(ab)
	if not (ab and ab._predMy and ab._predMy.GetMinMaxValues) then
		return nil, false, "native range getter unavailable"
	end
	local ok, _min, max = pcall(ab._predMy.GetMinMaxValues, ab._predMy)
	if not ok then
		return nil, false, "native range getter error"
	end
	if ns.isSecret(max) then
		return max, true, nil
	end
	local n = ns.toNumber(max)
	if n and n > 0 then return n, true, nil end
	return nil, false, "native range nonpositive/unusable"
end

-- Fallback range: UnitHealthMax ONLY. Deliberately independent of current
-- health (we never call GetHealthNumbers here), so a secret current health can
-- never block a perfectly usable max. Same return contract as above.
local function readUnitHealthMax()
	local f = UnitHealthMax
	if type(f) ~= "function" then
		return nil, false, "UnitHealthMax unavailable"
	end
	local ok, raw = pcall(f, "player")
	if not ok then
		return nil, false, "UnitHealthMax error"
	end
	if ns.isSecret(raw) then
		return raw, true, nil
	end
	local n = ns.toNumber(raw)
	if n and n > 0 then return n, true, nil end
	return nil, false, "UnitHealthMax nonpositive/unusable"
end

-- Resolve and apply the range to OUR OWN bar. A secret value is passed verbatim
-- to the engine-driven setter (pcall; boolean result only). A public value must
-- be a finite >0 number. Returns ok(boolean), diag(PUBLIC string). The diag
-- records the source and whether it was restricted, never the value.
function overlay.ApplyRange(bar, ab)
	if not bar or not bar.SetMinMaxValues then
		return false, "overlay range setter unavailable"
	end

	-- 1. Prefer the native prediction range (exactly what native uses).
	local raw, usable = readNativeRange(ab)
	local nativeWhy
	if usable then
		local applied = pcall(bar.SetMinMaxValues, bar, 0, raw)
		if applied then
			return true, "native-range (" .. rangeVisibility(raw) .. ")"
		end
		nativeWhy = "native-range setter refused"
	end

	-- 2. Fallback is tried INDEPENDENTLY of the native attempt.
	local raw2, usable2, why2 = readUnitHealthMax()
	if usable2 then
		local applied2 = pcall(bar.SetMinMaxValues, bar, 0, raw2)
		if applied2 then
			return true, "UnitHealthMax (" .. rangeVisibility(raw2) .. ")"
		end
		return false, "UnitHealthMax (" .. rangeVisibility(raw2) .. "); setter refused"
	end

	if nativeWhy then
		return false, nativeWhy .. "; " .. tostring(why2 or "no fallback range")
	end
	return false, "no readable range (" .. tostring(why2 or "native range unavailable") .. ")"
end

-- Render our bar. Returns ok(boolean), reason(PUBLIC string). `value` must be a
-- plain finite positive number produced by the model; it is never a secret. The
-- range may be restricted and is consumed by ApplyRange without inspection. A
-- successful render clears the stale suppress reason.
function overlay.RenderValue(value, reason)
	reason = reason or "render"
	if not ns.db or not ns.db.enabled then
		overlay.Hide("addon disabled")
		return false, "addon disabled"
	end
	local v = ns.toNumber(value)
	if not v or v <= 0 then
		overlay.Hide(reason)
		return false, reason
	end
	local f = overlay.state.frame
	if not f then
		-- Do NOT create the overlay first time in combat.
		if overlay.IsCombat() then
			overlay.state.pending = true
			overlay.Hide("overlay not created; applies after combat")
			return false, "overlay not created; applies after combat"
		end
		overlay.InvalidateStructure()
		overlay.Resolve()
		f = overlay.state.frame
		if not f then
			overlay.Hide("no native prediction frame")
			return false, "no native prediction frame"
		end
	end
	local ab = overlay.state.ab
	if not ab then
		overlay.Hide("no native prediction frame")
		return false, "no native prediction frame"
	end

	local rangeOk, rangeDiag = overlay.ApplyRange(f, ab)
	ns.session.lastRange = rangeDiag
	if not rangeOk then
		overlay.Hide(rangeDiag)
		return false, rangeDiag
	end
	if not f.SetValue or not pcall(f.SetValue, f, v) then
		overlay.Hide("overlay value setter refused")
		return false, "overlay value setter refused"
	end
	overlay.state.counts.render = overlay.state.counts.render + 1
	if f.Show then f:Show() end
	ns.session.lastSuppress = nil
	ns.session.lastRange = rangeDiag
	ns.session.lastRenderReason = "shown; " .. rangeDiag
	return true, ns.session.lastRenderReason
end

------------------------------------------------------------------------------
-- fake render gate (own; never consults the real HoT estimate)
--
-- Model.Evaluate still evaluates real HoTs for the actual prediction. The fake
-- test is only a rendering exercise, so its status must reflect the REQUESTED
-- amount and the render outcome -- never an unrelated "no active self HoT".
-- This gate mirrors the native-structure requirements (player unit, prediction
-- on, both bars) without touching the aura/model estimate at all.
-----------------------------------------------------------------------------

function overlay.EvaluateFake(ab, requested)
	local out = { fake = true, details = {}, reasons = {} }
	local playerFrame = ns.api and ns.api.GetPlayerFrame and ns.api.GetPlayerFrame()
	if playerFrame then
		local unit, uerr = ns.api.GetFrameUnit(playerFrame)
		if unit ~= "player" then
			out.added = 0
			out.suppressed = true
			out.reason = "player frame unit " .. tostring(unit) .. " (" .. tostring(uerr) .. ")"
			return out
		end
	end
	if not ab then
		out.added = 0
		out.suppressed = true
		out.reason = "no native prediction frame"
		return out
	end
	if ab._predOn ~= true then
		out.added = 0
		out.suppressed = true
		out.reason = "native prediction disabled"
		return out
	end
	if not ab._predMy or not ab._predOther then
		out.added = 0
		out.suppressed = true
		out.reason = "native prediction bars missing"
		return out
	end
	local v = ns.toNumber(requested)
	out.requested = v
	if not v or v <= 0 then
		out.added = 0
		out.suppressed = true
		out.reason = "fake test needs a positive requested amount"
		return out
	end
	out.added = v
	out.reason = "fake test requested; visible amount engine-clipped"
	return out
end

-----------------------------------------------------------------------------
-- periodic evaluation
------------------------------------------------------------------------------

local function debugChange(key, fmt, ...)
	if not (ns.db and ns.db.debug) then return end
	if key == overlay.state.lastDebugKey then return end
	local now = ns.now()
	if overlay.state.lastDebugAt and now - overlay.state.lastDebugAt < 1 then return end
	overlay.state.lastDebugKey = key
	overlay.state.lastDebugAt = now
	ns.debug(string.format(fmt, ...))
end

function overlay.Tick(force)
	if not ns.db or not ns.db.enabled then
		overlay.Hide("addon disabled")
		return
	end
	overlay.state.counts.ticks = overlay.state.counts.ticks + 1
	if ns.queuedSwing then ns.queuedSwing.Tick() end
	local now = ns.now()
	local formRefresh = overlay.state.nextFormRefresh and now >= overlay.state.nextFormRefresh
	if formRefresh then
		ns.api.InvalidateAuraCache()
		overlay.InvalidateStructure()
		overlay.state.nextFormRefresh = overlay.state.finalFormRefresh
		overlay.state.finalFormRefresh = nil
	end

	-- Cheap identity probe; if the vendor structure changed, resolve (deferred
	-- in combat) rather than painting stale handles.
	local probe = now - (overlay.state.lastIdleProbe or -1) >= IDLE_PROBE_INTERVAL
	if probe or force or overlay.state.paintRequested or overlay.state.active then
		if overlay.StructureChanged() then overlay.state.structureDirty = true end
	end

	local fake = ns.session.fake
	local needPaint = force or overlay.state.paintRequested or overlay.state.structureDirty
		or (overlay.state.active and fake == nil)
		or (fake == nil and overlay.state.nextEstimateRetry and now >= overlay.state.nextEstimateRetry)
	-- Missing native frames must not retry full attachment every 150ms forever.
	if not overlay.state.ab and not force and not probe and not formRefresh then return end

	if not needPaint then
		-- Idle: throttle. A ~1s cheap probe keeps attachment current without a
		-- full rescan or any aura API calls.
		if probe then overlay.state.lastIdleProbe = now end
		return
	end
	if probe then overlay.state.lastIdleProbe = now end

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
		-- Fake is a render exercise only: our own gate checks the native
		-- structure but never consults the real HoT estimate, so its reason is
		-- always about this request, never "no active self HoT estimate".
		local res = overlay.EvaluateFake(overlay.state.ab, fake.value)
		local rendered, renderReason
		if res.suppressed or not res.added or res.added <= 0 then
			overlay.state.active = false
			overlay.Hide(res.reason or "fake test")
			rendered, renderReason = false, res.reason or "fake test"
		else
			overlay.state.active = true
			rendered, renderReason = overlay.RenderValue(res.added, res.reason or "fake test")
			overlay.state.active = rendered and true or false
		end
		res.rendered = rendered and true or false
		res.renderReason = renderReason
		ns.session.lastStatus = res
		if ns.db.debug then
			debugChange("fake|" .. tostring(fake.value) .. "|" .. tostring(rendered) .. "|" .. tostring(renderReason),
				"fake requested=%s shown=%s render=%s range=%s", tostring(fake.value),
				tostring(rendered), tostring(renderReason), tostring(ns.session.lastRange))
		end
		return
	end

	overlay.state.counts.model = overlay.state.counts.model + 1
	local res = ns.model.Evaluate(now, { ab = overlay.state.ab })
	overlay.state.nextEstimateRetry = res.nextEstimateRetry
	local rendered, renderReason
	if res.added and res.added > 0 then
		rendered, renderReason = overlay.RenderValue(res.added, res.reason)
	else
		overlay.Hide(res.reason)
		rendered, renderReason = false, res.reason
	end
	res.rendered = rendered and true or false
	res.renderReason = renderReason
	-- A blocked or fully clipped estimate cannot change just by ticking. Owning
	-- aura/health/native events will retry it, without continuous model work.
	overlay.state.active = res.rendered and res.added and res.added > 0 or false
	ns.session.lastStatus = res
	if ns.db.debug then
		debugChange(tostring(res.added) .. "|" .. tostring(res.reason) .. "|" .. tostring(res.hotEstimate),
			"tick hot=%s native=%s added=%s reason=%s render=%s", tostring(res.hotEstimate),
			tostring(res.native and res.native.total), tostring(res.added), tostring(res.reason),
			tostring(renderReason))
	end
end

function overlay.Setup()
	overlay.SetEnabled(ns.db and ns.db.enabled)
end

function overlay.SetEnabled(enabled)
	if not enabled then
		if overlay.state.ticker then
			overlay.state.ticker:Cancel()
			overlay.state.ticker = nil
		end
		if overlay.state.timerFrame then overlay.state.timerFrame:SetScript("OnUpdate", nil) end
		overlay.state.active = false
		overlay.state.nextEstimateRetry = nil
		overlay.state.nextFormRefresh = nil
		overlay.state.finalFormRefresh = nil
		overlay.state.paintRequested = false
		overlay.Hide("addon disabled")
		return
	end
	if overlay.state.ticker or (overlay.state.timerFrame and overlay.state.timerFrame:GetScript("OnUpdate")) then return end
	overlay.InvalidateStructure()
	overlay.state.lastIdleProbe = -1
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
		overlay.state.ticker = C_Timer.NewTicker(TICK_INTERVAL, safeTick)
	elseif type(CreateFrame) == "function" then
		local t = overlay.state.timerFrame or CreateFrame("Frame")
		overlay.state.timerFrame = t
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
