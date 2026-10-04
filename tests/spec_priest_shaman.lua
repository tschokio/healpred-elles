-- ForeverChanges English/German spellbook fixtures, beta 1.60.1.70205,
-- retrieved 2026-10-03. Runtime never uses these base amounts as constants.
local function env()
	local e = Mocks.NewEnv({ noCLEU = true, build = { "1.60.1", 70205, "2026-10-02", 16001 } })
	e.ns.HandleCommand("approximate on")
	e.ab._predMy:SetValue(Mocks.MakeSecret())
	e.ab._predOther:SetValue(Mocks.MakeSecret())
	Mocks.healAbsorb = Mocks.MakeSecret()
	return e
end
local function aura(id, source)
	Mocks.SetAuras({ { spellId = id, sourceUnit = source or "player", applications = 0,
		duration = 15, expirationTime = Mocks.now + 15, auraInstanceID = id } })
end

T.register("priest: every Forever Renew rank uses exact live tooltip and five remaining ticks", function()
	local e = env()
	local ids = {139,6074,6075,6076,6077,6078,10927,10928,10929,25315}
	local totals = {45,75,125,160,205,270,370,510,670,830}
	for i, id in ipairs(ids) do
		Mocks.descriptions[id] = "Heals the target of " .. totals[i] .. " damage over 15 sec."
		aura(id)
		e.ns.overlay.Tick(true)
		assert_eq(e.ns.session.lastStatus.hotEstimate, totals[i])
		assert_eq(e.ns.learner.GetSpellData(id).interval, 3)
		Mocks.now = Mocks.now + 3
		e.ns.overlay.Tick(true)
		assert_near(e.ns.session.lastStatus.hotEstimate, totals[i] * 4 / 5, 1e-8)
		Mocks.now = Mocks.now + 12
		e.ns.overlay.Tick(true)
		assert_false(e.ns.overlay.state.frame:IsShown())
	end
end)

T.register("shaman: all Forever Riptide ranks exclude direct heal and Chain Heal multiplier", function()
	local e = env()
	local ids, totals = {408521,1239242,1239243}, {445,575,805}
	for i, id in ipairs(ids) do
		Mocks.descriptions[id] = "Heals a friendly target for 486 to 534, an additional " .. totals[i] .. " over 15 sec, and increases the effectiveness of your Chain Heal casts directly on that target by 25%."
		aura(id)
		e.ns.overlay.Tick(true)
		assert_eq(e.ns.session.lastStatus.hotEstimate, totals[i])
		Mocks.now = Mocks.now + 6
		e.ns.overlay.Tick(true)
		assert_near(e.ns.session.lastStatus.hotEstimate, totals[i] * 3 / 5, 1e-8)
	end
end)

T.register("priest/shaman: German Renew and Riptide website wording renders", function()
	local e = env()
	GetLocale = function() return "deDE" end
	Mocks.descriptions[139] = "Heilt das Ziel 15 Sek. lang um 45 Schadenspunkt(e)."
	Mocks.descriptions[408521] = "Heilt ein befreundetes Ziel um 486 bis 534 Gesundheit und im Verlauf von 15 Sek. um weitere 445 Gesundheit. Erhöht die Effektivität Eurer Einsätze von 'Kettenheilung', die direkt auf das Ziel gewirkt werden, um 25%."
	for _, id in ipairs({139,408521}) do
		aura(id)
		e.ns.overlay.Tick(true)
		assert_eq(e.ns.session.lastStatus.hotEstimate, id == 139 and 45 or 445)
		assert_true(e.ns.overlay.state.frame:IsShown())
	end
end)

T.register("priest/shaman: public bonus-inclusive aura tooltip overrides spell description", function()
	local e = env()
	Mocks.descriptions[139] = "Heals the target of 45 damage over 15 sec."
	C_TooltipInfo = { GetUnitAuraByAuraInstanceID = function()
		return { lines = { { leftText = "Heals 150 over 15 sec." } } }
	end }
	aura(139)
	e.ns.overlay.Tick(true)
	assert_eq(e.ns.session.lastStatus.hotEstimate, 150)
	GetSpellBonusHealing = function() error("must not add healing power twice") end
	assert_eq(e.ns.learner.GetSpellData(139, e.ns.api.ReadPlayerAuras()[1]).basePerStack, 30)
end)

T.register("priest/shaman: foreign ownership secret timing removal and manual precedence", function()
	local e = env()
	for _, id in ipairs({139,408521}) do
		Mocks.descriptions[id] = "Heals 150 over 15 sec."
		aura(id, "party1")
		e.ns.overlay.Tick(true)
		assert_false(e.ns.overlay.state.frame:IsShown())
		Mocks.SetAuras({ { spellId = id, sourceUnit = "player", applications = 0,
			duration = Mocks.MakeSecret(), expirationTime = Mocks.MakeSecret(), auraInstanceID = id } })
		e.ns.overlay.Tick(true)
		assert_false(e.ns.overlay.state.frame:IsShown())
		aura(id)
		e.ns.HandleCommand("amount " .. id .. " 40")
		e.ns.overlay.Tick(true)
		assert_eq(e.ns.session.lastStatus.hotEstimate, 200)
		Mocks.SetAuras({})
		e.ns.overlay.Tick(true)
		assert_false(e.ns.overlay.state.frame:IsShown())
	end
end)

T.register("priest/shaman/paladin: deferred triggers summons direct heals and procs stay excluded", function()
	local e = env()
	for _, id in ipairs({1277462,1277634,1277638,1277639,1277640,724,27870,27871,
		402174,1240720,1240721,1316995,401859,1240826,1240827,
		5394,6375,6377,10462,10463,635,633,19750,20165,20349,1310911,1311015}) do
		assert_nil(e.ns.spells.Meta(id))
		aura(id)
		e.ns.overlay.Tick(true)
		assert_false(e.ns.overlay.state.frame:IsShown())
	end
end)
