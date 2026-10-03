-- EllesmereUI_HoTPrediction / Model.lua
-- Pure(ish) prediction math: tick scheduling, per-stack amount, and the
-- conservative overlap policy. Inputs are plain Lua numbers; secret values are
-- refused before they reach any arithmetic.

local addonName, ns = ...
local model = {}
ns.model = model

model.EPS = 1e-6

-- Stacks for an aura. Returns nil when a stacking HoT has secret stacks, so the
-- caller withholds instead of guessing.
function model.EffectiveStacks(aura, meta)
	if aura.secretStacks and meta and meta.stacksMatter then return nil end
	local s = ns.toNumber(aura.stacks)
	if s == nil then s = 1 end
	if s < 1 then s = 1 end
	return s
end

-- Number of future ticks of an aura at or before expiry, using the observed
-- last tick phase when it belongs to this aura instance, otherwise the
-- application grid (expirationTime - duration). The tick exactly at expiry is
-- included; anything past expiry + eps is excluded.
-- Returns count, err, times.
function model.ComputeTicks(aura, data, now, eps)
	eps = eps or model.EPS
	if aura.secretTiming then return nil, "aura timing secret" end
	local E = ns.toNumber(aura.expirationTime)
	local D = ns.toNumber(aura.duration)
	if not E or not D then return nil, "aura timing unavailable" end
	if D <= 0 then return nil, "zero duration" end
	local I = data and ns.toNumber(data.interval)
	if not I or I <= 0 then return nil, "no interval learned/configured" end

	local anchor
	if data.lastTick and data.lastInstanceID and aura.instanceID and data.lastInstanceID == aura.instanceID then
		anchor = ns.toNumber(data.lastTick)
	end
	local applied = E - D -- current application time; grid ticks at applied + k*I
	-- Guard against a stale observed tick from before an in-place refresh.
	if not anchor or anchor < applied then
		anchor = applied
	end

	local times = {}
	local maxK = math.floor(D / I) + 3
	for k = 1, maxK do
		local t = anchor + k * I
		if t > E + eps then break end
		if t > now + eps then
			times[#times + 1] = t
		end
	end
	return #times, nil, times
end

-- Returns { ticks, amount, perTick, stacks, base } or nil, reason.
function model.ComputeAuraEstimate(aura, meta, data, now, eps)
	local count, err = model.ComputeTicks(aura, data, now, eps)
	if not count then return nil, err end
	if count == 0 then return { ticks = 0, amount = 0, perTick = 0, stacks = 1 } end
	local stacks = model.EffectiveStacks(aura, meta)
	if not stacks then return nil, "stacks unavailable for stacking HoT" end
	local base = data and ns.toNumber(data.basePerStack)
	if not base or base <= 0 then return nil, "tick amount not learned" end
	local perTick = base * stacks
	return { ticks = count, amount = perTick * count, perTick = perTick, stacks = stacks, base = base }
end

-- Collects all player self-cast candidate HoTs and sums their remaining amount.
-- Returns { total=nil|number, details={...}, reasons={...} }.
function model.CollectPlayerHoTs(now)
	local out = { total = nil, details = {}, reasons = {} }
	local auras = (ns.api and ns.api.ReadPlayerAuras and ns.api.ReadPlayerAuras()) or {}
	local sum = 0
	local any = false
	for i = 1, #auras do
		local aura = auras[i]
		local meta = ns.spells.Meta(aura.spellID)
		if meta then
			if aura.sourceUnit and aura.sourceUnit ~= "player" then
				out.reasons[#out.reasons + 1] = string.format("%s: foreign caster", tostring(aura.spellID))
			else
				local data = ns.learner.GetSpellData(aura.spellID)
				local res, err = model.ComputeAuraEstimate(aura, meta, data, now)
				if res then
					if res.amount > 0 then
						sum = sum + res.amount
						any = true
					end
					out.details[#out.details + 1] = {
						spellID = aura.spellID,
						family = meta.name or meta.family,
						ticks = res.ticks,
						perTick = res.perTick,
						stacks = res.stacks,
						amount = res.amount,
						approximate = meta.approximate and true or false,
					}
				else
					out.reasons[#out.reasons + 1] = string.format("%s: %s", tostring(aura.spellID), tostring(err))
				end
			end
		end
	end
	if any then out.total = sum end
	return out
end

-- Conservative overlap: append only what the native incoming number does not
-- already explain.
--   excludesHoTs=false -> added = max(0, hot - nativeTotal)
--   excludesHoTs=true  -> added = hot            (opt-in, user verified runtime)
-- Then clamp into remaining health when health is readable (never past max HP).
-- Returns added(number) or nil, reason.
function model.ComputeAdded(hotEstimate, native, healthInfo, opts)
	opts = opts or {}
	local excludes = opts.excludes and true or false
	if not hotEstimate or hotEstimate <= 0 then return 0, "no HoT estimate" end

	local added, reason
	if excludes then
		added = hotEstimate
		reason = "excludes-HoT mode: appended full estimate"
	else
		if type(native) ~= "table" or native.reason then
			return nil, "native incoming unavailable (" .. tostring(native and native.reason or "nil") .. ")"
		end
		local nt = ns.toNumber(native.total)
		if not nt then return nil, "native incoming not numeric" end
		added = hotEstimate - nt
		if added < 0 then added = 0 end
		reason = "conservative max(0, hot - native)"
	end

	if healthInfo then
		local h = ns.toNumber(healthInfo.health)
		local m = ns.toNumber(healthInfo.max)
		if h and m then
			local nativeTotal = 0
			if not excludes and type(native) == "table" then
				nativeTotal = ns.toNumber(native.total) or 0
			end
			local room = m - h - nativeTotal
			if room < 0 then room = 0 end
			if added > room then
				added = room
				reason = (reason or "") .. "; clamped to missing health"
			end
		end
	end
	return added, reason
end

-- End-to-end evaluation using live adapters. Returns a result table used both
-- by the overlay and by /euihot status+debug. `opts.fake` bypasses absorb/native
-- gating for the render test.
function model.Evaluate(now, opts)
	opts = opts or {}
	now = now or ns.now()
	local db = ns.db or {}
	local out = { now = now, details = {}, reasons = {} }

	local hot = model.CollectPlayerHoTs(now)
	out.hotEstimate = hot.total
	out.details = hot.details
	out.auraReasons = hot.reasons

	local ab = opts.ab
	if ab == nil and ns.api and ns.api.GetAbsorbFrame then
		ab = ns.api.GetAbsorbFrame()
	end

	-- Never paint a vehicle's health: the player frame's unit may have switched.
	local playerFrame = ns.api and ns.api.GetPlayerFrame and ns.api.GetPlayerFrame()
	if playerFrame then
		local unit = playerFrame._euiUnit
		if unit ~= nil and not ns.isSecret(unit) and unit ~= "player" then
			out.added = 0
			out.suppressed = true
			out.reason = "player frame showing unit '" .. tostring(unit) .. "' (not player)"
			return out
		end
	end

	if ab and ab._predOn == false and not opts.fake and not db.assumeApiExcludesHoTs then
		out.added = 0
		out.suppressed = true
		out.reason = "native prediction disabled"
		return out
	end

	local native
	if ab and ns.api and ns.api.GetNativeIncoming then
		native = ns.api.GetNativeIncoming(ab)
	else
		native = { reason = "no native prediction frame" }
	end
	out.native = native

	local absorbing, absorbReason = false, nil
	if not opts.fake and ns.api and ns.api.HasHealAbsorb then
		absorbing, absorbReason = ns.api.HasHealAbsorb()
	end

	if absorbing and hot.total and hot.total > 0 then
		out.added = 0
		out.suppressed = true
		out.reason = "suppressed: " .. tostring(absorbReason or "heal absorb active")
		return out
	end

	if not hot.total or hot.total <= 0 then
		out.added = 0
		if #hot.reasons > 0 then
			out.reason = "withheld: " .. hot.reasons[1]
		else
			out.reason = "no active self HoT estimate"
		end
		return out
	end

	local healthInfo = ns.api and ns.api.GetHealthNumbers and ns.api.GetHealthNumbers() or nil
	out.health = healthInfo
	local added, reason = model.ComputeAdded(hot.total, native, healthInfo, { excludes = db.assumeApiExcludesHoTs })
	if added == nil then
		out.suppressed = true
		out.added = 0
		out.reason = reason
	else
		out.added = added
		out.reason = reason
	end
	return out
end
