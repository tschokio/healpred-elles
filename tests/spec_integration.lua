-- tests/spec_integration.lua
-- Mocked-WoW integration tests: aura cache, learning, overlap, overlay,
-- commands, combat deferral, secret handling and CLEU tuple handling.

local unpack = unpack or table.unpack

local function newEnv()
	return Mocks.NewEnv()
end

-- seed learned session data for spell 774 (non-stacking)
local function seed(env, data, id)
	env.ns.session.learned[id or 774] = data
	return data
end

-- install a modern aura record and fire the owning event
local function liveAura(env, over)
	local a = {
		spellId = 774, applications = 1, expirationTime = 12, duration = 12,
		auraInstanceID = 1, sourceUnit = "player",
	}
	for k, v in pairs(over or {}) do a[k] = v end
	Mocks.SetAuras({ a })
	Mocks.Fire("UNIT_AURA", "player")
	return a
end

local function setNative(env, mine, other)
	env.ab._predMy:SetValue(mine or 0)
	if other and other > 0 then
		env.ab._predOther:SetValue(other)
		env.ab._predOther:Show()
	else
		env.ab._predOther:SetValue(0)
		env.ab._predOther:Hide()
	end
end

local function setHealth(h, m)
	Mocks.health = h
	Mocks.maxHealth = m
end

-- Modern CLEU has NO varargs: set the current tuple and fire the bare event.
local function fireCLEU(env, o)
	local g = Mocks.playerGUID
	local t = Mocks.PackCLEU(
		Mocks.now, "SPELL_PERIODIC_HEAL", false, g, "Player", 0, 0, g, "Player", 0, 0,
		o.spell or 774, "spell", 0, o.amount, o.overheal or 0, o.absorbed or 0, o.crit or false)
	Mocks.SetCLEU(t)
	Mocks.Fire("COMBAT_LOG_EVENT_UNFILTERED")
end

-- Drive the addon's real periodic timer callback (not a manual state setup).
local function runTimer()
	for i = #Mocks.tickers, 1, -1 do
		if Mocks.tickers[i].interval == 0.15 then
			Mocks.tickers[i].fn()
			return true
		end
	end
	return false
end

-- Recursively assert that no secret sentinel was retained in session state.
local function assertNoSecrets(node, path, seen)
	seen = seen or {}
	path = path or "session"
	if Mocks.IsSecretlike(node) then error("secret retained at " .. path, 2) end
	if type(node) == "table" and not seen[node] then
		seen[node] = true
		for k, v in pairs(node) do
			assertNoSecrets(v, path .. "." .. tostring(k), seen)
		end
	end
end

------------------------------------------------------------------------------

T.register("integration: no heals appends nothing", function()
	local env = newEnv()
	setNative(env, 0)
	local res = env.ns.model.Evaluate(env.ns.now(), { ab = env.ab })
	assert_eq(res.added, 0)
	assert_nil(res.hotEstimate)
end)

T.register("integration: 200x4=800 learned and appended", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200, baseCount = 4 })
	liveAura(env)
	setNative(env, 0)
	setHealth(1000, 5000)
	Mocks.SetNow(0)
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_near(res.hotEstimate, 800, 1e-9, "hot estimate")
	assert_near(res.added, 800, 1e-9, "appended")
	runTimer()
	local f = env.ns.overlay.state.frame
	assert_true(f and f:IsShown(), "overlay shown")
	assert_near(f:GetValue(), 800, 1e-9)
end)

T.register("integration: non-stacking aura with applications=0 is normalised", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env, { applications = 0 })
	setNative(env, 0)
	setHealth(1000, 5000)
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_near(res.hotEstimate, 800, 1e-9, "count0 treated as one non-stacking application")
end)

T.register("integration: conservative overlap subtracts native", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	setNative(env, 300)
	setHealth(1000, 5000)
	Mocks.SetNow(0)
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_near(res.hotEstimate, 800, 1e-9)
	assert_near(res.added, 500, 1e-9)
end)

T.register("integration: conservative overlap floors at zero", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	setNative(env, 1000)
	setHealth(1000, 5000)
	Mocks.SetNow(0)
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_eq(res.added, 0)
	assert_true(tostring(res.reason):match("conservative") ~= nil)
end)

T.register("integration: clamp 4500/5000 incoming300 leaves200", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	setNative(env, 300)
	setHealth(4500, 5000)
	Mocks.SetNow(0)
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_near(res.added, 200, 1e-9)
end)

T.register("integration: expired HoT yields nothing", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	setNative(env, 0)
	Mocks.SetNow(13)
	local hot = env.ns.model.CollectPlayerHoTs(13)
	assert_nil(hot.total)
	local res = env.ns.model.Evaluate(13, { ab = env.ab })
	assert_eq(res.added, 0)
end)

T.register("integration: refresh does not duplicate ticks", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200, lastTick = 9, lastInstanceID = 1 })
	liveAura(env, { auraInstanceID = 2 })
	setNative(env, 0)
	local hot = env.ns.model.CollectPlayerHoTs(0.1)
	assert_eq(#hot.details, 1, "single aura series")
	assert_near(hot.details[1].amount, 800, 1e-9, "grid reset to application")
end)

T.register("integration: foreign caster filtered", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env, { sourceUnit = "other" })
	local hot = env.ns.model.CollectPlayerHoTs(0)
	assert_nil(hot.total)
	assert_true(tostring(hot.reasons[1]):match("caster") ~= nil)
end)

T.register("integration: nil/unknown source is never counted as player", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	local a = liveAura(env)
	a.sourceUnit = nil -- explicit absence of ownership information
	Mocks.SetAuras({ a })
	Mocks.Fire("UNIT_AURA", "player")
	local hot = env.ns.model.CollectPlayerHoTs(0)
	assert_nil(hot.total, "unknown caster withheld")
	assert_true(tostring(hot.reasons[1]):match("unknown") ~= nil)
end)

T.register("integration: secret source is never counted as player", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env, { sourceUnit = Mocks.MakeSecret() })
	local hot = env.ns.model.CollectPlayerHoTs(0)
	assert_nil(hot.total)
end)

T.register("integration: full health suppresses, shows after damage", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	setNative(env, 0)
	Mocks.SetNow(0)
	setHealth(5000, 5000)
	local full = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_eq(full.added, 0)
	setHealth(1000, 5000)
	local hurt = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_true(hurt.added > 0, "shows after damage")
end)

T.register("integration: uses health not power", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	setNative(env, 0)
	setHealth(1000, 2000)
	Mocks.SetNow(0)
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_eq(res.health.max, 2000)
	assert_eq(Mocks.powerCalls, 0, "never queries power")
end)

T.register("integration: learns interval and base from modern CLEU", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 7, expirationTime = 112 })
	Mocks.SetNow(100)
	fireCLEU(env, { amount = 200 })
	Mocks.SetNow(103)
	fireCLEU(env, { amount = 200 })
	local d = env.ns.session.learned[774]
	assert_not_nil(d)
	assert_near(d.interval, 3, 1e-9, "interval learned")
	assert_near(d.basePerStack, 200, 1e-9, "base learned")
end)

T.register("integration: crit ticks still learn interval but never base", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 7, expirationTime = 112 })
	Mocks.SetNow(100)
	fireCLEU(env, { amount = 9999, crit = true })
	local d0 = env.ns.session.learned[774]
	assert_not_nil(d0, "the timer record is created")
	assert_nil(d0.interval, "no interval from a single tick")
	assert_nil(d0.basePerStack, "no magnitude from a single tick")
	Mocks.SetNow(103)
	fireCLEU(env, { amount = 9999, crit = true })
	local d = env.ns.session.learned[774]
	assert_not_nil(d, "interval observed from crit ticks")
	assert_near(d.interval, 3, 1e-9)
	assert_nil(d.basePerStack, "crit never teaches magnitude")
	assert_nil(d.totals[1])
end)

T.register("integration: absorbed ticks learn interval but never base", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 7, expirationTime = 112 })
	Mocks.SetNow(100)
	fireCLEU(env, { amount = 200, absorbed = 10 })
	Mocks.SetNow(103)
	fireCLEU(env, { amount = 200, absorbed = 10 })
	local d = env.ns.session.learned[774]
	assert_not_nil(d)
	assert_near(d.interval, 3, 1e-9)
	assert_nil(d.basePerStack)
end)

T.register("integration: overheal adapter modes total vs effective", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 7, expirationTime = 112 })
	env.ns.db.amountMode = "total"
	Mocks.SetNow(100)
	fireCLEU(env, { amount = 200, overheal = 50 })
	assert_near(env.ns.session.learned[774].basePerStack, 200, 1e-9, "total = amount")
	env.ns.learner.Reset()
	liveAura(env, { auraInstanceID = 7, expirationTime = 112 })
	env.ns.db.amountMode = "effective"
	Mocks.SetNow(100)
	fireCLEU(env, { amount = 200, overheal = 50 })
	assert_near(env.ns.session.learned[774].basePerStack, 250, 1e-9, "effective = amount + overheal")
end)

T.register("integration: interval not learned across aura instance change", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 1, expirationTime = 112 })
	Mocks.SetNow(100)
	fireCLEU(env, { amount = 200 })
	liveAura(env, { auraInstanceID = 2, expirationTime = 115 })
	Mocks.SetNow(103)
	fireCLEU(env, { amount = 200 })
	assert_nil(env.ns.session.learned[774].interval)
end)

T.register("integration: same-instance refresh does not create a cross-refresh interval", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 1, expirationTime = 112 })
	Mocks.SetNow(100)
	fireCLEU(env, { amount = 200 })
	-- refreshed in place: same instance ID, new expiration signature
	liveAura(env, { auraInstanceID = 1, expirationTime = 115 })
	Mocks.SetNow(103)
	fireCLEU(env, { amount = 200 })
	assert_nil(env.ns.session.learned[774].interval, "phase reset, no cross-refresh delta")
end)

T.register("integration: stacking totals are learned per stack count (no base*stacks)", function()
	local env = newEnv()
	env.ns.db.intervalOverrides[33763] = 1
	local function setAura(app)
		Mocks.SetAuras({ { spellId = 33763, applications = app, expirationTime = 12, duration = 12, auraInstanceID = 1, sourceUnit = "player" } })
		Mocks.Fire("UNIT_AURA", "player")
	end
	Mocks.SetNow(0)
	setAura(2)
	fireCLEU(env, { spell = 33763, amount = 400 })
	assert_near(env.ns.learner.AmountForStack(33763, 2), 400, 1e-9, "exact total at 2 stacks")
	assert_nil(env.ns.learner.AmountForStack(33763, 3), "never observed at 3")
	-- at 3 stacks the estimate withholds until observed there
	setAura(3)
	local hot = env.ns.model.CollectPlayerHoTs(0)
	assert_nil(hot.total)
	-- observe at 3, then use the exact total (not 400/2*3 = 600)
	Mocks.SetNow(1)
	fireCLEU(env, { spell = 33763, amount = 500 })
	setAura(3)
	local hot2 = env.ns.model.CollectPlayerHoTs(1)
	assert_not_nil(hot2.total)
	assert_near(hot2.details[1].perTick, 500, 1e-9, "exact observed total at 3 stacks")
end)

T.register("integration: exact tick boundaries (8.999 vs 9)", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	assert_near(env.ns.model.CollectPlayerHoTs(8.999).total, 400, 1e-9)
	assert_near(env.ns.model.CollectPlayerHoTs(9).total, 200, 1e-9)
end)

T.register("integration: secret aura timing withholds, no error", function()
	local env = newEnv()
	local s = Mocks.MakeSecret()
	Mocks.SetAuras({ { spellId = 774, applications = 1, expirationTime = s, duration = s, auraInstanceID = 1, sourceUnit = "player" } })
	local hot = env.ns.model.CollectPlayerHoTs(0)
	assert_nil(hot.total)
	assert_true(#hot.reasons > 0)
	assertNoSecrets(env.ns.session)
end)

T.register("integration: secret native incoming suppresses real overlay", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	setHealth(1000, 5000)
	env.ab._predMy:SetValue(Mocks.MakeSecret())
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_true(res.suppressed, "suppressed")
	assert_eq(res.added, 0)
	assert_true(tostring(res.reason):match("secret") ~= nil)
end)

T.register("integration: secret stacks on stacking HoT withholds", function()
	local env = newEnv()
	seed(env, { interval = 1, basePerStack = 100 }, 33763)
	Mocks.SetAuras({ { spellId = 33763, applications = Mocks.MakeSecret(), expirationTime = 12, duration = 12, auraInstanceID = 1, sourceUnit = "player" } })
	local hot = env.ns.model.CollectPlayerHoTs(0)
	assert_nil(hot.total)
end)

T.register("integration: secret instanceID is not retained (no `and nil or` bug)", function()
	local env = newEnv()
	Mocks.SetAuras({ { spellId = 774, applications = 1, expirationTime = 12, duration = 12, auraInstanceID = Mocks.MakeSecret(), sourceUnit = "player" } })
	local auras = env.ns.api.ReadPlayerAuras()
	assert_eq(#auras, 1)
	assert_nil(auras[1].instanceID, "secret instance dropped, not kept")
	assertNoSecrets(env.ns.session)
end)

T.register("integration: secret aura container is detected before indexing", function()
	local env = newEnv()
	local s = Mocks.MakeSecret()
	Mocks.SetAuras({ s })
	local ok = pcall(function() return env.ns.api.ReadPlayerAuras() end)
	assert_true(ok, "no error reading a secret container")
	assert_eq(#env.ns.api.ReadPlayerAuras(), 0)
	assertNoSecrets(env.ns.session)
end)

T.register("integration: secret CLEU ownership never produces learning", function()
	local env = newEnv()
	local s = Mocks.MakeSecret()
	liveAura(env, { auraInstanceID = 7 })
	Mocks.SetCLEU(Mocks.PackCLEU(100, "SPELL_PERIODIC_HEAL", false, s, "P", 0, 0, Mocks.playerGUID, "P", 0, 0, 774, "x", 0, 200, 0, 0, false))
	Mocks.Fire("COMBAT_LOG_EVENT_UNFILTERED")
	assert_nil(env.ns.session.learned[774], "secret source GUID yields no learning")
	assertNoSecrets(env.ns.session)
end)

T.register("integration: missing CLEU is handled gracefully", function()
	local env = newEnv()
	local saved = _G.CombatLogGetCurrentEventInfo
	_G.CombatLogGetCurrentEventInfo = nil
	local ok = pcall(function() Mocks.Fire("COMBAT_LOG_EVENT_UNFILTERED") end)
	assert_true(ok, "no error without CLEU")
	assert_false(env.ns.api.CombatLogAvailable())
	_G.CombatLogGetCurrentEventInfo = saved
end)

T.register("integration: CLEU tuple preserves nil holes and trailing false", function()
	local env = newEnv()
	local saved = _G.CombatLogGetCurrentEventInfo
	local t = Mocks.PackCLEU(100, "SPELL_PERIODIC_HEAL", false, nil, "x", false)
	_G.CombatLogGetCurrentEventInfo = function() return unpack(t, 1, t.n) end
	local packed = env.ns.api.GetCLEU()
	assert_eq(packed.n, 6, "explicit count")
	assert_eq(packed[3], false, "middle false preserved")
	assert_eq(packed[4], nil, "nil hole preserved")
	assert_eq(packed[6], false, "trailing false preserved")
	_G.CombatLogGetCurrentEventInfo = saved
end)

T.register("integration: native prediction disabled suppresses real and fake", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	env.ab._predOn = false
	local real = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_true(real.suppressed)
	assert_eq(real.reason, "native prediction disabled")
	local fake = env.ns.model.Evaluate(0, { fake = true, ab = env.ab })
	assert_true(fake.suppressed, "fake is gated by native too")
	assert_eq(fake.reason, "native prediction disabled")
end)

T.register("integration: native bars missing suppresses", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env, { auraInstanceID = 1 })
	local savedOther = env.ab._predOther
	env.ab._predOther = nil
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_true(res.suppressed)
	assert_eq(res.reason, "native prediction bars missing")
	env.ab._predOther = savedOther
end)

T.register("integration: missing/errored heal absorb is UNKNOWN and suppresses real", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	setNative(env, 0)
	setHealth(1000, 5000)
	local saved = _G.UnitGetTotalHealAbsorbs
	_G.UnitGetTotalHealAbsorbs = nil
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_true(res.suppressed)
	assert_true(tostring(res.reason):match("unknown heal absorb") ~= nil)
	-- fake still renders so users can exercise the overlay
	local fake = env.ns.model.Evaluate(0, { fake = true, ab = env.ab })
	assert_false(fake.suppressed, "fake bypasses the absorb gate")
	_G.UnitGetTotalHealAbsorbs = saved
end)

T.register("integration: positive heal absorb suppresses real", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	setNative(env, 0)
	setHealth(1000, 5000)
	Mocks.healAbsorb = 50
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_true(res.suppressed)
	Mocks.healAbsorb = 0
end)

T.register("integration: excludes-HoT opt-in gives direct+hot=1400 with native numeric", function()
	local env = newEnv()
	env.ns.db.assumeApiExcludesHoTs = true
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	setNative(env, 600)
	setHealth(1000, 5000)
	Mocks.SetNow(0)
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_near(res.hotEstimate, 800, 1e-9)
	assert_near(res.added, 800, 1e-9)
	assert_near(600 + res.added, 1400, 1e-9, "displayed total")
end)

T.register("integration: excludes mode does not bypass secret native", function()
	local env = newEnv()
	env.ns.db.assumeApiExcludesHoTs = true
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	env.ab._predMy:SetValue(Mocks.MakeSecret())
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_true(res.suppressed)
	assert_eq(res.added, 0)
end)

T.register("integration: frame replacement is detected by the timer and reattached", function()
	local env = newEnv()
	runTimer() -- initial attach through the real timer path
	local frame = env.ns.overlay.state.frame
	local parent1 = env.ns.overlay.state.parent
	local newer = Mocks.BuildEUF()
	_G.EllesmereUI._ModuleNS.EllesmereUIUnitFrames.frames.player = newer.player
	-- no manual Resolve: the periodic probe must notice and reattach
	env.ns.overlay.RequestPaint()
	Mocks.SetNow(Mocks.now + 1)
	runTimer()
	assert_eq(env.ns.overlay.state.frame, frame, "same overlay frame reused")
	assert_true(env.ns.overlay.state.parent ~= parent1, "reparented to the new frame")
	assert_eq(env.ns.overlay.state.parent, newer.ab._missClip, "parented to the new missClip")
	local count = 0
	for _, f in ipairs(Mocks.frames) do
		if f._name == "EllesmereUI_HoTPredictionOverlay" then count = count + 1 end
	end
	assert_eq(count, 1, "no duplicate overlay frames")
end)

T.register("integration: overlay is never created for the first time in combat", function()
	local env = newEnv()
	env.ns.overlay.state.frame = nil
	env.ns.overlay.state.ab = nil
	env.ns.overlay.state.structureDirty = true
	Mocks.inCombat = true
	env.ns.overlay.RequestPaint()
	env.ns.overlay.Tick()
	assert_nil(env.ns.overlay.state.frame, "not created in combat")
	assert_true(env.ns.overlay.state.pending, "pending until regen")
	Mocks.inCombat = false
	env.ns.dispatch("PLAYER_REGEN_ENABLED")
	assert_not_nil(env.ns.overlay.state.frame, "created after regen")
end)

T.register("integration: native hook queues deferred work instead of resolving", function()
	local env = newEnv()
	env.ns.overlay.Resolve()
	local module = env.ns.api.GetEUF()
	env.ns.overlay.state.paintRequested = false
	env.ns.overlay.state.structureDirty = false
	module.UF_PaintHealPred()
	assert_true(env.ns.overlay.state.paintRequested, "hook queued a paint")
	assert_false(env.ns.overlay.state.structureDirty, "no synchronous structural resolve")
end)

T.register("integration: native hook style change is applied on the next deferred paint", function()
	local env = newEnv()
	env.ns.overlay.Resolve()
	local f = env.ns.overlay.state.frame
	local module = env.ns.api.GetEUF()
	env.ab._predMy:SetStatusBarColor(0.25, 0.25, 0.25)
	module.UF_HealPredApply() -- queues style refresh, no synchronous work
	assert_true(env.ns.overlay.state.structureDirty)
	Mocks.SetNow(Mocks.now + 1)
	runTimer()
	assert_near(select(1, f:GetStatusBarColor()), 0.25, 1e-6, "deferred style applied")
end)


T.register("integration: aura cache reused on idle ticks and invalidated by player UNIT_AURA", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	runTimer() -- first evaluation populates the cache
	local afterFirst = Mocks.auraCalls
	assert_true(afterFirst > 0, "first read scans the aura API")
	env.ns.overlay.state.paintRequested = false
	env.ns.overlay.state.active = false
	Mocks.SetNow(Mocks.now + 1)
	runTimer()
	Mocks.SetNow(Mocks.now + 1)
	runTimer()
	assert_eq(Mocks.auraCalls, afterFirst, "idle ticks reuse the cache")
	Mocks.Fire("UNIT_AURA", "player")
	env.ns.overlay.state.active = false
	Mocks.SetNow(Mocks.now + 1)
	runTimer()
	assert_true(Mocks.auraCalls > afterFirst, "player UNIT_AURA forces a rescan")
end)

T.register("integration: non-player UNIT_AURA never invalidates the cache", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	runTimer()
	local before = Mocks.auraCalls
	Mocks.Fire("UNIT_AURA", "target")
	env.ns.overlay.state.paintRequested = false
	env.ns.overlay.state.active = false
	Mocks.SetNow(Mocks.now + 1)
	runTimer()
	assert_eq(Mocks.auraCalls, before, "unrelated unit does not force a full scan")
end)

T.register("integration: native styling copied, retextured on change, overridable", function()
	local env = newEnv()
	env.ns.overlay.Resolve()
	local f = env.ns.overlay.state.frame
	env.ab._predMy:SetStatusBarTexture("Interface\\custom.blp")
	env.ab._predMy:SetStatusBarColor(0.5, 0.5, 0.5)
	env.ns.overlay.Resolve() -- style changes re-apply on resolve, not per tick
	env.ns.overlay.RenderValue(100, "test")
	assert_eq(f:GetStatusBarTexture():GetTexture(), "Interface\\custom.blp")
	assert_near(select(1, f:GetStatusBarColor()), 0.5, 1e-6)
	env.ns.db.shareNativeStyle = false
	env.ns.db.overlayColor = { 1, 0, 0 }
	env.ns.overlay.Resolve()
	env.ns.overlay.RenderValue(100, "test")
	assert_near(select(1, f:GetStatusBarColor()), 1, 1e-6)
end)

T.register("integration: texture rotation is copied from the native fill", function()
	local env = newEnv()
	env.ab._predMy:GetStatusBarTexture():SetRotation(0.5)
	env.ns.overlay.Resolve()
	local f = env.ns.overlay.state.frame
	assert_near(f:GetStatusBarTexture():GetRotation(), 0.5, 1e-9)
end)

T.register("integration: overlay fill receives native bounds masks (and removes them)", function()
	local env = newEnv()
	env.ns.overlay.Resolve()
	local f = env.ns.overlay.state.frame
	local ourTex = f:GetStatusBarTexture()
	assert_eq(ourTex:GetMaskTextureCount(), 1, "absorb mask applied")
	env.ab._blizzMaskOn = true
	env.ns.overlay.InvalidateStructure()
	env.ns.overlay.Resolve()
	assert_eq(ourTex:GetMaskTextureCount(), 2, "blizz mask added when enabled")
	env.ab._blizzMaskOn = false
	env.ns.overlay.InvalidateStructure()
	env.ns.overlay.Resolve()
	assert_eq(ourTex:GetMaskTextureCount(), 1, "blizz mask removed when disabled")
	-- the vendor texture itself is never masked
	assert_eq(env.ab._predMy:GetStatusBarTexture():GetMaskTextureCount(), 0, "vendor texture untouched")
end)

T.register("integration: axes horizontal and vertical-reversed anchor", function()
	local env = newEnv()
	env.ns.overlay.Resolve()
	local f = env.ns.overlay.state.frame
	local p1 = f._points[1]
	assert_eq(p1[1], "LEFT")
	assert_eq(p1[3], "RIGHT")

	env.ab._predMy:SetOrientation("VERTICAL")
	env.ab._predMy:SetReverseFill(true)
	env.ns.overlay.InvalidateStructure()
	env.ns.overlay.Resolve()
	local p2 = f._points[1]
	assert_eq(f:GetOrientation(), "VERTICAL")
	assert_true(f:IsReverseFill())
	assert_eq(p2[1], "TOP")
	assert_eq(p2[3], "BOTTOM")
end)

T.register("integration: commands test/status/debug/enable/calibration/color", function()
	local env = newEnv()
	local ns = env.ns
	ns.HandleCommand("test 1000")
	assert_eq(ns.session.fake.value, 1000)
	runTimer()
	assert_near(ns.overlay.state.frame:GetValue(), 1000, 1e-9)
	assert_true(ns.overlay.state.frame:IsShown())
	ns.HandleCommand("status")
	local joined = table.concat(Mocks.chat, "\n")
	assert_true(joined:match("enabled=") ~= nil, "status lists settings")
	assert_true(joined:match("overlay frame=") ~= nil, "status lists overlay frame")
	assert_true(joined:match("cleu function=") ~= nil, "status lists CLEU access")
	assert_true(joined:match("build=") ~= nil, "status lists client build")
	ns.HandleCommand("debug on")
	assert_true(ns.db.debug)
	local dchat = table.concat(Mocks.chat, "\n")
	assert_true(dchat:match("policy=") ~= nil, "rich debug dump")
	ns.HandleCommand("interval 774 2")
	assert_eq(ns.db.intervalOverrides[774], 2)
	assert_eq(ns.learner.GetSpellData(774).confidence, "override")
	ns.HandleCommand("alpha 0.3")
	assert_near(ns.db.alpha, 0.3, 1e-9)
	ns.HandleCommand("color overlay 1 0 0")
	assert_eq(ns.db.overlayColor[1], 1)
	assert_false(ns.db.shareNativeStyle, "custom color disables native inheritance")
	ns.HandleCommand("color native")
	assert_true(ns.db.shareNativeStyle, "color native restores inheritance")
	ns.HandleCommand("enable off")
	assert_false(ns.db.enabled)
	ns.HandleCommand("enable on")
	assert_true(ns.db.enabled)
	ns.HandleCommand("test off")
	assert_nil(ns.session.fake)
end)

T.register("integration: test command rejects bad values; test3 removed", function()
	local env = newEnv()
	local ns = env.ns
	ns.HandleCommand("test -5")
	assert_nil(ns.session.fake, "negative rejected")
	ns.HandleCommand("test nan")
	assert_nil(ns.session.fake, "nan rejected")
	ns.HandleCommand("interval 0 3")
	assert_nil(ns.db.intervalOverrides[0], "non-positive id rejected")
	ns.HandleCommand("interval 774 -1")
	assert_nil(ns.db.intervalOverrides[774], "negative interval rejected")
	ns.HandleCommand("test3 600 800")
	local joined = table.concat(Mocks.chat, "\n")
	assert_true(joined:match("unknown command 'test3'") ~= nil, "test3 removed")
end)

T.register("integration: fake test is session-only and never persisted", function()
	local env = newEnv()
	env.ns.HandleCommand("test 1000")
	assert_not_nil(env.ns.session.fake)
	_G.EllesmereUI_HoTPredictionDB = { showFake = true, enabled = true }
	env.ns.InitDatabase()
	assert_nil(env.ns.db.showFake)
	local env2 = newEnv()
	assert_nil(env2.ns.session.fake)
end)

T.register("integration: enabled=false hides overlay", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	setNative(env, 0)
	setHealth(1000, 5000)
	env.ns.overlay.RenderValue(500, "x")
	assert_true(env.ns.overlay.state.frame:IsShown(), "shown while enabled")
	env.ns.db.enabled = false
	runTimer()
	assert_false(env.ns.overlay.state.frame:IsShown(), "hidden while disabled")
end)

T.register("integration: combat defers structural attach", function()
	local env = newEnv()
	local ns = env.ns
	ns.overlay.state.ab = nil
	ns.overlay.state.parent = nil
	Mocks.inCombat = true
	ns.overlay.Resolve()
	assert_true(ns.overlay.state.pending)
	assert_nil(ns.overlay.state.parent)
	Mocks.inCombat = false
	ns.dispatch("PLAYER_REGEN_ENABLED")
	assert_false(ns.overlay.state.pending)
	assert_not_nil(ns.overlay.state.parent)
end)

T.register("integration: quiet startup, no tick spam", function()
	local env = newEnv()
	local before = #Mocks.chat
	assert_eq(before, 0, "quiet startup")
	runTimer()
	assert_eq(#Mocks.chat, before, "no chat from tick while debug off")
end)

T.register("integration: vehicle frame is never painted (real or fake)", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	setNative(env, 0)
	setHealth(1000, 5000)
	Mocks.SetNow(0)
	env.player._euiUnit = "vehicle"
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_true(res.suppressed, "suppressed on vehicle")
	assert_eq(res.added, 0)
	local fake = env.ns.model.Evaluate(0, { fake = true, ab = env.ab })
	assert_true(fake.suppressed, "fake too on vehicle")
	env.player._euiUnit = "player"
	local res2 = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_true(res2.added > 0, "paints player again")
end)

T.register("integration: nil frame unit hides instead of guessing", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	env.player._euiUnit = nil
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_true(res.suppressed)
	assert_true(tostring(res.reason):match("unit") ~= nil)
end)

T.register("integration: amountmode change resets learned magnitudes", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 7, expirationTime = 112 })
	Mocks.SetNow(100)
	fireCLEU(env, { amount = 200 })
	assert_not_nil(env.ns.session.learned[774].basePerStack)
	env.ns.HandleCommand("amountmode effective")
	assert_nil(env.ns.session.learned[774].basePerStack, "magnitudes reset on amountmode change")
	assert_nil(env.ns.session.learned[774].totals[1], "stack totals reset too")
end)

T.register("integration: reset invalidates the aura cache", function()
	local env = newEnv()
	liveAura(env)
	runTimer()
	assert_not_nil(env.ns.session.auraCache)
	env.ns.HandleCommand("reset")
	assert_nil(env.ns.session.auraCache, "cache invalidated on reset")
end)

T.register("integration: debug only prints on change (no per-tick spam)", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	env.ns.db.debug = true
	env.ns.debugEnabled = true
	runTimer()
	local after = #Mocks.chat
	runTimer()
	runTimer()
	assert_eq(#Mocks.chat, after, "unchanged state does not re-print")
end)

T.register("integration: secret crit/absorb CLEU fields do not error or retain secrets", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 7, expirationTime = 112 })
	local s = Mocks.MakeSecret()
	Mocks.SetNow(100)
	Mocks.SetCLEU(Mocks.PackCLEU(100, "SPELL_PERIODIC_HEAL", false, Mocks.playerGUID, "P", 0, 0, Mocks.playerGUID, "P", 0, 0, 774, "x", 0, 200, 0, 0, s))
	assert_true(pcall(function() Mocks.Fire("COMBAT_LOG_EVENT_UNFILTERED") end), "secret crit safe")
	Mocks.SetNow(103)
	Mocks.SetCLEU(Mocks.PackCLEU(103, "SPELL_PERIODIC_HEAL", false, Mocks.playerGUID, "P", 0, 0, Mocks.playerGUID, "P", 0, 0, 774, "x", 0, 200, 0, s, s))
	assert_true(pcall(function() Mocks.Fire("COMBAT_LOG_EVENT_UNFILTERED") end), "secret absorbed safe")
	assert_nil(env.ns.session.learned[774].basePerStack, "unknown crit/absorb teaches no magnitude")
	assertNoSecrets(env.ns.session)
end)

T.register("integration: forbidden event registration is recorded", function()
	local env = newEnv()
	local saved = env.ns.eventFrame.RegisterEvent
	env.ns.eventFrame.RegisterEvent = function() error("forbidden", 2) end
	local ok = env.ns.register("SOME_FORBIDDEN_EVENT")
	assert_false(ok, "registration reported as failed")
	assert_false(env.ns.eventRegistered("SOME_FORBIDDEN_EVENT"))
	env.ns.eventFrame.RegisterEvent = saved
	assert_true(env.ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED"), "normal registration recorded")
end)

T.register("integration: health/prediction events queue a coalesced paint", function()
	local env = newEnv()
	env.ns.overlay.state.paintRequested = false
	Mocks.Fire("UNIT_HEALTH", "player")
	assert_true(env.ns.overlay.state.paintRequested, "player UNIT_HEALTH queues paint")
	env.ns.overlay.state.paintRequested = false
	Mocks.Fire("UNIT_HEAL_PREDICTION", "target")
	assert_false(env.ns.overlay.state.paintRequested, "unrelated unit ignored")
	Mocks.Fire("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "player")
	assert_true(env.ns.overlay.state.paintRequested, "player absorb queues paint")
end)

T.register("integration: gear change resets magnitudes but keeps intervals", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 7, expirationTime = 112 })
	Mocks.SetNow(100)
	fireCLEU(env, { amount = 200 })
	Mocks.SetNow(103)
	fireCLEU(env, { amount = 200 })
	assert_not_nil(env.ns.session.learned[774].interval)
	assert_not_nil(env.ns.session.learned[774].basePerStack)
	Mocks.Fire("PLAYER_EQUIPMENT_CHANGED", 16, true)
	assert_not_nil(env.ns.session.learned[774].interval, "interval kept across gear change")
	assert_nil(env.ns.session.learned[774].basePerStack, "magnitude reset across gear change")
end)

T.register("integration: missing EUF does not error", function()
	Mocks.Reset()
	_G.EllesmereUI = nil
	local ns = Mocks.LoadAddon()
	local ok = pcall(function()
		Mocks.Fire("ADDON_LOADED", "EllesmereUI_HoTPrediction")
		Mocks.Fire("PLAYER_LOGIN")
		ns.overlay.Tick()
	end)
	assert_true(ok, "loads and ticks without EUF")
	assert_nil(ns.api.GetEUF())
	local joined = table.concat(Mocks.chat, "\n")
	assert_true(joined:match("EllesmereUIUnitFrames") ~= nil, "single useful failure message")
end)

T.register("integration: chain follows BOTH incoming segments after texture replacement", function()
	local env = newEnv()
	setNative(env, 600, 200)
	env.ns.overlay.Resolve()
	local f = env.ns.overlay.state.frame
	assert_eq(select(2, f:GetPoint(1)), env.ab._predOther:GetStatusBarTexture())
	local replacement = env.ab._predOther:CreateTexture()
	env.ab._predOther:SetStatusBarTexture(replacement)
	runTimer()
	assert_eq(select(2, f:GetPoint(1)), replacement)
	assert_eq(f:GetParent(), env.ab._missClip)
end)

T.register("integration: native layout hook updates axes and dimensions after deferral", function()
	local env = newEnv()
	env.ns.overlay.Resolve()
	local f = env.ns.overlay.state.frame
	env.ab._predMy:SetOrientation("VERTICAL")
	env.ab._predMy:SetReverseFill(true)
	env.hp:SetSize(30, 240)
	env.ns.api.GetEUF().UF_HealPredLayout(env.ab)
	assert_eq(f:GetOrientation(), "HORIZONTAL")
	runTimer()
	assert_eq(f:GetOrientation(), "VERTICAL")
	assert_eq(f:GetHeight(), 240)
	assert_true(f:IsReverseFill())
end)

T.register("integration: expired aura cannot teach a periodic magnitude", function()
	local env = newEnv()
	liveAura(env, { expirationTime = 99 })
	Mocks.SetNow(100)
	fireCLEU(env, { amount = 200 })
	assert_nil(env.ns.session.learned[774])
end)

T.register("integration: clip replacement in combat hides until safe reattachment", function()
	local env = newEnv()
	env.ns.HandleCommand("test 500")
	runTimer()
	local f = env.ns.overlay.state.frame
	local old = f:GetParent()
	Mocks.inCombat = true
	env.ab._missClip = CreateFrame("Frame", nil, env.hp)
	runTimer()
	assert_false(f:IsShown())
	assert_eq(f:GetParent(), old)
	Mocks.inCombat = false
	Mocks.Fire("PLAYER_REGEN_ENABLED")
	runTimer()
	assert_eq(f:GetParent(), env.ab._missClip)
	assert_true(f:IsShown())
end)
