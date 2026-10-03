local function env()
	local e = Mocks.NewEnv({ noCLEU = true, build = { "1.60.1", 70205, "2026-10-02", 16001 } })
	e.ns.HandleCommand("approximate on")
	Mocks.descriptions[774] = "Heals 48 over 12 sec."
	e.ab._predMy:SetValue(Mocks.MakeSecret())
	e.ab._predOther:SetValue(Mocks.MakeSecret())
	return e
end
local function hot()
	Mocks.SetAuras({ { spellId = 774, applications = 0, duration = 12,
		expirationTime = 112, auraInstanceID = 1, sourceUnit = "player" } })
end

T.register("forms: same native frames resize and rescale existing HoT in combat without losing phase", function()
	local e = env()
	hot()
	e.ns.overlay.Tick(true)
	assert_eq(e.ns.session.lastStatus.hotEstimate, 48)
	local f = e.ns.overlay.state.frame
	Mocks.inCombat = true
	Mocks.maxHealth = 1500
	e.ab._predMy:SetMinMaxValues(0, 1500)
	e.hp:SetSize(240, 35)
	Mocks.Fire("UPDATE_SHAPESHIFT_FORM")
	Mocks.Fire("UNIT_DISPLAYPOWER", "player")
	e.ns.overlay.Tick()
	assert_eq(e.ns.overlay.state.frame, f)
	assert_true(f:IsShown())
	assert_eq(f:GetWidth(), 240)
	local _, max = f:GetMinMaxValues()
	assert_eq(max, 1500)
	assert_eq(e.ns.session.lastStatus.hotEstimate, 48)
	Mocks.now = 103.1
	e.ns.overlay.Tick()
	assert_eq(e.ns.session.lastStatus.hotEstimate, 36, "shifting must not restart tick schedule")
end)

T.register("forms: delayed aura data recovers from empty transition snapshot without new aura event", function()
	local e = env()
	hot()
	e.ns.overlay.Tick(true)
	Mocks.SetAuras({})
	Mocks.Fire("UPDATE_SHAPESHIFT_FORM")
	e.ns.overlay.Tick()
	assert_false(e.ns.overlay.state.frame:IsShown())
	hot() -- client data settles without another UNIT_AURA notification
	Mocks.now = 100.3
	e.ns.overlay.Tick()
	assert_true(e.ns.overlay.state.frame:IsShown())
	assert_eq(e.ns.session.lastStatus.hotEstimate, 48)
	Mocks.now = 100.8
	e.ns.overlay.Tick()
	assert_nil(e.ns.overlay.state.nextFormRefresh)
	local scans = e.ns.api.auraScans
	for i = 1, 10 do Mocks.now = Mocks.now + 0.15; e.ns.overlay.Tick() end
	assert_eq(e.ns.api.auraScans, scans, "bounded refreshes do not cause ongoing aura scans")
end)

T.register("forms: removed or expired HoTs never survive a form refresh", function()
	local e = env()
	hot()
	e.ns.overlay.Tick(true)
	Mocks.SetAuras({})
	Mocks.Fire("UNIT_DISPLAYPOWER", "player")
	e.ns.overlay.Tick()
	Mocks.now = 100.8
	e.ns.overlay.Tick()
	Mocks.now = 101
	e.ns.overlay.Tick()
	assert_false(e.ns.overlay.state.frame:IsShown())
	hot()
	Mocks.now = 113
	Mocks.Fire("UPDATE_SHAPESHIFT_FORM")
	e.ns.overlay.Tick()
	assert_false(e.ns.overlay.state.frame:IsShown())
end)

T.register("forms: unrelated power type changes are ignored and disable cancels pending work", function()
	local e = env()
	e.ns.overlay.Tick(true)
	local st = e.ns.overlay.state
	st.paintRequested, st.structureDirty = false, false
	Mocks.Fire("UNIT_DISPLAYPOWER", "target")
	assert_false(st.paintRequested)
	assert_nil(st.nextFormRefresh)
	Mocks.Fire("UPDATE_SHAPESHIFT_FORM")
	assert_true(st.nextFormRefresh ~= nil)
	e.ns.HandleCommand("enable off")
	assert_nil(st.nextFormRefresh)
	assert_nil(st.finalFormRefresh)
	assert_false(e.ns.eventFrame._events.UPDATE_SHAPESHIFT_FORM or false)
end)

T.register("forms: SPELLS_CHANGED requests repaint when prior estimate was blocked", function()
	local e = env()
	hot()
	Mocks.descriptions[774] = nil
	e.ns.overlay.Tick(true)
	assert_false(e.ns.overlay.state.frame:IsShown())
	Mocks.descriptions[774] = "Heals 48 over 12 sec."
	Mocks.Fire("SPELLS_CHANGED")
	assert_true(e.ns.overlay.state.paintRequested)
	e.ns.overlay.Tick()
	assert_true(e.ns.overlay.state.frame:IsShown())
end)
