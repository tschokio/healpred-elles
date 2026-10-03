-- Source fixtures: foreverchanges.pro/spellbook/druid and /de/spellbook/druid,
-- retrieved 2026-10-03, beta 1.60.1.70205. Site values are BASE examples used
-- only in tests; production reads character-specific public client tooltips.
local function env()
	local e = Mocks.NewEnv({ noCLEU = true, build = { "1.60.1", 70205, "2026-10-02", 16001 } })
	e.ns.HandleCommand("approximate on")
	e.ab._predMy:SetValue(Mocks.MakeSecret())
	e.ab._predOther:SetValue(Mocks.MakeSecret())
	Mocks.healAbsorb = Mocks.MakeSecret()
	return e
end
local function aura(id, duration, source)
	Mocks.SetAuras({ { spellId = id, sourceUnit = source or "player", applications = 0,
		duration = duration, expirationTime = Mocks.now + duration, auraInstanceID = id } })
end

T.register("druid: every Forever Rejuvenation and Regrowth rank reads its own periodic total", function()
	local e = env()
	local families = {
		{ ids = {774,1058,1430,2090,2091,3627,8910,9839,9840,9841,25299},
			totals = {32,48,92,128,168,204,284,376,496,644,776}, duration = 12 },
		{ ids = {8936,8938,8939,8940,8941,9750,9856,9857,9858},
			totals = {91,154,224,294,364,476,616,791,994}, duration = 21 },
	}
	for _, family in ipairs(families) do
		for rank, id in ipairs(family.ids) do
			local prefix = family.duration == 21 and "Heals a friendly target for 89 to 103 and another " or "Heals the target for "
			Mocks.descriptions[id] = prefix .. family.totals[rank] .. " over " .. family.duration .. " sec."
			aura(id, family.duration)
			e.ns.overlay.Tick(true)
			assert_near(e.ns.session.lastStatus.hotEstimate, family.totals[rank], 1e-8)
			assert_true(e.ns.overlay.state.frame:IsShown())
		end
	end
end)

T.register("druid: all three Forever Wild Growth ranks use per-player total and labelled average taper", function()
	local e = env()
	local ids, totals = {408120,1238214,1238215}, {336,493,679}
	for i, id in ipairs(ids) do
		Mocks.descriptions[id] = "Heals the target and their party for " .. totals[i] .. " over 7 sec. Party members must be within 43.5 yards of target. The amount healed is applied quickly at first, and slows down as Wild Growth reaches its full duration."
		aura(id, 7)
		e.ns.overlay.Tick(true)
		assert_near(e.ns.session.lastStatus.hotEstimate, totals[i], 1e-8)
		local d = e.ns.learner.GetSpellData(id)
		assert_eq(d.interval, 1)
		assert_true(d.amountSource:match("taper unmodelled") ~= nil)
		Mocks.now = Mocks.now + 3
		e.ns.overlay.Tick(true)
		assert_near(e.ns.session.lastStatus.hotEstimate, totals[i] * 4 / 7, 1e-8)
		Mocks.now = Mocks.now + 4
		e.ns.overlay.Tick(true)
		assert_false(e.ns.overlay.state.frame:IsShown())
	end
	aura(408120, 7, "party1")
	e.ns.overlay.Tick(true)
	assert_false(e.ns.overlay.state.frame:IsShown(), "foreign Wild Growth not counted")
end)

T.register("druid: Tranquility all ranks predict only the player's current channel", function()
	local e = env()
	local ids, ticks = {740,8918,9862,9863}, {91,133,201,285}
	for i, id in ipairs(ids) do
		Mocks.descriptions[id] = "Regenerates all nearby party members within 20 yards for " .. ticks[i] .. " every 2 sec for 10 sec. Druid must channel to maintain the spell."
		Mocks.channel = { id = id, start = Mocks.now * 1000, finish = (Mocks.now + 10) * 1000 }
		-- An aura with the same ID must not double-count the synthetic channel.
		aura(id, 10)
		e.ns.overlay.Tick(true)
		assert_eq(e.ns.session.lastStatus.hotEstimate, ticks[i] * 5)
		Mocks.now = Mocks.now + 2
		e.ns.overlay.Tick(true)
		assert_eq(e.ns.session.lastStatus.hotEstimate, ticks[i] * 4)
		Mocks.channel = nil
		Mocks.Fire("UNIT_SPELLCAST_CHANNEL_STOP", "player")
		e.ns.overlay.Tick()
		assert_false(e.ns.overlay.state.frame:IsShown(), "stale aura cannot survive interrupted channel")
	end
	Mocks.channel = { id = 740, start = Mocks.MakeSecret(), finish = Mocks.MakeSecret() }
	e.ns.overlay.Tick(true)
	assert_false(e.ns.overlay.state.frame:IsShown(), "restricted channel timing is withheld")
end)

T.register("druid: German site wording for Wild Growth Tranquility and Frenzied Regeneration", function()
	local e = env()
	local r = e.ns.estimates.Parse("Heilt das Ziel und seine Gruppenmitglieder innerhalb von 43.5 Metern um ihn herum im Verlauf von 7 Sek. um 336 Gesundheit. Die Heilung wird zunächst schnell und mit zunehmender Dauer von 'Wildwuchs' langsamer angewendet.", "deDE")
	assert_eq(r.amount, 336)
	assert_eq(r.seconds, 7)
	r = e.ns.estimates.Parse("Regeneriert 10 Sek. lang alle 2 Sek. 91 Gesundheit aller Gruppenmitglieder innerhalb von 20 Metern. Der Druide muss diesen Zauber kanalisieren, um ihn aufrechtzuerhalten.", "deDE")
	assert_eq(r.kind, "tick")
	assert_eq(r.amount, 91)
	assert_eq(r.seconds, 2)
	r = e.ns.estimates.Parse("Wandelt 10 Sek. lang bis zu 10 Wut pro Sekunde in Gesundheit um. Jeder Punkt Wut wird in 1% Gesundheit umgewandelt.", "deDE")
	assert_eq(r.kind, "ragePercent")
	assert_eq(r.rageCap, 10)
	assert_eq(r.amount, 1)
end)

T.register("druid: Frenzied Regeneration budgets current rage and effect alias without future rage invention", function()
	local e = env()
	Mocks.descriptions[22842] = "Converts up to 10 Rage per second into health for 10 sec. Each point of Rage is converted into 1% health."
	Mocks.maxHealth, Mocks.rage = 1000, 25
	aura(22845, 10)
	e.ns.overlay.Tick(true)
	assert_eq(e.ns.session.lastStatus.hotEstimate, 250)
	Mocks.SetAuras({
		{ spellId = 22842, sourceUnit = "player", duration = 10, expirationTime = 110, applications = 0, auraInstanceID = 1 },
		{ spellId = 22845, sourceUnit = "player", duration = 10, expirationTime = 110, applications = 0, auraInstanceID = 2 },
	})
	e.ns.overlay.Tick(true)
	assert_eq(e.ns.session.lastStatus.hotEstimate, 250, "cast/effect aliases cannot spend the same rage twice")
	aura(22845, 10)
	Mocks.rage = 12
	Mocks.Fire("UNIT_POWER_UPDATE", "player", "RAGE")
	e.ns.overlay.Tick()
	assert_eq(e.ns.session.lastStatus.hotEstimate, 120)
	Mocks.rage = Mocks.MakeSecret()
	Mocks.Fire("UNIT_POWER_UPDATE", "player", "RAGE")
	e.ns.overlay.Tick()
	assert_false(e.ns.overlay.state.frame:IsShown())
	assert_true(e.ns.session.lastStatus.reason:match("rage or maximum health restricted") ~= nil)
	e.ns.HandleCommand("amount 22845 80")
	e.ns.overlay.Tick()
	assert_eq(e.ns.session.lastStatus.hotEstimate, 800, "explicit manual amount bypasses resource formula")
end)

T.register("druid: non-periodic spells are never treated as future healing", function()
	local e = env()
	for _, id in ipairs({5185,18562,437138,20484,29166,8946,2893,1126,5229,8921}) do
		assert_nil(e.ns.spells.Meta(id))
		aura(id, 10)
		e.ns.overlay.Tick(true)
		assert_false(e.ns.overlay.state.frame:IsShown())
	end
end)

T.register("druid: Tranquility channel updates revise duration and ignore unrelated channels", function()
	local e = env()
	Mocks.descriptions[740] = "Regenerates nearby party members for 91 every 2 sec for 10 sec."
	Mocks.channel = { id = 740, start = 100000, finish = 110000 }
	e.ns.overlay.Tick(true)
	assert_eq(e.ns.session.lastStatus.hotEstimate, 455)
	Mocks.channel.finish = 106000
	Mocks.Fire("UNIT_SPELLCAST_CHANNEL_UPDATE", "player")
	e.ns.overlay.Tick()
	assert_eq(e.ns.session.lastStatus.hotEstimate, 273)
	Mocks.channel.id = 16914 -- Hurricane is damage, not healing
	Mocks.Fire("UNIT_SPELLCAST_CHANNEL_START", "player")
	e.ns.overlay.Tick()
	assert_false(e.ns.overlay.state.frame:IsShown())
	Mocks.channel.id = Mocks.MakeSecret()
	assert_nil(e.ns.api.ReadPlayerChannel())
	assert_eq(e.ns.eventFrame._unitEvents.UNIT_SPELLCAST_CHANNEL_UPDATE, "player")
end)

T.register("druid: resource healing clamps its budget and fails closed on secret maximum health", function()
	local e = env()
	Mocks.descriptions[22842] = "Converts up to 10 Rage per second into health for 10 sec. Each point of Rage is converted into 1% health."
	Mocks.maxHealth, Mocks.rage = 1000, 100
	aura(22842, 10)
	Mocks.now = 109
	e.ns.overlay.Tick(true)
	assert_eq(e.ns.session.lastStatus.hotEstimate, 100, "only one 10-rage conversion remains")
	Mocks.maxHealth = Mocks.MakeSecret()
	e.ns.overlay.Tick(true)
	assert_false(e.ns.overlay.state.frame:IsShown())
	assert_true(e.ns.session.lastStatus.reason:match("maximum health restricted") ~= nil)
	Mocks.maxHealth, Mocks.rage = 1000, 0
	e.ns.overlay.Tick(true)
	assert_false(e.ns.overlay.state.frame:IsShown(), "no assumed future rage healing")
	local st = e.ns.overlay.state
	st.paintRequested = false
	Mocks.Fire("UNIT_POWER_UPDATE", "player", "MANA")
	assert_false(st.paintRequested, "mana regeneration does not request a rage-model paint")
	Mocks.Fire("UNIT_POWER_UPDATE", "target", "RAGE")
	assert_false(st.paintRequested)
end)
