local function env()
	return Mocks.NewEnv({ noCLEU = true, build = { "1.60.1", 70205, "2026-10-02", 16001 } })
end

T.register("estimates: English total and Regrowth direct heal separation", function()
	local e = env()
	local r = e.ns.estimates.Parse("Heals 48 over 12 seconds.", "enUS")
	assert_eq(r.amount, 48)
	assert_eq(r.seconds, 12)
	r = e.ns.estimates.Parse("Heals a friendly target for 93 to 107 and another 98 over 21 sec.", "enUS")
	assert_eq(r.amount, 98)
	assert_eq(r.kind, "total")
end)

T.register("estimates: tick tooltip, German total, and restricted strings", function()
	local e = env()
	local r = e.ns.estimates.Parse("Heals 12 health every 3 sec.", "enUS")
	assert_eq(r.kind, "tick")
	assert_eq(r.amount, 12)
	r = e.ns.estimates.Parse("Heilt das Ziel im Verlauf von 12 Sek. um 48.", "deDE")
	assert_eq(r.amount, 48)
	assert_eq(r.seconds, 12)
	assert_nil(e.ns.estimates.Parse(Mocks.MakeSecret(), "enUS"))
	assert_nil(e.ns.estimates.Parse("Heals 48 over 12 seconds", "frFR"))
	assert_nil(e.ns.estimates.Parse("Heals 40 to 48 over 12 sec", "enUS"))
end)

T.register("estimates: actual auras render with secret incoming and absorb in opt-in mode", function()
	local e = env()
	Mocks.now = 0
	Mocks.descriptions[774] = "Heals 48 over 12 seconds."
	Mocks.descriptions[8936] = "Heals 93 to 107 and another 98 over 21 seconds."
	Mocks.SetAuras({
		{ spellId = 774, applications = 0, duration = 12, expirationTime = 12, sourceUnit = "player", auraInstanceID = 1 },
		{ spellId = 8936, applications = 0, duration = 21, expirationTime = 21, sourceUnit = "player", auraInstanceID = 2 },
	})
	Mocks.healAbsorb = Mocks.MakeSecret()
	e.ab._predMy:SetValue(Mocks.MakeSecret())
	e.ab._predOther:SetValue(Mocks.MakeSecret())
	e.ns.HandleCommand("approximate on")
	e.ns.overlay.Tick(true)
	assert_eq(e.ns.session.lastStatus.hotEstimate, 146)
	assert_true(e.ns.overlay.state.frame:IsShown())
	assert_true(e.ns.session.lastStatus.reason:match("overlap unverified") ~= nil)
	Mocks.now = 3
	e.ns.overlay.Tick(true)
	assert_eq(e.ns.session.lastStatus.hotEstimate, 120)
	Mocks.now = 21
	e.ns.overlay.Tick(true)
	assert_false(e.ns.overlay.state.frame:IsShown())
	e.ns.HandleCommand("approximate off")
	Mocks.now = 0
	e.ns.overlay.Tick(true)
	assert_false(e.ns.overlay.state.frame:IsShown())
end)

T.register("estimates: bonus-inclusive tooltip is never given additional healing power", function()
	local e = env()
	e.ns.HandleCommand("approximate on")
	Mocks.healingPower = 100
	Mocks.descriptions[774] = "Heals 900 over 12 seconds."
	local d = e.ns.learner.GetSpellData(774)
	assert_near(d.basePerStack, 225, 1e-9)
	assert_eq(d.interval, 3)
	e.ns.HandleCommand("amount 774 13")
	assert_eq(e.ns.learner.GetSpellData(774).basePerStack, 13)
	e.ns.HandleCommand("amount 774 off")
	Mocks.healingPower = Mocks.MakeSecret()
	GetSpellBonusHealing = function() error("healing power must not be added to tooltip") end
	assert_eq(e.ns.learner.GetSpellData(774).basePerStack, 225)
end)

T.register("estimates: exact rank IDs, cache and unsupported-family manual fallback", function()
	local e = env()
	e.ns.HandleCommand("approximate on")
	local calls = 0
	C_Spell.GetSpellDescription = function(id)
		calls = calls + 1
		return id == 1058 and "Heals 48 over 12 sec" or nil
	end
	local a = { instanceID = 1, expirationTime = 112 }
	assert_eq(e.ns.learner.GetSpellData(1058, a).basePerStack, 12)
	for i = 1, 100 do e.ns.learner.GetSpellData(1058, a) end
	assert_eq(calls, 1)
	assert_nil(e.ns.learner.GetSpellData(774, a).basePerStack)
	assert_nil(e.ns.learner.GetSpellData(48438, a).interval)
	e.ns.HandleCommand("interval 48438 1")
	e.ns.HandleCommand("amount 48438 20")
	assert_eq(e.ns.learner.GetSpellData(48438, a).basePerStack, 20)
end)

T.register("estimates: secret and ambiguous tooltips fail safely and manual calibration works", function()
	local e = env()
	e.ns.HandleCommand("approximate on")
	Mocks.descriptions[774] = Mocks.MakeSecret()
	assert_nil(e.ns.learner.GetSpellData(774).basePerStack)
	Mocks.descriptions[774] = "Heals 48 over 12 sec and heals 60 over 12 sec"
	e.ns.estimates.Invalidate()
	assert_nil(e.ns.learner.GetSpellData(774).basePerStack)
	e.ns.HandleCommand("amount 774 12")
	assert_eq(e.ns.learner.GetSpellData(774).basePerStack, 12)
end)

T.register("estimates: approximate mode retains ownership/timing gates and handles refresh", function()
	local e = env()
	e.ns.HandleCommand("approximate on")
	Mocks.descriptions[774] = "Heals 48 over 12 sec"
	local function aura(source, expiration)
		Mocks.SetAuras({ { spellId = 774, applications = 0, duration = 12, expirationTime = expiration,
			sourceUnit = source, auraInstanceID = 1 } })
	end
	Mocks.now = 100
	aura("party1", 112)
	assert_eq(e.ns.model.Evaluate(100, { ab = e.ab }).added, 0)
	aura("player", Mocks.MakeSecret())
	assert_eq(e.ns.model.Evaluate(100, { ab = e.ab }).added, 0)
	aura("player", 112)
	assert_eq(e.ns.model.Evaluate(100, { ab = e.ab }).hotEstimate, 48)
	Mocks.now = 106
	assert_eq(e.ns.model.Evaluate(106, { ab = e.ab }).hotEstimate, 24)
	aura("player", 118)
	assert_eq(e.ns.model.Evaluate(106, { ab = e.ab }).hotEstimate, 48)
end)

T.register("estimates: active aura tooltip wins over base spell text without retaining secrets", function()
	local e = env()
	e.ns.HandleCommand("approximate on")
	Mocks.descriptions[774] = "Heals 48 over 12 sec"
	C_TooltipInfo = { GetUnitAuraByAuraInstanceID = function()
		return { lines = { { leftText = Mocks.MakeSecret() }, { leftText = "Heals 15 every 3 sec." } } }
	end }
	local d = e.ns.learner.GetSpellData(774, { instanceID = 1, expirationTime = 112 })
	assert_eq(d.basePerStack, 15)
	assert_true(d.amountSource:match("active aura tooltip") ~= nil)
	assert_eq(e.ns.session.tooltipCache[774].parsed.amount, 15)
end)

T.register("estimates: delayed spell text retries once per cache window then renders", function()
	local e = env()
	e.ns.HandleCommand("approximate on")
	Mocks.SetAuras({ { spellId = 1058, applications = 0, duration = 12, expirationTime = 112,
		sourceUnit = "player", auraInstanceID = 1 } })
	e.ab._predMy:SetValue(Mocks.MakeSecret())
	e.ab._predOther:SetValue(Mocks.MakeSecret())
	local reads = 0
	C_Spell.GetSpellDescription = function(id)
		reads = reads + 1
		return Mocks.descriptions[id]
	end
	e.ns.overlay.Tick(true)
	assert_false(e.ns.overlay.state.frame:IsShown())
	for i = 1, 20 do Mocks.now = Mocks.now + 0.15; e.ns.overlay.Tick() end
	assert_eq(reads, 1)
	Mocks.descriptions[1058] = "Heals 48 over 12 seconds."
	Mocks.now = 105.1
	e.ns.overlay.Tick()
	assert_eq(reads, 2)
	assert_true(e.ns.overlay.state.frame:IsShown())
	local report = e.ns.BuildSnapshotReport()
	assert_true(report:match("spell description %(approximate%)") ~= nil)
	assert_true(report:match("native overlap unverified") ~= nil)
end)
