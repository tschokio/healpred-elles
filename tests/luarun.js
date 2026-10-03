// tests/luarun.js
// Runs tests/run.lua under the pure-JS Lua VM fengari when no native Lua
// binary is available. fengari is NOT vendored into this repository: point
// HOT_LUA_NODE_PATH at it, or let tests/run_tests.sh fetch it into a cache dir.
"use strict";

const fs = require("fs");
const path = require("path");
const os = require("os");

function loadFengari() {
	const candidates = [];
	if (process.env.HOT_LUA_NODE_PATH) candidates.push(process.env.HOT_LUA_NODE_PATH);
	candidates.push("fengari");
	candidates.push(path.join(os.homedir(), ".cache", "ai-coding-v2", "tmp", "luatools", "tools", "node_modules", "fengari"));
	candidates.push("/tmp/hot-lua-tools/node_modules/fengari");
	for (const c of candidates) {
		try { return require(c); } catch (e) { /* try next */ }
	}
	return null;
}

const fengari = loadFengari();
if (!fengari) {
	console.error("fengari not found. Set HOT_LUA_NODE_PATH or run tests/run_tests.sh which fetches it.");
	process.exit(77);
}

const { lua, lauxlib, lualib, to_luastring, to_jsstring } = fengari;

const root = path.resolve(__dirname, "..");

function walk(dir, out) {
	for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
		const full = path.join(dir, entry.name);
		if (entry.isDirectory()) {
			if (entry.name === "node_modules" || entry.name === ".git") continue;
			walk(full, out);
		} else if (/\.(lua|toc)$/.test(entry.name)) {
			out.push(full);
		}
	}
}
const files = [];
walk(path.join(root, "tests"), files);
walk(path.join(root, "EllesmereUI_HoTPrediction"), files);

const L = lauxlib.luaL_newstate();
lualib.luaL_openlibs(L);

// __HOT_TEST_SOURCES[absPath] = source
lua.lua_newtable(L);
for (const f of files) {
	const src = fs.readFileSync(f, "utf8");
	lua.lua_pushstring(L, to_luastring(src));
	lua.lua_setfield(L, -2, to_luastring(f));
}
lua.lua_setglobal(L, to_luastring("__HOT_TEST_SOURCES"));

lua.lua_pushstring(L, to_luastring(root));
lua.lua_setglobal(L, to_luastring("__HOT_ROOT"));

const runSource = fs.readFileSync(path.join(root, "tests", "run.lua"), "utf8");
const status = lauxlib.luaL_dostring(L, to_luastring(runSource));
if (status !== lua.LUA_OK) {
	console.error("LUA ERROR: " + to_jsstring(lua.lua_tostring(L, -1)));
	process.exit(1);
}

lua.lua_getglobal(L, to_luastring("__HOT_EXIT"));
const code = lua.lua_isinteger(L, -1) ? lua.lua_tointeger(L, -1) : 1;
lua.lua_pop(L, 1);
process.exit(code === 0 ? 0 : 1);
