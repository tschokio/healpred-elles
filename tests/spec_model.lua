-- tests/spec_model.lua
-- Pure-model tests: tick scheduling, per-stack amount, overlap policy.

local function mkEnv()
	return Mocks.NewEnv()
end

local function aura(over)
	local a = {
		spellID = 774, instanceID = 1, stacks = 1,
		expirationTime = 12, duration = 12, sourceUnit = "player",
	}
	for k, v in pairs(over or {}) do a[k] = v end
	return a
end

T.register("model: ticks full duration grid = 4, last at expiry", function()
	local env = mkEnv()
	local n, err, times = env.ns.model.ComputeTicks(aura(), { interval = 3 }, 0)
	assert_eq(err, nil, "no error")
	assert_eq(n, 4, "4 ticks")
	assert_near(times[1], 3, 1e-9)
	assert_near(times[4], 12, 1e-9, "tick at expiry included")
end)

T.register("model: tick boundary at expiry and just past", function()
	local env = mkEnv()
	local m = env.ns.model
	assert_eq((m.ComputeTicks(aura(), { interval = 3 }, 9)), 1, "only expiry tick left")
	assert_eq((m.ComputeTicks(aura(), { interval = 3 }, 12)), 0, "at expiry = none left")
	assert_eq((m.ComputeTicks(aura(), { interval = 3 }, 12 + 3e-6)), 0, "past expiry = none")
	assert_eq((m.ComputeTicks(aura(), { interval = 3 }, 12 - 3e-6)), 1, "just before expiry = one")
end)

T.register("model: observed phase anchored on last tick", function()
	local env = mkEnv()
	local n, _err, times = env.ns.model.ComputeTicks(aura(), { interval = 3, lastTick = 9, lastInstanceID = 1 }, 9.1)
	assert_eq(n, 1)
	assert_near(times[1], 12, 1e-9)
end)

T.register("model: refresh resets phase to application grid", function()
	local env = mkEnv()
	local a = aura({ instanceID = 2 })
	local n, _err, times = env.ns.model.ComputeTicks(a, { interval = 3, lastTick = 9, lastInstanceID = 1 }, 0.1)
	assert_eq(n, 4, "grid from application")
	assert_near(times[1], 3, 1e-9)
end)

T.register("model: no interval withholds", function()
	local env = mkEnv()
	local n, err = env.ns.model.ComputeTicks(aura(), {}, 0)
	assert_nil(n)
	assert_true(tostring(err):match("interval") ~= nil, "reason mentions interval")
end)

T.register("model: secret timing withholds without arithmetic", function()
	local env = mkEnv()
	local n, err = env.ns.model.ComputeTicks(aura({ secretTiming = true }), { interval = 3 }, 0)
	assert_nil(n)
	assert_true(tostring(err):match("secret") ~= nil)
end)

T.register("model: estimate 200 x 4 = 800", function()
	local env = mkEnv()
	local res, err = env.ns.model.ComputeAuraEstimate(aura(), nil, { interval = 3, basePerStack = 200 }, 0)
	assert_eq(err, nil)
	assert_eq(res.ticks, 4)
	assert_near(res.amount, 800, 1e-9)
end)

T.register("model: stack normalization multiplies per-stack base only", function()
	local env = mkEnv()
	local res = env.ns.model.ComputeAuraEstimate(aura({ stacks = 3 }), nil, { interval = 3, basePerStack = 200 }, 0)
	assert_near(res.perTick, 600, 1e-9)
end)

T.register("model: stacking HoT with secret stacks withholds", function()
	local env = mkEnv()
	local meta = env.ns.spells.Meta(33763)
	assert_true(meta and meta.stacksMatter, "lifebloom stacks matter")
	local res, err = env.ns.model.ComputeAuraEstimate(aura({ spellID = 33763, secretStacks = true }), meta, { interval = 1, basePerStack = 100 }, 0)
	assert_nil(res)
	assert_true(tostring(err):match("stacks") ~= nil)
end)

T.register("model: overlap conservative subtract", function()
	local env = mkEnv()
	local added = env.ns.model.ComputeAdded(800, { total = 300 }, nil, {})
	assert_near(added, 500, 1e-9)
end)

T.register("model: overlap floor at zero", function()
	local env = mkEnv()
	local added = env.ns.model.ComputeAdded(800, { total = 1000 }, nil, {})
	assert_eq(added, 0)
end)

T.register("model: overlap excludes-HoT mode appends full estimate", function()
	local env = mkEnv()
	local added = env.ns.model.ComputeAdded(800, { total = 600 }, nil, { excludes = true })
	assert_near(added, 800, 1e-9)
end)

T.register("model: overlap unavailable native suppresses", function()
	local env = mkEnv()
	local added, reason = env.ns.model.ComputeAdded(800, { reason = "secret" }, nil, {})
	assert_nil(added)
	assert_true(tostring(reason):match("unavailable") ~= nil)
end)

T.register("model: clamp into missing health (4500/5000, incoming 300 -> 200)", function()
	local env = mkEnv()
	local added, reason = env.ns.model.ComputeAdded(800, { total = 300 }, { health = 4500, max = 5000 }, {})
	assert_near(added, 200, 1e-9)
	assert_true(tostring(reason):match("clamp") ~= nil)
end)

T.register("model: full health clamps to zero", function()
	local env = mkEnv()
	local added = env.ns.model.ComputeAdded(800, { total = 300 }, { health = 5000, max = 5000 }, {})
	assert_eq(added, 0)
end)

T.register("model: secret values refuse arithmetic and are detected", function()
	local env = mkEnv()
	local s = Mocks.MakeSecret()
	assert_true(env.ns.isSecret(s), "detected as secret")
	assert_nil(env.ns.toNumber(s), "toNumber refuses secret")
	assert_error(function() return s + 1 end, "secret arithmetic must raise")
	assert_error(function() return s < 1 end, "secret comparison must raise")
end)
