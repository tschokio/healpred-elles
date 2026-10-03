-- EllesmereUI_HoTPrediction / Core.lua
-- Namespace, settings, event plumbing, startup, slash commands.
-- Keep this file free of anything that assumes a live WoW client: it must be
-- loadable and testable under a plain Lua interpreter with mocked globals.

local addonName, ns = ...

ns.name = addonName
ns.version = "0.2.0"
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

-- Return a plain finite number or nil.
-- Secret values are refused BEFORE the nil check (their equality/comparison can
-- be unreliable) and non-finite numbers (NaN / +/-inf) are refused too.
function ns.toNumber(v)
	if ns.isSecret(v) then return nil end
	if v == nil then return nil end
	if type(v) ~= "number" then return nil end
	if v ~= v then return nil end -- NaN
	if v == math.huge or v == -math.huge then return nil end
	return v
end

-- Explicit pack preserving nil holes and trailing false: { n =, [1]=, ... }.
function ns.pack(...)
	return { n = select("#", ...), ... }
end

function ns.now()
	local t = GetTime and GetTime() or 0
	return ns.toNumber(t) or 0
end

-- A finite, non-negative number (for command validation).
function ns.isFinite(v)
	local n = ns.toNumber(v)
	return n ~= nil and n >= 0 and n < math.huge
end

function ns.isPositiveInt(v)
	local n = ns.toNumber(v)
	return n ~= nil and n > 0 and n == math.floor(n)
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
		learned = {},      -- [spellID] = interval/totals + last tick phase
		auraCache = nil,   -- list of aura records, rebuilt on invalidation
		lastTicksAt = {},  -- [spellID] = { time =, instanceID = }
		fake = nil,        -- active fake overlay, never persisted
		lastSuppress = nil,
		lastStatus = nil,
	}
	ns.capabilities = { events = {}, cleu = nil, cleuError = nil }
end

ns.DEFAULTS = {
	enabled = true,
	debug = false,
	alpha = 0.60,                  -- our segment's opacity (composited with native)
	shareNativeStyle = true,       -- inherit native texture/color (default)
	overlayColor = { 1.0, 0.82, 0.0 },
	amountMode = "total",          -- "total" (CLEU amount includes overheal) or "effective"
	assumeApiExcludesHoTs = false, -- opt-in: user verified native already excludes HoTs
	intervalOverrides = {},        -- [spellID] = seconds (user calibration only)
	extraSpells = {},              -- [spellID] = { name =, family = }
	removedSpells = {},            -- [spellID] = true
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

-- Register an event and RECORD whether the client accepted it. A forbidden or
-- missing event is a capability failure the user must be able to see.
function ns.register(event)
	local f = ensureEventFrame()
	if not f or not f.RegisterEvent then
		ns.capabilities = ns.capabilities or { events = {} }
		ns.capabilities.events[event] = false
		return false
	end
	local ok = pcall(f.RegisterEvent, f, event)
	ns.capabilities = ns.capabilities or { events = {} }
	ns.capabilities.events[event] = ok and true or false
	return ok and true or false
end

function ns.eventRegistered(event)
	return ns.capabilities and ns.capabilities.events and ns.capabilities.events[event] == true
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
	ns.register("UNIT_HEALTH")
	ns.register("UNIT_MAXHEALTH")
	ns.register("UNIT_HEAL_PREDICTION")
	ns.register("UNIT_HEAL_ABSORB_AMOUNT_CHANGED")
	ns.register("COMBAT_LOG_EVENT_UNFILTERED") -- may be forbidden; guarded downstream
	ns.register("PLAYER_EQUIPMENT_CHANGED")
	ns.register("ACTIVE_TALENT_GROUP_CHANGED")
	ns.register("SPELLS_CHANGED")

	ns.capabilities.cleu = ns.api and ns.api.CombatLogAvailable() or false

	if ns.learner and ns.learner.Setup then ns.learner.Setup() end
	if ns.overlay and ns.overlay.Setup then ns.overlay.Setup() end

	if not ns.capabilities.cleu then
		ns.capabilities.cleuError = "CombatLogGetCurrentEventInfo unavailable"
	end

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
	if ns.api and ns.api.InvalidateAuraCache then ns.api.InvalidateAuraCache() end
	if ns.overlay then
		if ns.overlay.InvalidateStructure then ns.overlay.InvalidateStructure() end
		if ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
	end
	if ns.ReportStartupStatus then ns.ReportStartupStatus() end
end)

ns.on("PLAYER_ENTERING_WORLD", function()
	if ns.api and ns.api.InvalidateAuraCache then ns.api.InvalidateAuraCache() end
	if ns.overlay then
		if ns.overlay.InvalidateStructure then ns.overlay.InvalidateStructure() end
		if ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
	end
end)

ns.on("PLAYER_REGEN_DISABLED", function()
	ns.inCombat = true
end)

ns.on("PLAYER_REGEN_ENABLED", function()
	ns.inCombat = false
	if ns.overlay and ns.overlay.ApplyPending then ns.overlay.ApplyPending() end
end)

-- Aura cache is invalidated ONLY for the player's own auras. Unrelated units and
-- the paint timer must never force a full rescan.
ns.on("UNIT_AURA", function(_, unit)
	if unit ~= "player" then return end
	if ns.api and ns.api.InvalidateAuraCache then ns.api.InvalidateAuraCache() end
	if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
end)

-- Health / prediction / absorb changes queue (coalesce) a single own paint.
local function requestPaintForUnit(unit)
	if unit ~= "player" then return end
	if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
end

ns.on("UNIT_HEALTH", function(_, unit) requestPaintForUnit(unit) end)
ns.on("UNIT_MAXHEALTH", function(_, unit) requestPaintForUnit(unit) end)
ns.on("UNIT_HEAL_PREDICTION", function(_, unit) requestPaintForUnit(unit) end)
ns.on("UNIT_HEAL_ABSORB_AMOUNT_CHANGED", function(_, unit) requestPaintForUnit(unit) end)

------------------------------------------------------------------------------
-- slash commands
------------------------------------------------------------------------------

local function parseNumber(s)
	return tonumber(s)
end

local HELP = "commands: test <v> | test off | status | debug [on|off] | enable on|off | alpha <a> | color <r> <g> <b> | color overlay <r> <g> <b> | color native | interval <id> <s> | spell add|remove <id> [name] | amountmode total|effective | excludehots on|off | reset | help"

function ns.HandleCommand(input)
	local raw = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = raw:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()
	local args = {}
	for word in rest:gmatch("%S+") do args[#args + 1] = word end

	if cmd == "help" or cmd == "" then
		ns.print(HELP)
		return
	elseif cmd == "test" then
		if args[1] and args[1]:lower() == "off" then
			ns.session.fake = nil
			ns.print("fake test off.")
		else
			local v = parseNumber(args[1])
			if ns.isFinite(v) then
				ns.session.fake = { value = v }
				ns.print(string.format("fake overlay appended: +%s (session only).", tostring(v)))
			else
				ns.print("usage: /euihot test <nonnegative number> | test off")
			end
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
	elseif cmd == "enable" then
		local v = (args[1] or ""):lower()
		if v == "on" or v == "true" or v == "1" then
			ns.db.enabled = true
		elseif v == "off" or v == "false" or v == "0" then
			ns.db.enabled = false
		else
			ns.print("usage: /euihot enable on|off")
			return
		end
		if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
		ns.print("overlay " .. (ns.db.enabled and "enabled" or "disabled") .. ".")
		return
	elseif cmd == "alpha" then
		local a = parseNumber(args[1])
		if a and a >= 0 and a <= 1 and ns.isFinite(a) then
			ns.db.alpha = a
			if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
			ns.print("alpha = " .. tostring(a))
		else
			ns.print("usage: /euihot alpha <0..1>")
		end
		return
	elseif cmd == "color" then
		local first = (args[1] or ""):lower()
		if first == "native" then
			ns.db.shareNativeStyle = true
			if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
			ns.print("color restored to native inherited style.")
			return
		end
		-- Accept both "/euihot color r g b" and "/euihot color overlay r g b".
		local r, g, b
		if first == "overlay" then
			r, g, b = parseNumber(args[2]), parseNumber(args[3]), parseNumber(args[4])
		else
			r, g, b = parseNumber(args[1]), parseNumber(args[2]), parseNumber(args[3])
		end
		if ns.isFinite(r) and ns.isFinite(g) and ns.isFinite(b) and r <= 1 and g <= 1 and b <= 1 then
			ns.db.overlayColor = { r, g, b }
			ns.db.shareNativeStyle = false
			if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
			ns.print(string.format("overlay color = %s,%s,%s (native inheritance off). Use /euihot color native to restore.",
				tostring(r), tostring(g), tostring(b)))
		else
			ns.print("usage: /euihot color <r> <g> <b> | color overlay <r> <g> <b> | color native  (0..1)")
		end
		return
	elseif cmd == "interval" then
		local id = parseNumber(args[1])
		local secs = parseNumber(args[2])
		if ns.isPositiveInt(id) and ns.isFinite(secs) and secs > 0 and secs <= 300 then
			ns.db.intervalOverrides[id] = secs
			if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
			ns.print(string.format("interval override spell %s = %.2fs", tostring(id), secs))
		else
			ns.print("usage: /euihot interval <positive spellID> <seconds 0..300>")
		end
		return
	elseif cmd == "spell" then
		local op = (args[1] or ""):lower()
		local id = parseNumber(args[2])
		if ns.isPositiveInt(id) and op == "add" then
			ns.db.extraSpells[id] = { name = args[3] or ("spell " .. id), family = "custom" }
			ns.db.removedSpells[id] = nil
			ns.print("registered spell " .. id .. ".")
		elseif ns.isPositiveInt(id) and op == "remove" then
			ns.db.removedSpells[id] = true
			ns.print("removed spell " .. id .. ".")
		else
			ns.print("usage: /euihot spell add|remove <positive spellID> [name]")
		end
		return
	elseif cmd == "amountmode" then
		local m = (args[1] or ""):lower()
		if m == "total" or m == "effective" then
			ns.db.amountMode = m
			if ns.learner and ns.learner.ResetAmounts then ns.learner.ResetAmounts() end
			if ns.api and ns.api.InvalidateAuraCache then ns.api.InvalidateAuraCache() end
			ns.print("amount mode = " .. m .. "; learned magnitudes reset.")
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
		if ns.api and ns.api.InvalidateAuraCache then ns.api.InvalidateAuraCache() end
		if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
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

------------------------------------------------------------------------------
-- diagnostics
------------------------------------------------------------------------------

local function buildString()
	local f = GetBuildInfo
	if type(f) == "function" then
		local ok, version, build, date, toc = pcall(f)
		if ok then
			return string.format("%s build %s (%s, toc %s)", tostring(version), tostring(build), tostring(date), tostring(toc))
		end
	end
	return "GetBuildInfo unavailable (addon v" .. tostring(ns.version) .. ")"
end

-- Public status is concise; it is always pcall-protected so a weird widget can
-- never raise in a user's chat frame.
function ns.EmitStatus()
	local ok, err = pcall(ns._EmitStatus)
	if not ok then
		ns.print("status error (protected): " .. tostring(err))
	end
end

function ns._EmitStatus()
	if not ns.db then ns.InitDatabase() end
	local lines = {}
	local function add(fmt, ...)
		if select("#", ...) > 0 then
			lines[#lines + 1] = string.format(fmt, ...)
		else
			lines[#lines + 1] = fmt
		end
	end

	add("addon v%s enabled=%s debug=%s mode=%s excludeHoTs=%s shareNativeStyle=%s alpha=%.2f",
		tostring(ns.version), tostring(ns.db.enabled), tostring(ns.db.debug), tostring(ns.db.amountMode),
		tostring(ns.db.assumeApiExcludesHoTs), tostring(ns.db.shareNativeStyle), ns.db.alpha or 0)

	-- CLEU access / registration
	local cleuFn = ns.api and ns.api.CombatLogAvailable() or false
	local cleuReg = ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED")
	add("cleu function=%s registration=%s%s", tostring(cleuFn), tostring(cleuReg),
		(ns.capabilities and ns.capabilities.cleuError) and (" (" .. tostring(ns.capabilities.cleuError) .. ")") or "")
	if not cleuFn or not cleuReg then
		add("  WARNING: automatic tick learning unavailable; intervals/amounts require /euihot interval or will be withheld")
	end

	-- overlay structure
	local st = ns.overlay and ns.overlay.state or {}
	local f = st.frame
	local frameName = nil
	if f and f.GetName then
		local ok, v = pcall(f.GetName, f)
		if ok then frameName = v end
	end
	local hpName = nil
	if st.hp and st.hp.GetName then
		local ok, v = pcall(st.hp.GetName, st.hp)
		if ok then hpName = v end
	end
	add("overlay frame=%s shown=%s parent=%s hp=%s",
		f and (tostring(frameName) .. " ref=" .. tostring(f)) or "MISSING",
		tostring(f and f.IsShown and f:IsShown() or false),
		tostring(st.parent ~= nil), tostring(hpName))
	add("build=%s", buildString())
	add("native predOn=%s predMy=%s predOther=%s missClip=%s",
		tostring(st.ab and st.ab._predOn), tostring(st.ab and st.ab._predMy ~= nil),
		tostring(st.ab and st.ab._predOther ~= nil), tostring(st.ab and st.ab._missClip ~= nil))

	-- active HoTs, each with spell/rank, expiry, stacks, learned amount/interval,
	-- remaining ticks, and the total/visible prediction.
	local auras = (ns.api and ns.api.ReadPlayerAuras and ns.api.ReadPlayerAuras()) or {}
	local tracked = 0
	local now = ns.now()
	for i = 1, #auras do
		local aura = auras[i]
		local meta = ns.spells.Meta(aura.spellID)
		if meta and aura.sourceUnit == "player" then
			tracked = tracked + 1
			local data = ns.learner.GetSpellData(aura.spellID)
			local ticks = ns.model.ComputeTicks(aura, data, now)
			local learnedAmount
			if meta.stacksMatter then
				learnedAmount = ns.learner.AmountForStack(aura.spellID, aura.stacks)
			else
				learnedAmount = data.basePerStack
			end
			add("  hot %s [%s] stacks=%s exp=%s dur=%s interval=%s ticksLeft=%s amount=%s%s",
				tostring(aura.spellID), tostring(meta.name or meta.family), tostring(aura.stacks),
				tostring(ns.round(aura.expirationTime, 1)), tostring(ns.round(aura.duration, 1)),
				tostring(ns.round(data.interval, 2)), tostring(ticks),
				tostring(learnedAmount and ns.round(learnedAmount, 1) or "?"),
				meta.approximate and " (approximate)" or "")
		end
	end
	add("tracked active HoTs=%d", tracked)

	local res = ns.session.lastStatus
	if res then
		local visible = res.added
		add("prediction total=%s visible=%s native=%s reason=%s",
			tostring(res.hotEstimate), tostring(visible),
			tostring(res.native and res.native.total), tostring(res.reason))
	else
		add("prediction not evaluated yet")
	end
	if ns.session.lastSuppress then
		add("last suppress: %s", tostring(ns.session.lastSuppress))
	end
	if ns.session.fake then
		add("fake active=%s", tostring(ns.session.fake.value))
	end

	if ns.db.debug then
		pcall(ns.EmitDebugDetails, lines)
	end

	ns.print(table.concat(lines, "\n"))
end

-- Rich on-demand diagnostics used only while debug is enabled.
function ns.EmitDebugDetails(lines)
	local n = ns.toNumber
	local function add(fmt, ...) lines[#lines + 1] = string.format(fmt, ...) end
	add("lua=%s", tostring(_VERSION))
	add("apis C_UnitAuras=%s issecretvalue=%s hooksecurefunc=%s GetBuildInfo=%s",
		tostring(type(C_UnitAuras) == "table" and C_UnitAuras.GetAuraDataByIndex ~= nil),
		tostring(type(issecretvalue) == "function"),
		tostring(type(hooksecurefunc) == "function"),
		tostring(type(GetBuildInfo) == "function"))
	for _, event in ipairs({ "COMBAT_LOG_EVENT_UNFILTERED", "UNIT_AURA", "UNIT_HEALTH", "UNIT_HEAL_PREDICTION", "UNIT_HEAL_ABSORB_AMOUNT_CHANGED" }) do
		add("event %s registered=%s", event, tostring(ns.eventRegistered(event)))
	end
	add("policy=%s amountMode=%s",
		ns.db.assumeApiExcludesHoTs and "excludes-HoT(opt-in)" or "conservative max(0,hot-native)",
		tostring(ns.db.amountMode))
	local st = ns.overlay and ns.overlay.state or {}
	local hp = st.hp
	if hp then
		local w, h = n(hp.GetWidth and hp:GetWidth()), n(hp.GetHeight and hp:GetHeight())
		add("hp dims=%sx%s", tostring(w), tostring(h))
	end
	local ab = st.ab
	if ab then
		local info = ns.api.GetBarInfo(ab._predMy)
		if info then
			add("predMy orient=%s reversed=%s level=%s texture=%s color=%s",
				tostring(info.orientation), tostring(info.reversed), tostring(info.level), tostring(info.texture),
				info.color and table.concat({ tostring(info.color[1]), tostring(info.color[2]), tostring(info.color[3]) }, ",") or "nil")
		end
		local nat = ns.api.GetNativeIncoming(ab)
		add("native mine=%s other=%s total=%s src=%s reason=%s",
			tostring(nat.mine), tostring(nat.others), tostring(nat.total), tostring(nat.source), tostring(nat.reason))
	end
	local last = ns.session.lastStatus
	if last then
		add("tick hot=%s added=%s nativeTotal=%s reason=%s",
			tostring(last.hotEstimate), tostring(last.added),
			tostring(last.native and last.native.total), tostring(last.reason))
	end
	if ns.overlay and ns.overlay.state and ns.overlay.state.frame then
		local f2 = ns.overlay.state.frame
		local v = n(f2.GetValue and f2:GetValue())
		add("overlay shown=%s value=%s marks=%s", tostring(f2.IsShown and f2:IsShown()), tostring(v),
			tostring(ns.overlay.state.maskCount or 0))
	end
end

------------------------------------------------------------------------------
-- The event frame must exist at file-load time so ADDON_LOADED (our own) can
-- be received. Everything else is registered from Startup.
------------------------------------------------------------------------------
ensureEventFrame()
ns.capabilities = ns.capabilities or { events = {} }
ns.register("ADDON_LOADED")
ns.SetupSlash()
