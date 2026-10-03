-- EllesmereUI_HoTPrediction / Model.lua
-- Pure(ish) prediction math: tick scheduling, per-stack-count amount, and the
-- conservative overlap policy. Inputs are plain Lua numbers; secret values are
-- refused before they reach any arithmetic.

local addonName, ns = ...
local model = {}
ns.model = model

model.EPS = 1e-6

-- Stacks for an aura. Stacking families withhold when their stack count is
-- secret OR unreadable (never assume 1). Non-stacking families are always 1,
-- so a stray applications=0/count0 is normalised to 1.
function model.EffectiveStacks(aura, meta)
	if meta and meta.stacksMatter then
		if aura.secretStacks then return nil end
		local s = ns.toNumber(aura.stacks)
		if s == nil then return nil end
		if s < 1 then s = 1 end
		return s
	end
	return 1
end

-- Number of future ticks of an aura at or before expiry, using the observed
-- last tick phase when it belongs to this aura instance AND application
-- signature, otherwise the application grid (expirationTime - duration). The
-- tick exactly at expiry is included; anything past expiry + eps is excluded.
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
	if data.lastTick and data.lastInstanceID and aura.instanceID
		and data.lastInstanceID == aura.instanceID
		and (data.lastSig == nil or aura.expirationTime == data.lastSig) then
		anchor = ns.toNumber(data.lastTick)
	end
	local applied = E - D -- current application time; grid ticks at applied + k*I
	-- Guard against a stale observed tick from before an in-place refresh.
	if not anchor or anchor < applied then
		anchor = applied
	end

	local times = {}
	local maxK = math.floor(D / I) + 3
	-- Defensive work bound, not a spell-mechanics assumption. Bad calibration or
	-- malformed aura durations must never cause millions of iterations per paint
	-- (or while building a copyable status report).
	if maxK > 10000 then return nil, "tick schedule exceeds safety limit" end
	for k = 1, maxK do
		local t = anchor + k * I
		if t > E + eps then break end
		if t > now + eps then
			times[#times + 1] = t
		end
	end
	return #times, nil, times
end

-- Returns { ticks, amount, perTick, stacks, base, approximate } or nil, reason.
-- For stacking families the observed total at the current stack count is used
-- directly. If it was never observed at that count the estimate is withheld
-- (never base * stacks).
function model.ComputeAuraEstimate(aura, meta, data, now, eps)
	local count, err = model.ComputeTicks(aura, data, now, eps)
	if not count then return nil, err end
	if count == 0 then
		return { ticks = 0, amount = 0, perTick = 0, stacks = 1, approximate = meta and meta.approximate or false }
	end

	if meta and meta.stacksMatter then
		local stacks = model.EffectiveStacks(aura, meta)
		if not stacks then return nil, "stacks unavailable for stacking HoT" end
		local total = ns.learner.AmountForStack(aura.spellID, stacks)
		if not total or total <= 0 then
			return nil, string.format("tick amount not learned at %d stacks", stacks)
		end
		return { ticks = count, amount = total * count, perTick = total, stacks = stacks,
			base = total, approximate = meta.approximate and true or false }
	end

	local base = data and ns.toNumber(data.basePerStack)
	if not base and data and data.totals and data.totals[1] then
		base = ns.toNumber(data.totals[1].value)
	end
	if not base or base <= 0 then return nil, "tick amount not learned" end
	return { ticks = count, amount = base * count, perTick = base, stacks = 1, base = base,
		approximate = meta and meta.approximate and true or false }
end

-- Collects all player self-cast candidate HoTs and sums their remaining amount.
-- Strict ownership: only sourceUnit == "player" is accepted; nil/secret/foreign
-- casters are recorded as reasons and never counted.
function model.CollectPlayerHoTs(now)
	local out = { total = nil, details = {}, reasons = {} }
	local auras = (ns.api and ns.api.ReadPlayerAuras and ns.api.ReadPlayerAuras()) or {}
	local sum = 0
	local any = false
	for i = 1, #auras do
		local aura = auras[i]
		local meta = ns.spells.Meta(aura.spellID)
		if meta then
			if aura.sourceUnit ~= "player" then
				out.reasons[#out.reasons + 1] = string.format("%s: %s caster",
					tostring(aura.spellID), aura.sourceUnit and tostring(aura.sourceUnit) or "unknown")
			else
				local data = ns.learner.GetSpellData(aura.spellID, aura)
				if data.nextEstimateRetry then
					out.nextEstimateRetry = math.min(out.nextEstimateRetry or data.nextEstimateRetry, data.nextEstimateRetry)
				end
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
						approximate = res.approximate and true or false,
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

-- Conservative overlap. Native total MUST be a readable number in BOTH modes;
-- the excludes-HoT opt-in only changes whether the HoT estimate is subtracted.
--   excludes=false -> added = max(0, hot - nativeTotal)
--   excludes=true  -> added = hot            (user verified runtime)
-- Then clamp into remaining health so native + added never exceeds missing HP.
-- Returns added(number) or nil, reason.
function model.ComputeAdded(hotEstimate, native, healthInfo, opts)
	opts = opts or {}
	local excludes = opts.excludes and true or false
	if not hotEstimate or hotEstimate <= 0 then return 0, "no HoT estimate" end

	if type(native) ~= "table" or native.reason then
		return nil, "native incoming unavailable (" .. tostring(native and native.reason or "nil") .. ")"
	end
	local nt = ns.toNumber(native.total)
	if nt == nil then return nil, "native incoming not numeric" end

	local added, reason
	if excludes then
		added = hotEstimate
		reason = "excludes-HoT mode: appended full estimate"
	else
		added = hotEstimate - nt
		if added < 0 then added = 0 end
		reason = "conservative max(0, hot - native)"
	end

	if healthInfo then
		local h = ns.toNumber(healthInfo.health)
		local m = ns.toNumber(healthInfo.max)
		if h and m then
			local room = m - h - nt
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
-- by the overlay and by /euihot status+debug. `opts.fake` is the render test:
-- it still requires a player unit and valid native bars, but bypasses the heal
-- absorb gate so a user can exercise rendering.
function model.Evaluate(now, opts)
	opts = opts or {}
	now = now or ns.now()
	local db = ns.db or {}
	local out = { now = now, details = {}, reasons = {} }

	-- Vehicle / unknown-unit guard applies to REAL and FAKE alike.
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

	local ab = opts.ab
	if ab == nil and ns.api and ns.api.GetAbsorbFrame then
		ab = ns.api.GetAbsorbFrame()
	end

	-- Native prediction is required for BOTH modes: _predOn true and both bars
	-- present, so we never anchor a stale hidden segment.
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

	local hot = model.CollectPlayerHoTs(now)
	out.hotEstimate = hot.total
	out.details = hot.details
	out.auraReasons = hot.reasons
	out.nextEstimateRetry = hot.nextEstimateRetry

	local native = ns.api.GetNativeIncoming(ab)
	out.native = native

	-- Explicitly authorized rough mode. It never interprets restricted native or
	-- absorb values as zero: instead the status says overlap is UNVERIFIED. Engine
	-- clipping bounds the appended public estimate when health is restricted.
	if db.approximatePrediction then
		out.approximate = true
		if not hot.total or hot.total <= 0 then
			out.added = 0
			out.reason = #hot.reasons > 0 and ("withheld: " .. hot.reasons[1]) or "no active self HoT estimate"
			return out
		end
		if native.reason then
			out.added = hot.total
			out.reason = "approximate full HoT estimate; native overlap unverified; heal absorbs ignored; engine-clipped"
		else
			local health = ns.api.GetHealthNumbers()
			out.added, out.reason = model.ComputeAdded(hot.total, native, health, { excludes = db.assumeApiExcludesHoTs })
			out.reason = "approximate; heal absorbs ignored; " .. tostring(out.reason)
		end
		return out
	end

	-- Positive OR unknown heal absorb suppresses the real overlay. Fake bypasses.
	if not opts.fake and ns.api and ns.api.GetHealAbsorb then
		local absorb, absorbReason = ns.api.GetHealAbsorb()
		if absorb == nil then
			out.added = 0
			out.suppressed = true
			out.reason = "suppressed: unknown heal absorb (" .. tostring(absorbReason) .. ")"
			return out
		elseif absorb > 0 then
			out.added = 0
			out.suppressed = true
			out.reason = "suppressed: heal absorb active"
			return out
		end
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
