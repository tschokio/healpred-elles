-- On-demand, read-only catalog of implemented behavior, not known/active spells.
local _, ns = ...
local names = { WildGrowth = "Wild Growth", FrenziedRegeneration = "Frenzied Regeneration" }
local notes = {
	Rejuvenation = "Remaining self-cast HoT ticks; public tooltip or manual/observed healing.",
	Regrowth = "HoT portion only; initial direct heal excluded.",
	Renew = "Remaining self-cast HoT ticks; public tooltip or manual/observed healing.",
	Riptide = "Periodic portion only; initial heal and Chain Heal bonus excluded.",
	WildGrowth = "Per-player periodic total; average ticks, declining taper not modelled.",
	Tranquility = "Player healing during your own readable active channel; stops on channel end.",
	FrenziedRegeneration = "Current readable Rage and maximum health only; no future Rage assumed. 22845 is a candidate effect alias for 22842.",
	Lifebloom = "Exact stack-specific tick totals; final bloom excluded.",
	Germination = "Remaining self-cast periodic healing only.",
}
local function idsText(ids)
	table.sort(ids)
	local strings = {}
	for _, id in ipairs(ids) do strings[#strings + 1] = tostring(id) end
	return table.concat(strings, ", ")
end

function ns.BuildSpellCatalog()
	local lines = {
		"IMPLEMENTED SPELLS / RANK IDs",
		"This is a support catalog, not a list of spells you know or currently have active.",
		"HEALING: your own effects on yourself only. Other players' HoTs are NOT implemented.",
		"Tooltip estimates require Approximate mode and readable aura ownership/timing. Conservative mode needs manual/observed data and readable native values.",
		"",
		"HEALING WITH BUILT-IN TOOLTIP SUPPORT",
	}
	local groups, order = {}, {}
	local all = {}
	for id in pairs(ns.spells.BASE) do all[id] = true end
	for id in pairs(ns.db.extraSpells) do all[id] = true end
	for id in pairs(all) do
		local meta = ns.spells.Meta(id)
		-- Keep disabled built-ins visible, but label them rather than implying active support.
		local source = meta or ns.db.extraSpells[id] or ns.spells.BASE[id]
		local section = (meta and meta.extra or ns.db.extraSpells[id]) and "custom"
			or (source.foreverInterval and "tooltip" or "candidate")
		local family = source.family or "custom"
		local name = section == "custom" and (source.name or ("spell " .. id)) or (names[family] or family)
		local key = section .. ":" .. name
		if not groups[key] then
			groups[key] = { name = name, family = family, section = section, ids = {}, disabled = {} }
			order[#order + 1] = key
		end
		local list = meta and groups[key].ids or groups[key].disabled
		list[#list + 1] = id
	end
	table.sort(order)
	local function section(which)
		local count = 0
		for _, key in ipairs(order) do
			local g = groups[key]
			if g.section == which then
				count = count + 1
				lines[#lines + 1] = g.name
				if #g.ids > 0 then lines[#lines + 1] = "  IDs: " .. idsText(g.ids) end
				if #g.disabled > 0 then lines[#lines + 1] = "  Disabled by your settings: " .. idsText(g.disabled) end
				lines[#lines + 1] = "  " .. (which == "custom" and "User-added candidate; manual calibration/observation required."
					or notes[g.family] or "Manual calibration/observation required.")
				lines[#lines + 1] = ""
			end
		end
		return count
	end
	section("tooltip")
	lines[#lines + 1] = "CANDIDATES: MANUAL / OBSERVATION ONLY"
	lines[#lines + 1] = "No built-in tooltip estimate for these IDs; availability in Forever is not established."
	section("candidate")
	lines[#lines + 1] = "USER-ADDED CANDIDATES"
	if section("custom") == 0 then lines[#lines + 1] = "None registered." end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "NEXT-SWING QUEUE BORDERS"
	lines[#lines + 1] = "Real readable current-action/current-spell state only; no cast-attempt prediction."
	local queueGroups = {}
	for id, family in pairs(ns.queuedSwing.spells) do
		queueGroups[family] = queueGroups[family] or {}
		queueGroups[family][#queueGroups[family] + 1] = id
	end
	for _, family in ipairs({ "Maul", "Heroic Strike", "Cleave" }) do
		lines[#lines + 1] = family .. "\n  IDs: " .. idsText(queueGroups[family] or {})
	end
	lines[#lines + 1] = ""
	lines[#lines + 1] = "NOT IMPLEMENTED AS EXTRA HEALING"
	lines[#lines + 1] = "Other players' HoTs; direct heals (left to native prediction); Lifebloom bloom; conditional/proc heals; Healing Stream Totem, Lightwell, Penance recipient tracking, Prayer of Mending and Contingency Plan."
	return ns.StripFormatting(table.concat(lines, "\n"))
end
