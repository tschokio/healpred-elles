-- EllesmereUI_HoTPrediction / Core.lua
-- Namespace, settings, event plumbing, startup, slash commands.
-- Keep this file free of anything that assumes a live WoW client: it must be
-- loadable and testable under a plain Lua interpreter with mocked globals.

local addonName, ns = ...

ns.name = addonName
ns.version = "0.1.0"
ns.session = {}
ns.debugEnabled = false
ns.inCombat = false
ns.started = false

------------------------------------------------------------------------------
-- small helpers
------------------------------------------------------------------------------

-- WoW 11+/Midnight can hand out "secret" values that raise on any arithmetic,
-- comparison or table indexing. Never touch them: detect and refuse.
function ns.isSecret(v)
	local f = issecretvalue
	if type(f) == "function" then
		local ok, res = pcall(f, v)
		if ok then return res and true or false end
	end
	return false
end

-- Return a plain number or nil (secret values and non-numbers are refused).
function ns.toNumber(v)
	if v == nil then return nil end
	if ns.isSecret(v) then return nil end
	if type(v) == "number" then return v end
	return nil
end

function ns.now()
	local t = GetTime and GetTime() or 0
	return ns.toNumber(t) or 0
end

function ns.print(msg)
	local line = "|cff66f366[HoTPred]|r " .. tostring(msg)
	if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
		DEFAULT_CHAT_FRAME:AddMessage(line)
	else
		print(line)
	end
end

function ns.debug(...)
	if not ns.db then return end
	if ns.db.debug or ns.debugEnabled then
		local parts = {}
		for i = 1, select("#", ...) do
			parts[#parts + 1] = tostring((select(i, ...)))
		end
		ns.print("|cff999999" .. table.concat(parts, " ") .. "|r")
	end
end

function ns.round(v, places)
	local n = ns.toNumber(v)
	if not n then return nil end
	local mult = 10 ^ (places or 0)
	return math.floor(n * mult + 0.5) / mult
end

-- Deep-merge defaults into a table, returning the table.
function ns.applyDefaults(dst, defaults)
	dst = dst or {}
	for k, v in pairs(defaults) do
		if type(v) == "table" then
			dst[k] = ns.applyDefaults(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
	return dst
end

------------------------------------------------------------------------------
-- settings
------------------------------------------------------------------------------

-- Session-only state. Nothing here is written to SavedVariables, so a reload
-- can never resurrect a fake test value or stale learned gear numbers.
function ns.resetSession()
	ns.session = {
		learned = {},      -- [spellID] = interval/base samples + last tick phase
		auraCache = {},    -- [instanceID] = aura record (latest read)
		lastTicksAt = {},  -- [spellID] = { time =, instanceID = }
		fake = nil,        -- active fake overlay, never persisted
		lastSuppress = nil,
		lastStatus = nil,
	}
end

ns.DEFAULTS = {
	enabled = true,
	debug = false,
	alpha = 0.60,
	shareNativeStyle = true,
	colorMine = { 102 / 255, 243 / 255, 102 / 255 },
	amountMode = "total",          -- "total" (CLEU amount already includes overheal) or "effective"
	assumeApiExcludesHoTs = false, -- opt-in: user verified runtime adds direct + HoT
	colorOther = { 40 / 255, 170 / 255, 40 / 255 },
	overlayColor = { 1.0, 0.82, 0.0 }, -- our own appended segment
	intervalOverrides = {},        -- [spellID] = seconds (user calibration only)
	extraSpells = {},              -- [spellID] = { name =, family = }
	removedSpells = {},            -- [spellID] = true
	requireNativePrediction = true, -- v1 requires the native prediction bars
	-- "showFake" is intentionally NOT a real default: tests never persist.
}

function ns.InitDatabase()
	if type(EllesmereUI_HoTPredictionDB) ~= "table" then
		EllesmereUI_HoTPredictionDB = {}
	end
	ns.db = ns.applyDefaults(EllesmereUI_HoTPredictionDB, ns.DEFAULTS)
	-- A fake test is session-only by design.
	ns.db.showFake = nil
	ns.debugEnabled = ns.db.debug and true or false
end

------------------------------------------------------------------------------
-- events
------------------------------------------------------------------------------

ns.eventHandlers = {}

function ns.on(event, fn)
	local list = ns.eventHandlers[event]
	if not list then
		list = {}
		ns.eventHandlers[event] = list
	end
	list[#list + 1] = fn
end

function ns.dispatch(event, ...)
	local list = ns.eventHandlers[event]
	if not list then return end
	for i = 1, #list do
		local ok, err = pcall(list[i], event, ...)
		if not ok then
			ns.debug("handler error for " .. tostring(event) .. ": " .. tostring(err))
		end
	end
end

local function ensureEventFrame()
	if ns.eventFrame then return ns.eventFrame end
	if type(CreateFrame) ~= "function" then return nil end
	local f = CreateFrame("Frame")
	ns.eventFrame = f
	f:SetScript("OnEvent", function(_, event, ...)
		ns.dispatch(event, ...)
	end)
	return f
end

function ns.register(event)
	local f = ensureEventFrame()
	if f and f.RegisterEvent then
		pcall(f.RegisterEvent, f, event)
	end
end

function ns.unregister(event)
	local f = ns.eventFrame
	if f and f.UnregisterEvent then f:UnregisterEvent(event) end
end

------------------------------------------------------------------------------
-- startup
------------------------------------------------------------------------------

-- Called once after the matching ADDON_LOADED. Attempts a real init and, only
-- if everything the overlay depends on is absent, prints a single useful line.
function ns.Startup()
	if ns.started then return end
	ns.started = true

	ns.resetSession()
	ns.InitDatabase()

	ns.register("PLAYER_LOGIN")
	ns.register("PLAYER_ENTERING_WORLD")
	ns.register("PLAYER_REGEN_DISABLED")
	ns.register("PLAYER_REGEN_ENABLED")
	ns.register("UNIT_AURA")
	ns.register("PLAYER_TARGET_CHANGED")
	ns.register("COMBAT_LOG_EVENT_UNFILTERED") -- may be forbidden; guarded downstream

	if ns.learner and ns.learner.Setup then ns.learner.Setup() end
	if ns.overlay and ns.overlay.Setup then ns.overlay.Setup() end

	if ns.db and ns.db.debug then
		ns.print("v" .. ns.version .. " loaded (debug). /euihot help for commands.")
	end
end

-- Single, useful failure line after the real init attempts; otherwise quiet.
function ns.ReportStartupStatus()
	if ns.startupReported then return end
	ns.startupReported = true
	local euf = ns.api and ns.api.GetEUF()
	local ab = ns.api and ns.api.GetAbsorbFrame()
	if not euf or not ab then
		ns.print("EllesmereUIUnitFrames prediction frame not found; overlay idle. Enable native heal prediction, then /reload.")
	elseif ns.db and ns.db.debug then
		ns.print("attached to EllesmereUIUnitFrames native prediction.")
	end
end

ns.on("ADDON_LOADED", function(_, loaded)
	if loaded == ns.name then
		ns.Startup()
	end
end)

ns.on("PLAYER_LOGIN", function()
	ns.inCombat = InCombatLockdown and InCombatLockdown() and true or false
	if ns.overlay and ns.overlay.Resolve then ns.overlay.Resolve() end
	if ns.ReportStartupStatus then ns.ReportStartupStatus() end
end)

ns.on("PLAYER_ENTERING_WORLD", function()
	if ns.overlay and ns.overlay.Resolve then ns.overlay.Resolve() end
end)

ns.on("PLAYER_REGEN_DISABLED", function()
	ns.inCombat = true
end)

ns.on("PLAYER_REGEN_ENABLED", function()
	ns.inCombat = false
	if ns.overlay and ns.overlay.ApplyPending then ns.overlay.ApplyPending() end
end)

ns.on("UNIT_AURA", function(_, unit)
	if unit == "player" and ns.api and ns.api.InvalidateAuraCache then
		ns.api.InvalidateAuraCache()
	end
end)

ns.on("PLAYER_TARGET_CHANGED", function()
	if ns.overlay and ns.overlay.Resolve then ns.overlay.Resolve() end
end)

------------------------------------------------------------------------------
-- slash commands
------------------------------------------------------------------------------

local function parseNumber(s)
	return tonumber(s)
end

function ns.HandleCommand(input)
	local raw = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = raw:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()
	local args = {}
	for word in rest:gmatch("%S+") do args[#args + 1] = word end

	if cmd == "help" or cmd == "" then
		ns.print("commands: test <v> | test off | test3 <direct> <hot> | status | debug [on|off] | alpha <a> | color <my|other|overlay> <r> <g> <b> | interval <id> <s> | spell add|remove <id> [name] | amountmode total|effective | excludehots on|off | reset | help")
		return
	elseif cmd == "test" then
		local v = parseNumber(args[1])
		if args[1] and args[1]:lower() == "off" then
			ns.session.fake = nil
			ns.print("fake test off.")
		elseif v then
			ns.session.fake = { value = v }
			ns.print(string.format("fake overlay appended: +%s (session only).", tostring(v)))
		else
			ns.print("usage: /euihot test <value> | test off")
		end
		return
	elseif cmd == "test3" then
		local direct = parseNumber(args[1])
		local hot = parseNumber(args[2])
		if direct and hot then
			ns.session.fake = { direct = direct, hot = hot, expectTotal = direct + hot, excludes = true }
			ns.db.assumeApiExcludesHoTs = true
			ns.print(string.format("test3: direct=%s hot=%s -> expect %s (excludes-HoT mode ON).", tostring(direct), tostring(hot), tostring(direct + hot)))
		else
			ns.print("usage: /euihot test3 <direct> <hot>")
		end
		return
	elseif cmd == "status" then
		ns.EmitStatus()
		return
	elseif cmd == "debug" then
		local v = (args[1] or ""):lower()
		if v == "on" then
			ns.db.debug = true
			ns.debugEnabled = true
		elseif v == "off" then
			ns.db.debug = false
			ns.debugEnabled = false
		else
			ns.db.debug = not ns.db.debug
			ns.debugEnabled = ns.db.debug
		end
		ns.print("debug " .. (ns.db.debug and "on" or "off") .. ".")
		if ns.db.debug then ns.EmitStatus() end
		return
	elseif cmd == "alpha" then
		local a = parseNumber(args[1])
		if a and a >= 0 and a <= 1 then
			ns.db.alpha = a
			ns.print("alpha = " .. tostring(a))
		else
			ns.print("usage: /euihot alpha <0..1>")
		end
		return
	elseif cmd == "color" then
		local which = (args[1] or ""):lower()
		local r, g, b = parseNumber(args[2]), parseNumber(args[3]), parseNumber(args[4])
		if (which == "my" or which == "other" or which == "overlay") and r and g and b then
			local key = "overlayColor"
			if which == "my" then key = "colorMine" elseif which == "other" then key = "colorOther" end
			ns.db[key] = { r, g, b }
			ns.print("color " .. which .. " = " .. table.concat({ tostring(r), tostring(g), tostring(b) }, ","))
		else
			ns.print("usage: /euihot color <my|other|overlay> <r> <g> <b>  (0..1)")
		end
		return
	elseif cmd == "interval" then
		local id = parseNumber(args[1])
		local secs = parseNumber(args[2])
		if id and secs and secs > 0 then
			ns.db.intervalOverrides[id] = secs
			ns.print(string.format("interval override spell %s = %.2fs", tostring(id), secs))
		else
			ns.print("usage: /euihot interval <spellID> <seconds>")
		end
		return
	elseif cmd == "spell" then
		local op = (args[1] or ""):lower()
		local id = parseNumber(args[2])
		if id and op == "add" then
			ns.db.extraSpells[id] = { name = args[3] or ("spell " .. id), family = "custom" }
			ns.db.removedSpells[id] = nil
			ns.print("registered spell " .. id .. ".")
		elseif id and op == "remove" then
			ns.db.removedSpells[id] = true
			ns.print("removed spell " .. id .. ".")
		else
			ns.print("usage: /euihot spell add|remove <spellID> [name]")
		end
		return
	elseif cmd == "amountmode" then
		local m = (args[1] or ""):lower()
		if m == "total" or m == "effective" then
			ns.db.amountMode = m
			ns.print("amount mode = " .. m .. " (adapter assumption).")
		else
			ns.print("usage: /euihot amountmode total|effective")
		end
		return
	elseif cmd == "excludehots" then
		local v = (args[1] or ""):lower()
		ns.db.assumeApiExcludesHoTs = (v == "on" or v == "true" or v == "1")
		ns.print("assume API excludes HoTs = " .. tostring(ns.db.assumeApiExcludesHoTs))
		return
	elseif cmd == "reset" then
		ns.resetSession()
		ns.print("session learning reset.")
		return
	end

	ns.print("unknown command '" .. tostring(cmd) .. "'. /euihot help")
end

function ns.SetupSlash()
	if type(SlashCmdList) == "nil" then return end
	SLASH_ELLESMEREUIHOTPRED1 = "/euihot"
	SLASH_ELLESMEREUIHOTPRED2 = "/hotpred"
	SlashCmdList["ELLESMEREUIHOTPRED"] = function(msg)
		ns.HandleCommand(msg)
	end
end

-- status is a concise user report (not a firehose); debug adds internals.
function ns.EmitStatus()
	if not ns.db then ns.InitDatabase() end
	local lines = {}
	lines[#lines + 1] = string.format("enabled=%s debug=%s mode=%s excludeHoTs=%s",
		tostring(ns.db.enabled), tostring(ns.db.debug), tostring(ns.db.amountMode), tostring(ns.db.assumeApiExcludesHoTs))

	local ab, player = nil, nil
	if ns.api then ab, player = ns.api.GetAbsorbFrame() end
	lines[#lines + 1] = "euf=" .. tostring(ns.api and ns.api.GetEUF() ~= nil)
		.. " playerFrame=" .. tostring(player ~= nil)
		.. " nativePred=" .. tostring(ab ~= nil and ab._predOn and true or false)
	if ab then
		local native = ns.api.GetNativeIncoming and ns.api.GetNativeIncoming(ab) or nil
		if native and native.total then
			lines[#lines + 1] = string.format("native incoming mine=%s other=%s (src=%s)",
				tostring(native.mine), tostring(native.others), tostring(native.source))
		else
			lines[#lines + 1] = "native incoming unavailable: " .. tostring(native and native.reason or "nil")
		end
	end
	if ns.session.lastSuppress then
		lines[#lines + 1] = "last suppress: " .. tostring(ns.session.lastSuppress)
	end
	local learnedCount = 0
	local learnedBits = {}
	for id, d in pairs(ns.session.learned or {}) do
		learnedCount = learnedCount + 1
		if learnedCount <= 6 then
			learnedBits[#learnedBits + 1] = string.format("%s[int=%s base=%s n=%s]",
				tostring(id), tostring(ns.round(d.interval, 2)), tostring(ns.round(d.basePerStack, 1)), tostring(d.baseCount or 0))
		end
	end
	lines[#lines + 1] = "learned spells=" .. tostring(learnedCount)
	if #learnedBits > 0 then
		lines[#lines + 1] = "  " .. table.concat(learnedBits, " ")
	end
	if ns.session.fake then
		local f = ns.session.fake
		lines[#lines + 1] = "fake active=" .. tostring(f.value or (f.direct .. "+" .. f.hot))
	end

	if ns.db.debug then
		pcall(function() ns.EmitDebugDetails(lines, ab, player) end)
	end

	ns.print(table.concat(lines, "\n"))
end

-- Rich on-demand diagnostics used only while debug is enabled.
function ns.EmitDebugDetails(lines, ab, player)
	local n = ns.toNumber
	local function add(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
	add("build=%s lua=%s", ns.version, tostring(_VERSION))
	add("apis C_UnitAuras=%s cleu=%s issecretvalue=%s hooksecurefunc=%s",
		tostring(type(C_UnitAuras) == "table" and C_UnitAuras.GetAuraDataByIndex ~= nil),
		tostring(ns.api.CombatLogAvailable()),
		tostring(type(issecretvalue) == "function"),
		tostring(type(hooksecurefunc) == "function"))
	add("policy=%s amountMode=%s alpha=%.2f shareNativeStyle=%s",
		ns.db.assumeApiExcludesHoTs and "excludes-HoT(opt-in)" or "conservative max(0,hot-native)",
		tostring(ns.db.amountMode), ns.db.alpha, tostring(ns.db.shareNativeStyle))
	local hp = select(3, ns.api.GetAbsorbFrame())
	if hp then
		local w, h = n(hp.GetWidth and hp:GetWidth()), n(hp.GetHeight and hp:GetHeight())
		local mn, mx
		if hp.GetMinMaxValues then mn, mx = hp:GetMinMaxValues() end
		add("hp dims=%sx%s range=%s..%s", tostring(w), tostring(h), tostring(n(mn)), tostring(n(mx)))
	end
	if ab then
		local info = ns.api.GetBarInfo(ab._predMy)
		if info then
			add("predMy orient=%s reversed=%s level=%s texture=%s", tostring(info.orientation), tostring(info.reversed), tostring(info.level), tostring(info.texture))
		end
		local nat = ns.api.GetNativeIncoming(ab)
		add("native mine=%s other=%s total=%s src=%s reason=%s",
			tostring(nat.mine), tostring(nat.others), tostring(nat.total), tostring(nat.source), tostring(nat.reason))
	end
	local st = ns.session.lastStatus
	if st then
		add("tick hot=%s added=%s nativeTotal=%s reason=%s",
			tostring(st.hotEstimate), tostring(st.added),
			tostring(st.native and st.native.total), tostring(st.reason))
	end
	local f = ns.overlay and ns.overlay.state.frame
	if f then
		local v = n(f.GetValue and f:GetValue())
		add("overlay shown=%s value=%s", tostring(f:IsShown()), tostring(v))
	end
end

------------------------------------------------------------------------------
-- The event frame must exist at file-load time so ADDON_LOADED (our own)
-- can be received. Everything else is registered from Startup.
------------------------------------------------------------------------------
ensureEventFrame()
ns.register("ADDON_LOADED")
ns.SetupSlash()
