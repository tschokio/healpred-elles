-- tests/harness.lua
-- Minimal deterministic test runner. No external dependencies.

local T = { tests = {}, pass = 0, fail = 0, failures = {} }
_G.T = T

function T.register(name, fn)
	T.tests[#T.tests + 1] = { name = name, fn = fn }
end

function T.run()
	for i = 1, #T.tests do
		local tc = T.tests[i]
		local ok, err = pcall(tc.fn)
		if ok then
			T.pass = T.pass + 1
			print("PASS " .. tc.name)
		else
			T.fail = T.fail + 1
			T.failures[#T.failures + 1] = { name = tc.name, err = tostring(err) }
			print("FAIL " .. tc.name .. " :: " .. tostring(err))
		end
	end
	print(string.format("RESULT pass=%d fail=%d total=%d", T.pass, T.fail, #T.tests))
end

function assert_true(v, msg)
	if not v then error("expected truthy: " .. tostring(msg), 2) end
end

function assert_false(v, msg)
	if v then error("expected falsy: " .. tostring(msg), 2) end
end

function assert_eq(a, b, msg)
	if a ~= b then
		error(string.format("expected %s == %s (%s)", tostring(a), tostring(b), tostring(msg)), 2)
	end
end

function assert_near(a, b, eps, msg)
	eps = eps or 1e-6
	if type(a) ~= "number" or math.abs(a - b) > eps then
		error(string.format("expected %s ~= %s (eps %s) (%s)", tostring(a), tostring(b), tostring(eps), tostring(msg)), 2)
	end
end

function assert_nil(a, msg)
	if a ~= nil then error("expected nil, got " .. tostring(a) .. " (" .. tostring(msg) .. ")", 2) end
end

function assert_not_nil(a, msg)
	if a == nil then error("expected non-nil (" .. tostring(msg) .. ")", 2) end
end

function assert_error(fn, msg)
	local ok = pcall(fn)
	if ok then error("expected an error (" .. tostring(msg) .. ")", 2) end
end
