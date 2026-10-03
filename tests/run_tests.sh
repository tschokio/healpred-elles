#!/usr/bin/env bash
# tests/run_tests.sh
# Runs the deterministic test suite. Prefers a native Lua interpreter; falls
# back to the node + fengari runner, fetching fengari into a local cache (never
# into the repository) when it is not already present.
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT" || exit 1

for LUA in lua5.4 lua5.3 lua5.1 lua luajit; do
	if command -v "$LUA" >/dev/null 2>&1; then
		echo "== running tests with $LUA =="
		exec "$LUA" tests/run.lua
	fi
done

if command -v node >/dev/null 2>&1; then
	CACHE="${HOME}/.cache/ai-coding-v2/tmp/luatools"
	FENG="$CACHE/tools/node_modules/fengari"
	if [ ! -f "$FENG/src/fengari.js" ]; then
		echo "== no Lua binary; fetching fengari into local cache =="
		mkdir -p "$CACHE/tools/node_modules"
		TMPD="$(mktemp -d)"
		curl -sSL "https://registry.npmjs.org/fengari/-/fengari-0.1.5.tgz" -o "$TMPD/fengari.tgz" \
			&& tar -xzf "$TMPD/fengari.tgz" -C "$TMPD" \
			&& rm -rf "$FENG" && cp -r "$TMPD/package" "$FENG"
		for dep in "sprintf-js/-/sprintf-js-1.1.3" "readline-sync/-/readline-sync-1.4.10" "tmp/-/tmp-0.2.5"; do
			name="$(echo "$dep" | cut -d/ -f1)"
			[ -d "$CACHE/tools/node_modules/$name" ] && continue
			curl -sSL "https://registry.npmjs.org/$dep.tgz" -o "$TMPD/$name.tgz" \
				&& tar -xzf "$TMPD/$name.tgz" -C "$CACHE/tools/node_modules" \
				&& rm -rf "$CACHE/tools/node_modules/$name" \
				&& mv "$CACHE/tools/node_modules/package" "$CACHE/tools/node_modules/$name"
		done
		rm -rf "$TMPD"
	fi
	echo "== running tests with node + fengari =="
	HOT_LUA_NODE_PATH="$FENG" exec node tests/luarun.js
fi

echo "No Lua interpreter and no node available; cannot run Lua tests." >&2
exit 77
