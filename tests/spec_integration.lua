-- tests/spec_integration.lua
-- Mocked-WoW integration tests: aura reading, learning, overlap, overlay,
-- commands, combat deferral, secret handling.

local unpack = unpack or table.unpack

local function newEnv()
	return Mocks.NewEnv()
end

-- seed learned session data for spell 774
local function seed(env, data)
	env.ns.session.learned[774] = data
	return data
end

-- install a live modern-aura record (spellId/applications/expirationTime/...)
local function liveAura(env, over)
	local a = {
		spellId = 774, applications = 1, expirationTime = 12, duration = 12,
		auraInstanceID = 1, sourceUnit = "player",
	}
	for k, v in pairs(over or {}) do a[k] = v end
	Mocks.SetAuras({ a })
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

local function fireTick(env, o)
	local g = Mocks.playerGUID
	local tup = {
		Mocks.now, "SPELL_PERIODIC_HEAL", false, g, "Player", 0, 0, g, "Player", 0, 0,
		o.spell or 774, "spell", 0, o.amount, o.overheal or 0, o.absorbed or 0, o.crit or false,
	}
	Mocks.Fire("COMBAT_LOG_EVENT_UNFILTERED", unpack(tup))
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
	env.ns.overlay.Tick()
	local f = env.ns.overlay.state.frame
	assert_true(f and f:IsShown(), "overlay shown")
	assert_near(f:GetValue(), 800, 1e-9)
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
	assert_true(tostring(hot.reasons[1]):match("foreign") ~= nil)
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

T.register("integration: learns interval and base from CLEU", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 7 })
	Mocks.SetNow(100)
	fireTick(env, { amount = 200 })
	Mocks.SetNow(103)
	fireTick(env, { amount = 200 })
	local d = env.ns.session.learned[774]
	assert_not_nil(d)
	assert_near(d.interval, 3, 1e-9, "interval learned")
	assert_near(d.basePerStack, 200, 1e-9, "base learned")
end)

T.register("integration: crit ticks are ignored", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 7 })
	Mocks.SetNow(100)
	fireTick(env, { amount = 9999, crit = true })
	assert_nil(env.ns.session.learned[774])
end)

T.register("integration: absorbed ticks are ignored", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 7 })
	Mocks.SetNow(100)
	fireTick(env, { amount = 200, absorbed = 10 })
	assert_nil(env.ns.session.learned[774])
end)

T.register("integration: overheal adapter modes total vs effective", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 7 })
	env.ns.db.amountMode = "total"
	Mocks.SetNow(100)
	fireTick(env, { amount = 200, overheal = 50 })
	assert_near(env.ns.session.learned[774].basePerStack, 200, 1e-9, "total = amount")
	env.ns.learner.Reset()
	liveAura(env, { auraInstanceID = 7 })
	env.ns.db.amountMode = "effective"
	Mocks.SetNow(100)
	fireTick(env, { amount = 200, overheal = 50 })
	assert_near(env.ns.session.learned[774].basePerStack, 250, 1e-9, "effective = amount + overheal")
end)

T.register("integration: interval not learned across refresh", function()
	local env = newEnv()
	liveAura(env, { auraInstanceID = 1 })
	Mocks.SetNow(100)
	fireTick(env, { amount = 200 })
	liveAura(env, { auraInstanceID = 2 })
	Mocks.SetNow(103)
	fireTick(env, { amount = 200 })
	assert_nil(env.ns.session.learned[774].interval)
end)

T.register("integration: stack change normalizes without double multiply", function()
	local env = newEnv()
	env.ns.learner.ObserveBase(774, 400, 2)
	local d = env.ns.session.learned[774]
	assert_near(d.basePerStack, 200, 1e-9)
	env.ns.learner.ObserveBase(774, 400, 2)
	assert_near(env.ns.session.learned[774].basePerStack, 200, 1e-9)
	d.interval = 3
	liveAura(env, { applications = 3 })
	local hot = env.ns.model.CollectPlayerHoTs(0)
	assert_near(hot.details[1].perTick, 600, 1e-9, "3 stacks x 200")
	assert_near(hot.details[1].amount, 2400, 1e-9, "4 ticks")
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
	seed(env, { interval = 1, basePerStack = 100 })
	Mocks.SetAuras({ { spellId = 33763, applications = Mocks.MakeSecret(), expirationTime = 12, duration = 12, auraInstanceID = 1, sourceUnit = "player" } })
	local hot = env.ns.model.CollectPlayerHoTs(0)
	assert_nil(hot.total)
end)

T.register("integration: missing CLEU is handled gracefully", function()
	local env = newEnv()
	local saved = _G.CombatLogGetCurrentEventInfo
	_G.CombatLogGetCurrentEventInfo = nil
	local ok = pcall(function() Mocks.Fire("COMBAT_LOG_EVENT_UNFILTERED", 100, "SPELL_PERIODIC_HEAL") end)
	assert_true(ok, "no error without CLEU")
	assert_false(env.ns.api.CombatLogAvailable())
	_G.CombatLogGetCurrentEventInfo = saved
end)

T.register("integration: native prediction disabled suppresses", function()
	local env = newEnv()
	seed(env, { interval = 3, basePerStack = 200 })
	liveAura(env)
	env.ab._predOn = false
	local res = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_true(res.suppressed)
	assert_eq(res.reason, "native prediction disabled")
end)

T.register("integration: frame replacement reattaches idempotently", function()
	local env = newEnv()
	env.ns.overlay.Resolve()
	local frame = env.ns.overlay.state.frame
	local parent1 = env.ns.overlay.state.parent
	local newer = Mocks.BuildEUF()
	_G.EllesmereUI._ModuleNS.EllesmereUIUnitFrames.frames.player = newer.player
	env.ns.overlay.Resolve()
	assert_eq(env.ns.overlay.state.frame, frame, "same overlay frame reused")
	assert_true(env.ns.overlay.state.parent ~= parent1, "reparented to new frame")
	local count = 0
	for _, f in ipairs(Mocks.frames) do
		if f._name == "EllesmereUI_HoTPredictionOverlay" then count = count + 1 end
	end
	assert_eq(count, 1, "no duplicate overlay frames")
end)

T.register("integration: native styling copied and overridable", function()
	local env = newEnv()
	env.ns.overlay.Resolve()
	local f = env.ns.overlay.state.frame
	env.ab._predMy:SetStatusBarTexture("Interface\\custom.blp")
	env.ab._predMy:SetStatusBarColor(0.5, 0.5, 0.5)
	env.ns.overlay.RenderValue(100, "test")
	assert_eq(f:GetStatusBarTexture():GetTexture(), "Interface\\custom.blp")
	assert_near(f:GetStatusBarColor(), 0.5, 1e-6)
	env.ns.db.shareNativeStyle = false
	env.ns.db.overlayColor = { 1, 0, 0 }
	env.ns.overlay.RenderValue(100, "test")
	assert_near(select(1, f:GetStatusBarColor()), 1, 1e-6)
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
	env.ns.overlay.Resolve()
	local p2 = f._points[1]
	assert_eq(f:GetOrientation(), "VERTICAL")
	assert_true(f:IsReverseFill())
	assert_eq(p2[1], "TOP")
	assert_eq(p2[3], "BOTTOM")
end)

T.register("integration: commands test/status/debug/off/calibration", function()
	local env = newEnv()
	local ns = env.ns
	ns.HandleCommand("test 1000")
	assert_eq(ns.session.fake.value, 1000)
	ns.overlay.Tick()
	assert_near(ns.overlay.state.frame:GetValue(), 1000, 1e-9)
	assert_true(ns.overlay.state.frame:IsShown())
	ns.HandleCommand("status")
	local joined = table.concat(Mocks.chat, "\n")
	assert_true(joined:match("enabled=") ~= nil, "status lists settings")
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
	ns.HandleCommand("test off")
	assert_nil(ns.session.fake)
end)

T.register("integration: excludes-HoT opt-in gives direct+hot=1400", function()
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
	env.ns.HandleCommand("test3 600 800")
	assert_true(env.ns.db.assumeApiExcludesHoTs)
	assert_eq(env.ns.session.fake.hot, 800)
end)

T.register("integration: fake test is session-only and never persisted", function()
	local env = newEnv()
	env.ns.HandleCommand("test 1000")
	assert_not_nil(env.ns.session.fake)
	-- simulate a saved variable that somehow carries the flag
	_G.EllesmereUI_HoTPredictionDB = { showFake = true, enabled = true }
	env.ns.InitDatabase()
	assert_nil(env.ns.db.showFake)
	-- a fresh load starts with no fake active
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
	env.ns.overlay.Tick()
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
	env.ns.overlay.Tick()
	assert_eq(#Mocks.chat, before, "no chat from tick while debug off")
end)

T.register("integration: vehicle frame is never painted", function()
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
	env.player._euiUnit = "player"
	local res2 = env.ns.model.Evaluate(0, { ab = env.ab })
	assert_true(res2.added > 0, "paints player again")
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
