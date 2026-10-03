-- EllesmereUI_HoTPrediction / Api.lua
-- Thin, defensive adapters over the live client and the EllesmereUIUnitFrames
-- namespace. Every call into foreign code is pcall-wrapped; nothing here ever
-- performs arithmetic on a value that may be secret.

local addonName, ns = ...
local api = {}
ns.api = api

local unpack = unpack or table.unpack
local EUF_MODULE = "EllesmereUIUnitFrames"

function api.GetEUF()
	local root = EllesmereUI
	if type(root) ~= "table" then return nil end
	local mods = root._ModuleNS
	if type(mods) ~= "table" then return nil end
	return mods[EUF_MODULE]
end

function api.GetPlayerFrame()
	local euf = api.GetEUF()
	if not euf or type(euf.frames) ~= "table" then return nil end
	return euf.frames.player
end

-- Returns ab, player, hp where ab is the native absorb/prediction module.
function api.GetAbsorbFrame()
	local player = api.GetPlayerFrame()
	if not player then return nil, nil, nil end
	local hp = player.Health
	local hpPred = player.HealthPrediction
	local ab = hpPred and hpPred.damageAbsorb
	return ab, player, hp
end

function api.InvalidateAuraCache()
	ns.session.auraReadAt = nil
end

function api.InCombat()
	local f = InCombatLockdown
	if type(f) == "function" then
		local ok, res = pcall(f)
		if ok then return res and true or false end
	end
	return ns.inCombat and true or false
end

function api.PlayerGUID()
	local g = UnitGUID and UnitGUID("player")
	return type(g) == "string" and g or nil
end

function api.UnitExists(unit)
	local f = UnitExists
	if type(f) ~= "function" then return false end
	local ok, res = pcall(f, unit)
	return ok and res and true or false
end

------------------------------------------------------------------------------
-- aura reading
------------------------------------------------------------------------------

-- Reads helpful player-owned auras. Returns a list of records:
-- { spellID, stacks, expirationTime, duration, instanceID, sourceUnit,
--   secretStacks=bool, secretTiming=bool, reason=nil }
-- Records with an unreadable spell ID are skipped (cannot be classified).
function api.ReadPlayerAuras()
	local list = {}
	local unit = "player"

	if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
		-- Prefer the player-owned filter; fall back if a client rejects it.
		for _, filter in ipairs({ "HELPFUL|PLAYER", "HELPFUL" }) do
			local okFirst = true
			local i = 1
			while i < 200 do
				local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
				if i == 1 then okFirst = ok end
				if not ok or data == nil then break end
				local rec = api._AuraFromModern(data)
				if rec then list[#list + 1] = rec end
				i = i + 1
			end
			if okFirst then return list end
			list = {}
		end
		return list
	end

	-- Legacy adapter (older clients only; WoW 1.12-era API never assumed).
	if type(UnitAura) == "function" then
		local i = 1
		while i < 100 do
			local ok, name, _rank, _icon, count, _dispel, duration, expiration, source, _steal, _npp, spellId =
				pcall(UnitAura, unit, i, "HELPFUL")
			if not ok or name == nil then break end
			list[#list + 1] = {
				spellID = ns.toNumber(spellId),
				stacks = ns.toNumber(count) or 1,
				expirationTime = ns.toNumber(expiration),
				duration = ns.toNumber(duration),
				instanceID = ns.toNumber(spellId), -- legacy has no instance id; spell id is the key
				sourceUnit = source,
				secretStacks = false,
				secretTiming = false,
				legacy = true,
			}
			i = i + 1
		end
	end
	return list
end

function api._AuraFromModern(data)
	if type(data) ~= "table" then return nil end
	local spellID = data.spellId
	if ns.isSecret(spellID) or type(spellID) ~= "number" then
		-- Cannot identify the aura; surface a reason through the record set.
		ns.session.lastSuppress = "aura spellId unreadable/secret"
		return nil
	end
	local sourceUnit = data.sourceUnit
	if ns.isSecret(sourceUnit) then sourceUnit = nil end
	local rec = {
		spellID = spellID,
		instanceID = ns.isSecret(data.auraInstanceID) and nil or data.auraInstanceID,
		sourceUnit = sourceUnit,
		secretStacks = ns.isSecret(data.applications),
		secretTiming = ns.isSecret(data.expirationTime) or ns.isSecret(data.duration),
	}
	rec.stacks = ns.toNumber(data.applications) or 1
	rec.expirationTime = ns.toNumber(data.expirationTime)
	rec.duration = ns.toNumber(data.duration)
	return rec
end

------------------------------------------------------------------------------
-- native incoming heals
------------------------------------------------------------------------------

-- Returns { mine, others, total, source } when both components are readable
-- plain numbers, otherwise { reason = "..." }.
function api.GetNativeIncoming(ab)
	if not ab then return { reason = "no absorb module" } end

	-- Preferred: read the native prediction bars, which are already clamped and
	-- secret-safe for the client.
	local mineBar, otherBar = ab._predMy, ab._predOther
	if mineBar and otherBar and mineBar.GetValue and otherBar.GetValue then
		local okM, mv = pcall(mineBar.GetValue, mineBar)
		local okO, ov = pcall(otherBar.GetValue, otherBar)
		local mine = okM and ns.toNumber(mv) or nil
		local others = okO and ns.toNumber(ov) or nil
		if mine and others then
			return { mine = mine, others = others, total = mine + others, source = "bars" }
		end
		if ns.isSecret(mv) or ns.isSecret(ov) then
			return { reason = "native bar values secret" }
		end
	end

	-- Fallback: ask the native predictor directly.
	if ab._predCalc and type(UnitGetDetailedHealPrediction) == "function" then
		local okCall = pcall(UnitGetDetailedHealPrediction, "player", "player", ab._predCalc)
		if okCall and ab._predCalc.GetIncomingHeals then
			local ok, _head, m, o = pcall(ab._predCalc.GetIncomingHeals, ab._predCalc)
			if ok then
				if ns.isSecret(m) or ns.isSecret(o) then
					return { reason = "calc incoming heals secret" }
				end
				local mine = ns.toNumber(m)
				local others = ns.toNumber(o)
				if mine and others then
					return { mine = mine, others = others, total = mine + others, source = "calc" }
				end
			end
		end
	end

	return { reason = "native incoming unavailable" }
end

------------------------------------------------------------------------------
-- health / absorb facts
------------------------------------------------------------------------------

function api.GetHealthNumbers()
	local h = ns.toNumber(UnitHealth and UnitHealth("player"))
	local m = ns.toNumber(UnitHealthMax and UnitHealthMax("player"))
	if h == nil or m == nil then
		return nil, (ns.isSecret(UnitHealth and UnitHealth("player")) and "health secret") or "health unavailable"
	end
	if m <= 0 then return nil, "max health zero" end
	return { health = h, max = m }
end

-- Positive / unknown heal-absorption forces us to suppress (conservative).
function api.HasHealAbsorb()
	local f = UnitGetTotalHealAbsorbs
	if type(f) == "function" then
		local ok, v = pcall(f, "player")
		if ok then
			if ns.isSecret(v) then return true, "heal absorb secret" end
			local n = ns.toNumber(v)
			if n and n > 0 then return true, "heal absorb active" end
		end
	end
	return false, nil
end

------------------------------------------------------------------------------
-- widget introspection (for anchoring/styling our own overlay)
------------------------------------------------------------------------------

function api.GetBarInfo(bar)
	if not bar then return nil end
	local info = { shown = true }
	if bar.IsShown then
		local ok, v = pcall(bar.IsShown, bar)
		info.shown = ok and v and true or false
	end
	if bar.GetStatusBarTexture then
		local ok, tex = pcall(bar.GetStatusBarTexture, bar)
		if ok and tex and tex.GetTexture then
			local ok2, path = pcall(tex.GetTexture, tex)
			if ok2 then info.texture = path end
		end
	end
	if bar.GetOrientation then
		local ok, v = pcall(bar.GetOrientation, bar)
		if ok and (v == "VERTICAL" or v == "HORIZONTAL") then info.orientation = v end
	end
	if bar.IsReverseFill then
		local ok, v = pcall(bar.IsReverseFill, bar)
		if ok then info.reversed = v and true or false end
	elseif bar.GetReverseFill then
		local ok, v = pcall(bar.GetReverseFill, bar)
		if ok then info.reversed = v and true or false end
	end
	if bar.GetStatusBarColor then
		local ok, r, g, b = pcall(bar.GetStatusBarColor, bar)
		if ok and ns.toNumber(r) and ns.toNumber(g) and ns.toNumber(b) then
			info.color = { r, g, b }
		end
	end
	if bar.GetAlpha then
		local ok, v = pcall(bar.GetAlpha, bar)
		info.alpha = ok and ns.toNumber(v) or nil
	end
	if bar.GetFrameLevel then
		local ok, v = pcall(bar.GetFrameLevel, bar)
		info.level = ok and ns.toNumber(v) or nil
	end
	return info
end

-- Ordered list of shown native incoming bars (my first, other second).
function api.GetNativeChain(ab)
	local chain = {}
	if not ab then return chain end
	for _, bar in ipairs({ ab._predMy, ab._predOther }) do
		if bar then
			local shown = true
			if bar.IsShown then
				local ok, v = pcall(bar.IsShown, bar)
				shown = ok and v and true or false
			end
			-- Include _predMy even when hidden so we have a stable anchor.
			if shown or bar == ab._predMy then chain[#chain + 1] = bar end
		end
	end
	return chain
end

function api.GetCLEU()
	local f = CombatLogGetCurrentEventInfo
	if type(f) ~= "function" then return nil end
	local results = { pcall(f) }
	if not results[1] then return nil end
	return unpack(results, 2)
end

function api.CombatLogAvailable()
	return type(CombatLogGetCurrentEventInfo) == "function"
end
