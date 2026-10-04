-- DoHelper / Spells.lua
-- Candidate spell/rank database. The verified Forever preset IDs below are
-- *candidates only*: presence in the client is decided at runtime by observed
-- auras / combat log, never inferred from this catalog.
--
-- No tick constants are stored here. Conservative mode uses observation/manual
-- data; Estimates.lua owns opt-in tooltip and cadence assumptions.

local addonName, ns = ...
local spells = {}
ns.spells = spells

-- Verified list from EllesmereUI/EllesmereUI_BuffPresets.lua (Forever presets).
local BASE = {}
local function addFamily(family, ids, opts)
	opts = opts or {}
	for _, id in ipairs(ids) do
		BASE[id] = {
			name = family,
			family = family,
			stacksMatter = opts.stacksMatter and true or false,
			approximate = opts.approximate and true or false,
			base = true,
			foreverInterval = opts.foreverInterval,
			channel = opts.channel,
			resourceHealing = opts.resourceHealing,
			tooltipSpellID = opts.tooltipSpellID,
			tooltipSupport = opts.tooltipSupport,
			targetDrain = opts.targetDrain,
			lifeDrain = opts.lifeDrain,
		}
	end
end

addFamily("Rejuvenation", { 774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299 }, { foreverInterval = 3 })
addFamily("Regrowth", { 8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858 }, { foreverInterval = 3 })
addFamily("Renew", { 139, 6074, 6075, 6076, 6077, 6078, 10927, 10928, 10929, 25315 }, { foreverInterval = 3 })
addFamily("Riptide", { 408521, 1239242, 1239243 }, { foreverInterval = 3 })
-- ForeverChanges spellbook, beta 1.60.1.70205 (2026-10-03). IDs, not
-- magnitudes: healing comes from live public tooltips, including gear bonuses.
addFamily("WildGrowth", { 408120, 1238214, 1238215 }, { approximate = true, foreverInterval = 1 })
addFamily("Tranquility", { 740, 8918, 9862, 9863 }, { channel = true, foreverInterval = 2 })
addFamily("FrenziedRegeneration", { 22842, 22845 },
	{ resourceHealing = true, foreverInterval = 1, tooltipSpellID = 22842 })
-- Candidate-only IDs observed in retail/general buff managers; NOT proof they
-- exist on the installed client. Runtime gating decides.
addFamily("Lifebloom", { 33763 }, { stacksMatter = true })
addFamily("Germination", { 155777 })
addFamily("WildGrowth", { 48438 }, { approximate = true })

-- Reviewed ForeverChanges spellbooks 2026-10-04, build 1.60.1.70205.
-- Lightwell's summon is NOT a healing aura; only the applied Renew counts.
-- Its cadence is not documented: require observed/manual or explicit tick text.
addFamily("LightwellRenew", { 7001 }, { tooltipSupport = true, tooltipSpellID = 724 })
addFamily("LightwellRenew", { 27873 }, { tooltipSupport = true, tooltipSpellID = 27870 })
addFamily("LightwellRenew", { 27874 }, { tooltipSupport = true, tooltipSpellID = 27871 })
-- Life drains are opt-in rough estimates, never guaranteed incoming healing.
-- Channel state / owned current-target debuffs are required, not cast attempts.
addFamily("DrainLife", { 689, 699, 709, 7651, 11699, 11700 },
	{ channel = true, lifeDrain = true, approximate = true, foreverInterval = 1 })
addFamily("SiphonLife", { 18265, 18879, 18880, 18881 },
	{ targetDrain = true, lifeDrain = true, approximate = true, foreverInterval = 3 })
addFamily("DevouringPlague", { 2944, 19276, 19277, 19278, 19279, 19280 },
	{ targetDrain = true, lifeDrain = true, approximate = true, foreverInterval = 3 })

spells.BASE = BASE

function spells.Meta(id)
	if type(id) ~= "number" then return nil end
	local db = ns.db
	if db and db.removedSpells and db.removedSpells[id] then return nil end
	if db and db.extraSpells and db.extraSpells[id] then
		local e = db.extraSpells[id]
		return { name = e.name or ("spell " .. id), family = e.family or "custom", stacksMatter = false, approximate = false, extra = true }
	end
	return BASE[id]
end

function spells.IsCandidate(id)
	return spells.Meta(id) ~= nil
end

-- Explicit user calibration only. Returns nil when nothing was configured.
function spells.IntervalOverride(id)
	local db = ns.db
	if db and db.intervalOverrides then
		return ns.toNumber(db.intervalOverrides[id])
	end
	return nil
end

-- Explicit user amount calibration for an exact stack count. This is separate
-- from (and authoritative over) learned magnitudes. Returns a positive number
-- or nil. Non-stacking families are always keyed at stack 1.
function spells.AmountOverride(id, stacks)
	local db = ns.db
	local ov = db and db.amountOverrides and db.amountOverrides[id]
	if type(ov) ~= "table" then return nil end
	local s = ns.toNumber(stacks)
	if s == nil then s = 1 end
	s = math.floor(s)
	if s < 1 then s = 1 end
	local v = ns.toNumber(ov[s])
	if v and v > 0 then return v end
	return nil
end

function spells.Describe(id)
	local meta = spells.Meta(id)
	if not meta then return nil end
	return meta.name or meta.family
end
