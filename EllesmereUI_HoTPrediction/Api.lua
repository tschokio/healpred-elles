-- EllesmereUI_HoTPrediction / Api.lua
-- Thin, defensive adapters over the live client and the EllesmereUIUnitFrames
-- namespace. Every call into foreign code is pcall-wrapped; nothing here ever
-- performs arithmetic on a value that may be secret.

local addonName, ns = ...
local api = {}
ns.api = api

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

function api.InCombat()
	local f = InCombatLockdown
	if type(f) == "function" then
		local ok, res = pcall(f)
		if ok then return res and true or false end
	end
	return ns.inCombat and true or false
end

-- Guarded player GUID: a secret GUID is refused, never compared.
function api.PlayerGUID()
	local f = UnitGUID
	if type(f) ~= "function" then return nil end
	local ok, g = pcall(f, "player")
	if not ok or ns.isSecret(g) or type(g) ~= "string" then return nil end
	return g
end

function api.UnitExists(unit)
	local f = UnitExists
	if type(f) ~= "function" then return false end
	local ok, res = pcall(f, unit)
	return ok and res and true or false
end

-- Which unit is the given player frame currently showing? A secret or missing
-- unit means "unknown": the caller must not paint.
function api.GetFrameUnit(playerFrame)
	if not playerFrame then return nil, "no player frame" end
	local unit
	local ok, v = pcall(function() return playerFrame._euiUnit end)
	if ok and v ~= nil then unit = v end
	if unit == nil and type(playerFrame.GetAttribute) == "function" then
		local ok2, v2 = pcall(playerFrame.GetAttribute, playerFrame, "unit")
		if ok2 and v2 ~= nil then unit = v2 end
	end
	if ns.isSecret(unit) then return nil, "frame unit secret" end
	if type(unit) ~= "string" or unit == "" then return nil, "frame unit unavailable" end
	return unit
end

------------------------------------------------------------------------------
-- aura reading (event-invalidated cache)
------------------------------------------------------------------------------

-- Aura data is expensive to rescan, so the list is cached until an owning event
-- (UNIT_AURA player, entering world, reset, amountmode) invalidates it. The
-- paint timer NEVER triggers a rescan by itself.
function api.InvalidateAuraCache()
	ns.session.auraCache = nil
end

function api.ReadPlayerAuras()
	if ns.session.auraCache then return ns.session.auraCache end
	ns.session.auraCache = api._ScanPlayerAuras()
	return ns.session.auraCache
end

-- Returns every parsable aura record; strict ownership is enforced by the
-- consumers (Model/Learner/status) so unknown or foreign casters can be
-- reported as reasons rather than silently dropped.
function api._ScanPlayerAuras()
	local list = {}
	local unit = "player"
	local fn = C_UnitAuras and C_UnitAuras.GetAuraDataByIndex
	if type(fn) ~= "function" then return list end

	for _, filter in ipairs({ "HELPFUL|PLAYER", "HELPFUL" }) do
		local localList = {}
		local okFirst = true
		local i = 1
		while i < 200 do
			local ok, data = pcall(fn, unit, i, filter)
			if i == 1 then okFirst = ok end
			if not ok or data == nil then break end
			local rec = api._AuraFromModern(data)
			if rec then
				localList[#localList + 1] = rec
			end
			i = i + 1
		end
		if okFirst then return localList end
	end
	return list
end

-- Normalises one modern aura record. Every index is pcall-wrapped because the
-- container itself may be a secret table. Never retains a secret value.
function api._AuraFromModern(data)
	if ns.isSecret(data) then
		ns.session.lastSuppress = "aura container secret"
		return nil
	end
	if type(data) ~= "table" then return nil end

	local function field(k)
		local ok, v = pcall(function() return data[k] end)
		if not ok then return nil, true end
		return v, false
	end

	local spellID, sBad = field("spellId")
	if sBad or ns.isSecret(spellID) or type(spellID) ~= "number" then
		ns.session.lastSuppress = "aura spellId unreadable/secret"
		return nil
	end

	local inst, iBad = field("auraInstanceID")
	if iBad or ns.isSecret(inst) or type(inst) ~= "number" then inst = nil end

	local su, uBad = field("sourceUnit")
	if uBad or ns.isSecret(su) or type(su) ~= "string" then su = nil end

	local app, aBad = field("applications")
	local exp, eBad = field("expirationTime")
	local dur, dBad = field("duration")

	local rec = {
		spellID = spellID,
		instanceID = inst,
		sourceUnit = su,
		secretStacks = (aBad or ns.isSecret(app)) and true or false,
		secretTiming = (eBad or dBad or ns.isSecret(exp) or ns.isSecret(dur)) and true or false,
	}
	-- Explicit if-statements (never `secret and nil or value`, which would keep
	-- the secret when the guard is truthy).
	if not rec.secretStacks then
		rec.stacks = ns.toNumber(app)
	else
		rec.stacks = nil
	end
	rec.expirationTime = (not rec.secretTiming) and ns.toNumber(exp) or nil
	rec.duration = (not rec.secretTiming) and ns.toNumber(dur) or nil
	return rec
end

------------------------------------------------------------------------------
-- native incoming heals (read native bars only)
------------------------------------------------------------------------------

-- Returns { mine, others, total, source } when both native bars read as plain
-- numbers, otherwise { reason = "..." }.
function api.GetNativeIncoming(ab)
	if not ab then return { reason = "no absorb module" } end
	local mineBar, otherBar = ab._predMy, ab._predOther
	if not mineBar or not otherBar or not mineBar.GetValue or not otherBar.GetValue then
		return { reason = "native prediction bars missing" }
	end
	local okM, mv = pcall(mineBar.GetValue, mineBar)
	local okO, ov = pcall(otherBar.GetValue, otherBar)
	if not okM or not okO then return { reason = "native bar read error" } end
	if ns.isSecret(mv) or ns.isSecret(ov) then return { reason = "native bar values secret" } end
	local mine = ns.toNumber(mv)
	local others = ns.toNumber(ov)
	if mine == nil or others == nil then return { reason = "native bar values nonnumeric" } end
	return { mine = mine, others = others, total = mine + others, source = "bars" }
end

------------------------------------------------------------------------------
-- health / absorb facts
------------------------------------------------------------------------------

function api.GetHealthNumbers()
	local hraw = UnitHealth and UnitHealth("player")
	if ns.isSecret(hraw) then return nil, "health secret" end
	local mraw = UnitHealthMax and UnitHealthMax("player")
	if ns.isSecret(mraw) then return nil, "max health secret" end
	local h = ns.toNumber(hraw)
	local m = ns.toNumber(mraw)
	if h == nil or m == nil then
		return nil, "health unavailable"
	end
	if m <= 0 then return nil, "max health zero" end
	return { health = h, max = m }
end

-- Tri-state heal-absorb probe:
--   number (>=0) -> readable value
--   nil, reason  -> UNKNOWN (missing API / error / secret / nonnumeric)
-- A positive OR unknown result suppresses the real overlay.
function api.GetHealAbsorb()
	local f = UnitGetTotalHealAbsorbs
	if type(f) ~= "function" then return nil, "heal absorb API missing" end
	local ok, v = pcall(f, "player")
	if not ok then return nil, "heal absorb API error" end
	if ns.isSecret(v) then return nil, "heal absorb secret" end
	local n = ns.toNumber(v)
	if n == nil then return nil, "heal absorb nonnumeric" end
	return n, nil
end

-- Back-compat boolean wrapper used by tests/diagnostics.
function api.HasHealAbsorb()
	local v, reason = api.GetHealAbsorb()
	if v == nil then return true, reason end
	if v > 0 then return true, "heal absorb active" end
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
		if ok and tex then info.textureObject = tex end
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
	if bar.GetStatusBarAlpha then
		local ok, v = pcall(bar.GetStatusBarAlpha, bar)
		info.colorAlpha = ok and ns.toNumber(v) or nil
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

-- Ordered list of the native incoming bars we may chain after. _predMy is
-- always included as a stable anchor; _predOther only when actually shown.
function api.GetNativeChain(ab)
	local chain = {}
	if not ab then return chain end
	local my, other = ab._predMy, ab._predOther
	if other then
		local shown = true
		if other.IsShown then
			local ok, v = pcall(other.IsShown, other)
			shown = ok and v and true or false
		end
		if shown then chain[#chain + 1] = other end
	end
	if my then chain[#chain + 1] = my end
	return chain
end

------------------------------------------------------------------------------
-- combat log
------------------------------------------------------------------------------

-- Modern CLEU: the event carries no varargs; the current tuple must be fetched.
-- Returned as an explicit pack so nil holes and trailing false survive.
function api.GetCLEU()
	local f = CombatLogGetCurrentEventInfo
	if type(f) ~= "function" then return nil end
	local p = ns.pack(pcall(f))
	if not p[1] then return nil end
	local out = { n = p.n - 1 }
	for i = 2, p.n do
		out[i - 1] = p[i]
	end
	return out
end

function api.CombatLogAvailable()
	return type(CombatLogGetCurrentEventInfo) == "function"
end
