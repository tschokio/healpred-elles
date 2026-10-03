-- tests/run.lua
-- Entry point. Run from the repository root:
--   lua tests/run.lua
-- or, without a Lua binary, via the bundled fengari runner:
--   node tests/luarun.js
-- Returns/prints a RESULT line and sets __HOT_EXIT for the JS runner.

local function readSource(path)
	-- fengari runner injects a source map; a real interpreter uses io.
	if _G.__HOT_TEST_SOURCES and _G.__HOT_TEST_SOURCES[path] then
		return _G.__HOT_TEST_SOURCES[path]
	end
	local f = io and io.open and io.open(path, "r")
	if not f then return nil end
	local src = f:read("*a")
	f:close()
	return src
end
_G.ReadFile = readSource

-- Locate the repository root.
local root = _G.__HOT_ROOT
if not root then
	local src = (debug.getinfo(1, "S") or {}).source or "@."
	root = src:match("@(.*)/tests/run%.lua") or "."
end
_G.__HOT_ROOT = root

local function loadRel(rel, ...)
	local path = root .. "/" .. rel
	local src = readSource(path)
	if not src then error("cannot read " .. path) end
	local chunk = assert(load(src, "@" .. path))
	return chunk(...)
end

loadRel("tests/harness.lua")
loadRel("tests/wowenv.lua")
loadRel("tests/spec_model.lua")
loadRel("tests/spec_integration.lua")
loadRel("tests/spec_debugwindow.lua")
loadRel("tests/spec_estimates.lua")
loadRel("tests/spec_druid.lua")
loadRel("tests/spec_priest_shaman.lua")

T.run()
_G.__HOT_EXIT = (T.fail == 0) and 0 or 1
return _G.__HOT_EXIT
