-- EllesmereUI_HoTPrediction / Learner.lua
-- Observes SPELL_PERIODIC_HEAL from the combat log to learn two things per
-- spell, session only:
--   * the tick interval (from consecutive same-instance / same-application ticks)
--   * the per-stack-count tick total (recent bounded samples)
--
-- Adapter assumption: by default the CLEU "amount" field is the total heal
-- including overheal. On modified clients that report effective healing plus a
-- separate overheal field, the user can switch to "effective" mode.
--
-- Nothing here is persisted, so stale gear values cannot survive a reload.

local addonName, ns = ...
local learner = {}
ns.learner = learner

local MAX_INTERVAL_GAP = 30      -- ignore deltas larger than this (cross-refresh)
local MIN_INTERVAL_GAP = 0.20    -- ignore duplicate/instant events
local INTERVAL_WINDOW = 10       -- bounded recent deltas (haste changes)
local AMOUNT_WINDOW = 8          -- bounded recent totals per stack count
local INTERVAL_DECIMALS = 1

local function bucketOf(delta)
	local mult = 10 ^ INTERVAL_DECIMALS
	return math.floor(delta * mult + 0.5) / mult
end

local function learnedFor(id)
	local L = ns.session.learned
	local d = L[id]
	if not d then
		d = {
			interval = nil,
			intervalSamples = {}, -- bounded recent delta buckets
			rawCount = 0,
			totals = {},          -- [stacks] = { samples = {..}, value = number, count = }
			basePerStack = nil,   -- convenience for non-stacking families (stack 1)
			baseCount = 0,
			lastTick = nil,
			lastInstanceID = nil,
			lastSig = nil,
			stacksMatter = false,
		}
		L[id] = d
	end
	return d
end

function learner.Reset()
	ns.session.learned = {}
	ns.session.lastTicksAt = {}
	if ns.api and ns.api.InvalidateAuraCache then ns.api.InvalidateAuraCache() end
end

-- Drop learned magnitudes (gear-dependent) but keep intervals (mechanical).
function learner.ResetAmounts()
	for _, d in pairs(ns.session.learned or {}) do
		d.totals = {}
		d.basePerStack = nil
		d.baseCount = 0
	end
	if ns.api and ns.api.InvalidateAuraCache then ns.api.InvalidateAuraCache() end
end

-- Robust interval from a bounded recent window: most common 0.1s bucket,
-- ties resolved to the smaller value. Adapts when haste changes.
local function recomputeInterval(d)
	local hist = {}
	local best, bestCount
	for i = 1, #d.intervalSamples do
		local b = d.intervalSamples[i]
		hist[b] = (hist[b] or 0) + 1
		local c = hist[b]
		if c > (bestCount or 0) or (c == bestCount and best and b < best) then
			best, bestCount = b, c
		end
	end
	d.interval = best
end

function learner.ObserveInterval(id, delta)
	local d = learnedFor(id)
	local n = ns.toNumber(delta)
	if not n or n < MIN_INTERVAL_GAP or n > MAX_INTERVAL_GAP then return end
	local b = bucketOf(n)
	d.intervalSamples[#d.intervalSamples + 1] = b
	while #d.intervalSamples > INTERVAL_WINDOW do table.remove(d.intervalSamples, 1) end
	d.rawCount = (d.rawCount or 0) + 1
	recomputeInterval(d)
end

-- Records a valid non-crit, non-absorbed, owned periodic-heal total for a
-- specific stack count. Stacking families are deliberately NOT modelled as
-- base*stacks: the exact total observed at each stack count is what we use.
function learner.ObserveBase(id, total, stacks, approximate)
	local d = learnedFor(id)
	local n = ns.toNumber(total)
	local s = ns.toNumber(stacks)
	if s == nil then s = 1 end
	s = math.floor(s)
	if s < 1 then s = 1 end
	if not n or n <= 0 then return end

	local bucket = d.totals[s]
	if not bucket then
		bucket = { samples = {}, value = nil, count = 0 }
		d.totals[s] = bucket
	end
	bucket.samples[#bucket.samples + 1] = n
	while #bucket.samples > AMOUNT_WINDOW do table.remove(bucket.samples, 1) end
	bucket.count = #bucket.samples

	if approximate then
		-- Strength-varying HoTs (e.g. Wild Growth) decline over the cast: the
		-- conservative minimum of recent samples avoids overestimating the tail.
		local mn
		for i = 1, #bucket.samples do
			if mn == nil or bucket.samples[i] < mn then mn = bucket.samples[i] end
		end
		bucket.value = mn
	else
		local sum = 0
		for i = 1, #bucket.samples do sum = sum + bucket.samples[i] end
		bucket.value = sum / #bucket.samples
	end

	if s == 1 then
		d.basePerStack = bucket.value
		d.baseCount = bucket.count
	end
end

-- Learned total for an exact stack count, or nil when never observed there.
function learner.AmountForStack(id, stacks)
	local d = ns.session.learned and ns.session.learned[id]
	if not d then return nil end
	local s = ns.toNumber(stacks)
	if s == nil then return nil end
	s = math.floor(s)
	local bucket = d.totals and d.totals[s]
	return bucket and bucket.value or nil
end

-- Merge learned session data with an explicit user interval override.
function learner.GetSpellData(id)
	local d = ns.session.learned and ns.session.learned[id]
	local override = ns.spells.IntervalOverride(id)
	local out = {
		interval = override or (d and d.interval) or nil,
		basePerStack = d and d.basePerStack or nil,
		baseCount = d and d.baseCount or 0,
		totals = d and d.totals or nil,
		stacksMatter = d and d.stacksMatter or false,
		lastTick = d and d.lastTick or nil,
		lastInstanceID = d and d.lastInstanceID or nil,
		lastSig = d and d.lastSig or nil,
		confidence = "none",
	}
	if override then
		out.confidence = "override"
	elseif d and d.interval and d.rawCount and d.rawCount >= 3 then
		out.confidence = "high"
	elseif d and d.interval then
		out.confidence = "low"
	end
	return out
end

-- Live stacks for a spell from the cached aura set. Returns nil when absent or
-- secret (never guesses).
function learner.LiveStacks(id)
	local auras = ns.api.ReadPlayerAuras()
	for i = 1, #auras do
		local a = auras[i]
		if a.spellID == id and a.sourceUnit == "player" then
			if a.secretStacks then return nil end
			local s = ns.toNumber(a.stacks)
			if s == nil or s < 1 then return 1 end
			return math.floor(s)
		end
	end
	return nil
end

-- Register the combat-log handler and the learning-invalidation events.
function learner.Setup()
	learner.Reset()
	ns.on("COMBAT_LOG_EVENT_UNFILTERED", function(_, ...)
		local count = select("#", ...)
		if count > 0 then
			-- Deliberate legacy path: this client delivers explicit varargs.
			learner.HandleCLEU(ns.pack(...))
		else
			local cleu = ns.api.GetCLEU()
			if cleu then learner.HandleCLEU(cleu) end
		end
	end)
	-- Gear changes invalidate magnitudes only; spec change invalidates all.
	ns.on("PLAYER_EQUIPMENT_CHANGED", function(_, unit)
		if unit == nil or unit == "player" then learner.ResetAmounts() end
	end)
	ns.on("SPELLS_CHANGED", function() learner.ResetAmounts() end)
	ns.on("ACTIVE_TALENT_GROUP_CHANGED", function() learner.Reset() end)
end

-- args is an explicit pack (field 1 timestamp, 2 subevent, ...).
function learner.HandleCLEU(args)
	if type(args) ~= "table" then return end
	local sub = args[2]
	if ns.isSecret(sub) then return end
	if sub ~= "SPELL_PERIODIC_HEAL" then return end

	local playerGUID = ns.api.PlayerGUID()
	if not playerGUID then return end
	local sourceGUID, destGUID = args[4], args[8]
	-- Guard secret source/dest BEFORE any comparison or boolean branch.
	if ns.isSecret(sourceGUID) or ns.isSecret(destGUID) then return end
	if sourceGUID ~= playerGUID or destGUID ~= playerGUID then return end

	local spellID = ns.toNumber(args[12])
	if not spellID or not ns.spells.IsCandidate(spellID) then return end
	local meta = ns.spells.Meta(spellID)
	if not meta then return end

	-- Ownership: only a positively owned current aura may be learned from.
	local auras = ns.api.ReadPlayerAuras()
	local aura
	for i = 1, #auras do
		if auras[i].spellID == spellID and auras[i].sourceUnit == "player" then
			aura = auras[i]
			break
		end
	end
	if not aura then return end -- absent / unknown ownership: never learned

	local instanceID = aura.instanceID
	local sig = aura.expirationTime -- application/expiration signature
	local stacks = 1
	if meta.stacksMatter then
		if aura.secretStacks then
			stacks = nil -- unknown for this tick; skip amount, still time it
		else
			stacks = ns.toNumber(aura.stacks)
			if stacks == nil or stacks < 1 then stacks = 1 end
			stacks = math.floor(stacks)
		end
	end

	local now = ns.now()
	local d = learnedFor(spellID)
	d.stacksMatter = meta.stacksMatter and true or false

	-- Timing is observed for ALL valid owned periodic events. Only same aura
	-- instance AND same application signature may produce an interval, so a
	-- refresh (same instance ID, new expiration) resets the phase and never
	-- contributes a cross-refresh delta.
	if d.lastTick and instanceID and d.lastInstanceID == instanceID and d.lastSig == sig then
		learner.ObserveInterval(spellID, now - d.lastTick)
	end
	d.lastTick = now
	d.lastInstanceID = instanceID or d.lastInstanceID
	d.lastSig = sig

	-- Magnitude is learned ONLY from readable, valid, non-crit, non-absorbed ticks.
	local critical, absorbed = args[18], args[17]
	if ns.isSecret(critical) or ns.isSecret(absorbed) then return end
	if critical then return end
	local absN = ns.toNumber(absorbed)
	if absN and absN > 0 then return end
	if meta.stacksMatter and stacks == nil then return end

	local amount = ns.toNumber(args[15])
	local overheal = ns.toNumber(args[16])
	if not amount then return end
	local total
	if ns.db and ns.db.amountMode == "effective" then
		total = amount + (overheal or 0)
	else
		total = amount -- adapter assumption: amount already includes overheal
	end
	if total <= 0 then return end

	learner.ObserveBase(spellID, total, stacks or 1, meta.approximate)
end
