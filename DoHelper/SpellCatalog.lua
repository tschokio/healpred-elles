-- Class-organized, on-demand catalog. Runtime IDs are authoritative; the
-- spellbook review adds icons and honest limitations, not healing constants.
local _, ns = ...
ns.catalogClasses = {
	{ key = "WARRIOR", name = "Warrior", count = 42, color = { 0.78, 0.61, 0.43 } },
	{ key = "HUNTER", name = "Hunter", count = 59, color = { 0.67, 0.83, 0.45 } },
	{ key = "MAGE", name = "Mage", count = 60, color = { 0.41, 0.8, 0.94 } },
	{ key = "ROGUE", name = "Rogue", count = 57, color = { 1, 0.96, 0.41 } },
	{ key = "PRIEST", name = "Priest", count = 57, color = { 1, 1, 1 } },
	{ key = "WARLOCK", name = "Warlock", count = 56, color = { 0.58, 0.51, 0.79 } },
	{ key = "PALADIN", name = "Paladin", count = 56, color = { 0.96, 0.55, 0.73 } },
	{ key = "DRUID", name = "Druid", count = 60, color = { 1, 0.49, 0.04 } },
	{ key = "SHAMAN", name = "Shaman", count = 56, color = { 0, 0.44, 0.87 } },
	{ key = "CUSTOM", name = "General / custom", color = { 0.7, 0.7, 0.7 } },
}
local families = {
	Rejuvenation = { "DRUID", "Rejuvenation", "spell_nature_rejuvenation", "Remaining owned HoT ticks on yourself." },
	Regrowth = { "DRUID", "Regrowth", "spell_nature_resistnature", "HoT portion only; initial direct heal excluded." },
	WildGrowth = { "DRUID", "Wild Growth", "ability_druid_flourish", "Per-player periodic total; declining taper approximated by average ticks." },
	Tranquility = { "DRUID", "Tranquility", "spell_nature_tranquility", "Your own active channel; clears on cancellation or channel end." },
	FrenziedRegeneration = { "DRUID", "Frenzied Regeneration", "ability_bullrush", "Only current readable Rage and maximum health; no future Rage invented." },
	Lifebloom = { "DRUID", "Lifebloom", "inv_misc_herb_felblossom", "Candidate only: exact stack-specific manual/observed totals. Bloom excluded; not established in Forever." },
	Germination = { "DRUID", "Germination", "spell_nature_rejuvenation", "Candidate only: manual/observed ticks; not established in Forever." },
	Renew = { "PRIEST", "Renew", "spell_holy_renew", "Remaining owned HoT ticks on yourself." },
	LightwellRenew = { "PRIEST", "Lightwell Renew", "spell_holy_summonlightwell", "Applied healing aura only, not the summon. Requires player ownership and manual/observed cadence or an explicit tick tooltip; removal stops prediction." },
	Riptide = { "SHAMAN", "Riptide", "spell_nature_riptide", "Periodic portion only; initial direct heal and Chain Heal bonus excluded." },
	DrainLife = { "WARLOCK", "Drain Life", "spell_shadow_lifedrain02", "Approximate mode only: your actual active channel. Damage, resistance and absorption can reduce healing." },
	SiphonLife = { "WARLOCK", "Siphon Life", "spell_shadow_requiem", "Approximate mode only: owned debuff on the current living hostile target. Switching target hides it. Damage/resists/absorbs unverified." },
	DevouringPlague = { "PRIEST", "Devouring Plague", "spell_shadow_blackplague", "Approximate mode only: owned debuff on current living hostile target. Damage-dependent healing, not guaranteed incoming healing." },
}
local queue = {
	Maul = { "DRUID", "ability_druid_maul" },
	["Heroic Strike"] = { "WARRIOR", "ability_rogue_ambush" },
	Cleave = { "WARRIOR", "ability_warrior_cleave" },
	["Raptor Strike"] = { "HUNTER", "ability_meleedamage" },
}
-- Reviewed but deliberately not represented as scheduled player healing/queues.
local deferred = {
	{ "WARRIOR", "Bloodthirst / Victory Rush", "spell_nature_bloodlust", "Not a HoT", "Forever Bloodthirst grants movement speed, not Classic healing charges. Victory Rush heals instantly. Neither queues the next swing." },
	{ "HUNTER", "Mend Pet", "ability_hunter_mendpet", "Pet healing excluded", "Channels healing to your pet, not your player frame. Player-only HoT prediction cannot represent it." },
	{ "MAGE", "No scheduled health HoTs or next-swing abilities", "classicon_mage", "Reviewed", "All 60 entries reviewed. Damage spells, shields, mana regeneration and food creation are not player HoTs or queued attacks." },
	{ "ROGUE", "No scheduled health HoTs or next-swing abilities", "classicon_rogue", "Reviewed", "All 57 entries reviewed. Instant strikes, poisons and weapon procs are not queued next-swing abilities." },
	{ "PRIEST", "Contingency Plan", "spell_holy_powerwordshield", "Needs triggered aura IDs", "The 30-second ward is not a 15-second healing aura. Actual triggered healing IDs/cadence must be verified before automatic support." },
	{ "PRIEST", "Penance", "spell_holy_penance", "Recipient tracking needed", "Can damage an enemy or heal another player. A channel alone does not prove the player is receiving it; left to native prediction." },
	{ "PRIEST", "Prayer of Mending / Vampiric Embrace", "spell_holy_prayerofmendingtga", "Conditional, not scheduled", "Future damage/procs are unknown. No healing invented before a trigger; Dark Sacrifice consumes health rather than heals." },
	{ "WARLOCK", "Demon Skin / Demon Armor", "spell_shadow_ragingscream", "Passive regeneration excluded", "Long-duration stat regeneration is not a finite HoT. Forecasting the whole 30-minute buff would fill the health bar misleadingly." },
	{ "WARLOCK", "Demonic Sacrifice", "spell_shadow_psychicscream", "Needs effect identity", "The summon-sacrifice cast is not the healing aura. Forever changed which demon grants health regeneration; actual effect IDs must be verified." },
	{ "WARLOCK", "Health Funnel", "spell_shadow_lifedrain", "Pet healing excluded", "Channels health to your pet, not your player frame." },
	{ "PALADIN", "Holy Strike / seals / Light's Vigil", "classicon_paladin", "No timed HoT or queue", "Holy Strike explicitly attacks instantly. Seals and Light's Vigil are attack/trigger-dependent; direct healing remains native." },
	{ "SHAMAN", "Healing Stream Totem", "inv_spear_04", "Totem tracking needed", "Requires own totem identity, remaining lifetime and readable player range. The summon or persistent buff alone is insufficient." },
}

function ns.CatalogIDs(ids)
	local values = {}
	for _, id in ipairs(ids) do values[#values + 1] = tostring(id) end
	return table.concat(values, ", ")
end

function ns.GetSpellCatalog()
	local groups, byClass = {}, {}
	for _, class in ipairs(ns.catalogClasses) do
		local g = { key = class.key, name = class.name, color = class.color, count = class.count, rows = {} }
		groups[#groups + 1], byClass[class.key] = g, g
	end
	local rows, all = {}, {}
	for id in pairs(ns.spells.BASE) do all[id] = true end
	for id in pairs(ns.db.extraSpells) do all[id] = true end
	for id in pairs(all) do
		local meta = ns.spells.Meta(id)
		local source = meta or ns.db.extraSpells[id] or ns.spells.BASE[id]
		local custom = ns.db.extraSpells[id] ~= nil
		local f = not custom and families[source.family]
		local key = (custom and "custom:" or "heal:") .. (custom and (source.name or tostring(id)) or source.family)
		if not rows[key] then
			local r = { key = key, name = f and f[2] or source.name or tostring(id), ids = {}, disabled = {},
				class = f and f[1] or "CUSTOM", icon = f and f[3] or "inv_misc_book_11",
				status = custom and "User-added candidate" or (source.lifeDrain and "Approximate life drain"
					or (source.tooltipSupport and "HoT - cadence required") or (source.foreverInterval and "HoT prediction") or "Manual / observation only"),
				note = f and f[4] or "User-added candidate; manual calibration/observation required." }
			rows[key] = r
			byClass[r.class].rows[#byClass[r.class].rows + 1] = r
		end
		local ids = meta and rows[key].ids or rows[key].disabled
		ids[#ids + 1] = id
	end
	local queueEntries = {}
	for id, name in pairs(ns.queuedSwing.baseSpells) do queueEntries[id] = name end
	for id, name in pairs(ns.queuedSwing.spells) do queueEntries[id] = name end
	for id, name in pairs(queueEntries) do
		local key = "queue:" .. (ns.db.extraQueueSpells[id] and ("custom:" .. id) or name)
		if not rows[key] then
			local f = not ns.db.extraQueueSpells[id] and queue[name]
			local r = { key = key, class = f and f[1] or "CUSTOM", name = name, icon = f and f[2] or "inv_misc_book_11",
				status = name == "Throw" and "Ranged current-action indicator" or "Next-swing queue",
				note = (name == "Throw" and "Throw is normally ranged, not a melee queue. " or "") .. "Real readable current-action/current-spell state only. No border for failed attempts or unavailable state.", ids = {}, disabled = {} }
			rows[key] = r; byClass[r.class].rows[#byClass[r.class].rows + 1] = r
		end
		local list = ns.queuedSwing.spells[id] and rows[key].ids or rows[key].disabled
		list[#list + 1] = id
	end
	for i, d in ipairs(deferred) do
		local r = { key = "review:" .. i, name = d[2], class = d[1], icon = d[3], status = d[4], note = d[5], ids = {}, disabled = {}, deferred = true }
		byClass[r.class].rows[#byClass[r.class].rows + 1] = r
	end
	for _, g in ipairs(groups) do
		for _, r in ipairs(g.rows) do table.sort(r.ids); table.sort(r.disabled) end
		table.sort(g.rows, function(a, b)
			if a.deferred ~= b.deferred then return not a.deferred end
			if a.name ~= b.name then return a.name < b.name end
			return a.key < b.key
		end)
	end
	return groups
end

function ns.BuildSpellCatalog()
	local lines = { "SPELLBOOK COVERAGE BY CLASS", "Reviewed 503 entries across all nine classes: ForeverChanges 1.60.1.70205 (2026-10-04).",
		"Support catalog, not learned/known spells. Other players' HoTs are NOT implemented.",
		"HoTs require readable ownership/timing. Life drains require Approximate mode; damage-dependent healing is unverified.",
		"CANDIDATES: MANUAL / OBSERVATION ONLY remain labelled below." }
	for _, g in ipairs(ns.GetSpellCatalog()) do
		lines[#lines + 1] = "\n" .. g.name:upper() .. (g.count and (" - " .. g.count .. " spellbook entries reviewed") or "")
		if #g.rows == 0 then lines[#lines + 1] = "No registered custom spells." end
		for _, r in ipairs(g.rows) do
			lines[#lines + 1] = r.name .. " [" .. r.status .. "]\n  " .. r.note
			if #r.ids > 0 then lines[#lines + 1] = "  IDs: " .. ns.CatalogIDs(r.ids) end
			if #r.disabled > 0 then lines[#lines + 1] = "  Disabled by your settings: " .. ns.CatalogIDs(r.disabled) end
		end
	end
	return ns.StripFormatting(table.concat(lines, "\n"))
end
