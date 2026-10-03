-- EllesmereUI_HoTPrediction / Learner.lua
-- Observes SPELL_PERIODIC_HEAL from the combat log to learn two things per
-- spell/rank, session only:
--   * the tick interval (from consecutive same-aura ticks)
--   * the per-stack tick amount (average of recent non-crit samples)
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
local MAX_BASE_SAMPLES = 10
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
			intervalHist = {},   -- [bucket] = count
			rawCount = 0,
			baseSamples = {},    -- ring of per-stack amounts
			basePerStack = nil,
			baseCount = 0,
			lastTick = nil,
			lastInstanceID = nil,
		}
		L[id] = d
	end
	return d
end

function learner.Reset()
	ns.session.learned = {}
	ns.session.lastTicksAt = {}
end

-- Merge learned session data with an explicit user interval override.
-- Returns { interval, basePerStack, baseCount, confidence, lastTick, lastInstanceID }
function learner.GetSpellData(id)
	local d = ns.session.learned and ns.session.learned[id]
	local override = ns.spells.IntervalOverride(id)
	local out = {
		interval = override or (d and d.interval) or nil,
		basePerStack = d and d.basePerStack or nil,
		baseCount = d and d.baseCount or 0,
		lastTick = d and d.lastTick or nil,
		lastInstanceID = d and d.lastInstanceID or nil,
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

function learner.ObserveInterval(id, delta, instanceID)
	local d = learnedFor(id)
	if not delta or delta < MIN_INTERVAL_GAP or delta > MAX_INTERVAL_GAP then return end
	-- Do not learn across a refresh: a changed aura instance starts a new grid.
	if instanceID and d.lastInstanceID and instanceID ~= d.lastInstanceID then return end
	local b = bucketOf(delta)
	d.intervalHist[b] = (d.intervalHist[b] or 0) + 1
	d.rawCount = (d.rawCount or 0) + 1
	-- Pick the most common bucket; ties resolve to the smaller interval.
	local best, bestCount
	for value, count in pairs(d.intervalHist) do
		if count > (bestCount or 0) or (count == bestCount and best and value < best) then
			best, bestCount = value, count
		end
	end
	d.interval = best
end

function learner.ObserveBase(id, total, stacks)
	local d = learnedFor(id)
	local n = ns.toNumber(total)
	local s = ns.toNumber(stacks) or 1
	if not n or n <= 0 or s < 1 then return end
	local perStack = n / s
	local samples = d.baseSamples
	samples[#samples + 1] = perStack
	if #samples > MAX_BASE_SAMPLES then table.remove(samples, 1) end
	local sum = 0
	for i = 1, #samples do sum = sum + samples[i] end
	d.basePerStack = sum / #samples
	d.baseCount = #samples
end

-- Live stacks for a spell, read from the current aura set. Returns nil when the
-- aura is not present or its stack count is secret.
function learner.LiveStacks(id)
	local auras = ns.api.ReadPlayerAuras()
	for i = 1, #auras do
		local a = auras[i]
		if a.spellID == id then
			if a.secretStacks then return nil end
			return ns.toNumber(a.stacks) or 1
		end
	end
	return nil
end

-- Register the combat-log handler.
function learner.Setup()
	learner.Reset()
	ns.on("COMBAT_LOG_EVENT_UNFILTERED", function(_, ...)
		learner.HandleCLEU(...)
	end)
end

function learner.HandleCLEU(timestamp, sub, ...)
	local args = { ... }
	local function field(n)
		if n == 1 then return timestamp end
		if n == 2 then return sub end
		return args[n - 2]
	end
	if sub ~= "SPELL_PERIODIC_HEAL" then return end

	local playerGUID = ns.api.PlayerGUID()
	if not playerGUID then return end
	local sourceGUID = field(4)
	local destGUID = field(8)
	if sourceGUID ~= playerGUID or destGUID ~= playerGUID then return end

	local spellID = ns.toNumber(field(12))
	if not spellID or not ns.spells.IsCandidate(spellID) then return end

	local critical = field(18)
	if critical then return end -- never learn from crits

	local absorbed = ns.toNumber(field(17))
	if absorbed and absorbed > 0 then return end -- avoid inflating via unknown absorb

	local amount = ns.toNumber(field(15))
	local overheal = ns.toNumber(field(16))
	if not amount then return end
	local total
	if ns.db and ns.db.amountMode == "effective" then
		total = amount + (overheal or 0)
	else
		total = amount -- adapter assumption: amount already includes overheal
	end
	if total <= 0 then return end

	local now = ns.now()
	local auras = ns.api.ReadPlayerAuras()
	local instanceID, stacks
	for i = 1, #auras do
		if auras[i].spellID == spellID then
			instanceID = auras[i].instanceID
			stacks = auras[i].secretStacks and nil or (ns.toNumber(auras[i].stacks) or 1)
			break
		end
	end

	local d = learnedFor(spellID)
	local prev = d.lastTick
	local prevInstance = d.lastInstanceID
	if prev and prevInstance and instanceID and prevInstance == instanceID then
		learner.ObserveInterval(spellID, now - prev, instanceID)
	end
	learner.ObserveBase(spellID, total, stacks or 1)

	d.lastTick = now
	d.lastInstanceID = instanceID or prevInstance
end
