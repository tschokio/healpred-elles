-- EllesmereUI_HoTPrediction / Core.lua
-- Namespace, settings, event plumbing, startup, slash commands.
-- Keep this file free of anything that assumes a live WoW client: it must be
-- loadable and testable under a plain Lua interpreter with mocked globals.

local addonName, ns = ...

ns.name = addonName
ns.version = "0.5.2"
ns.debugEnabled = false
ns.inCombat = false
ns.started = false

-- Session-only CLEU override, set by `/euihot observe on|off`. It is NEVER
-- written to SavedVariables: a restricted client must not resurrect a forbidden
-- registration across a reload. nil = no override (use the engine gate default),
-- true = request guarded registration, false = do not register (and unregister).
ns.observeCLEU = nil

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
--
-- Capability state is deliberately NOT reset here: registration/acceptance and
-- the observed CLEU delivery count are facts about this client session, not
-- "learning", and clearing them would erase the honest CLEU status the user
-- needs. `ns.resetSession()` only clears learned data and the aura cache.
function ns.resetSession()
	ns.session = {
		learned = {},      -- [spellID] = interval/totals + last tick phase
		auraCache = nil,   -- list of aura records, rebuilt on invalidation
		lastTicksAt = {},  -- [spellID] = { time =, instanceID = }
		fake = nil,        -- active fake overlay, never persisted
		lastSuppress = nil,
		lastStatus = nil,
		-- PUBLIC render diagnostics: never hold a secret range/value, only a
		-- short label of its source and whether it was restricted.
		lastRange = nil,
		lastRenderReason = nil,
	}
end

-- Persistent-per-session capability record. Initialised once; not rebuilt by a
-- reload or a `/reset` (only a full addon reload recreates it).
function ns.initCapabilities()
	if ns.capabilities then return ns.capabilities end
	ns.capabilities = {
		events = {},         -- [eventName] = accepted boolean
		cleuFunction = false,-- is CombatLogGetCurrentEventInfo present?
		cleuRequested = false, -- did we ask the client to register CLEU?
		cleuAccepted = false,  -- did RegisterEvent report acceptance?
		cleuDelivered = 0,     -- actual observed COMBAT_LOG_EVENT_UNFILTERED deliveries
		cleuGateReason = nil,  -- why we did or did not request registration
		cleuOverride = false,  -- was an explicit session override responsible?
		cleuError = nil,       -- last adapter error reading the tuple
	}
	return ns.capabilities
end

ns.DEFAULTS = {
	enabled = true,
	debug = false,
	alpha = 0.60,                  -- our segment's opacity (composited with native)
	shareNativeStyle = true,       -- inherit native texture/color (default)
	overlayColor = { 1.0, 0.82, 0.0 },
	amountMode = "total",          -- "total" (CLEU amount includes overheal) or "effective"
	assumeApiExcludesHoTs = false, -- opt-in: user verified native already excludes HoTs
	approximatePrediction = false, -- opt-in: public tooltip/manual estimate, ignores heal absorbs
	minimapHidden = false,
	minimapAngle = 225,
	queuedSwingEnabled = true,
	queuedSwingColor = { 0.0, 1.0, 1.0 }, -- distinct opaque next-swing border
	queuedSwingThickness = 3,
	queuedSwingPadding = 3,
	queuedSwingAlpha = 1,
	intervalOverrides = {},        -- [spellID] = seconds (user calibration only)
	amountOverrides = {},          -- [spellID] = { [stacks] = exact tick total } (user calibration only)
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
	if ns.db and not ns.db.enabled and event ~= "ADDON_LOADED" then return end
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
--
-- "pcall returned true" is NOT proof: some clients make RegisterEvent a no-op
-- that returns false for a forbidden event. We treat an explicit `false` return
-- as rejection and everything else (nil/true) as accepted.
function ns.register(event)
	ns.initCapabilities()
	local f = ensureEventFrame()
	if not f or not f.RegisterEvent then
		ns.capabilities.events[event] = false
		return false
	end
	local ok, ret
	if event:match("^UNIT_") and type(f.RegisterUnitEvent) == "function" then
		ok, ret = pcall(f.RegisterUnitEvent, f, event, "player")
	else
		ok, ret = pcall(f.RegisterEvent, f, event)
	end
	local accepted = ok and (ret ~= false)
	ns.capabilities.events[event] = accepted and true or false
	return accepted and true or false
end

-- Record an event as unavailable WITHOUT ever attempting registration.
function ns.markEventUnavailable(event)
	ns.initCapabilities()
	ns.capabilities.events[event] = false
	return false
end

function ns.eventRegistered(event)
	return ns.capabilities and ns.capabilities.events and ns.capabilities.events[event] == true
end

function ns.unregister(event)
	ns.initCapabilities()
	local f = ns.eventFrame
	if f and f.UnregisterEvent then pcall(f.UnregisterEvent, f, event) end
	ns.capabilities.events[event] = false
	return true
end

-----------------------------------------------------------------------------
-- engine gate: known restricted (Midnight) engines forbid CLEU
-----------------------------------------------------------------------------

-- The supplied EllesmereUI source gate treats current retail (interface/toc
-- >= 120000, i.e. 12.0.0 / 12.0.1) and "Forever" (interface 16000..19999) as
-- Midnight engines. On those, automatic COMBAT_LOG_EVENT_UNFILTERED registration
-- must never be ATTEMPTED unless the user explicitly opts in.
-- Returns restricted(boolean), reason(string).
function ns.RestrictedEngineReason()
	local f = GetBuildInfo
	if type(f) ~= "function" then
		return false, "GetBuildInfo unavailable: cannot classify engine"
	end
	local ok, version, _build, _date, toc = pcall(f)
	if not ok then
		return false, "GetBuildInfo error: cannot classify engine"
	end
	local tocN = ns.toNumber(toc)
	if tocN and tocN >= 120000 then
		return true, string.format("retail interface %s is a restricted Midnight engine", tostring(tocN))
	end
	if tocN and tocN >= 16000 and tocN <= 19999 then
		return true, string.format("Forever interface %s is a restricted engine", tostring(tocN))
	end
	-- Fall back to the version string when toc version is not usable.
	if not tocN and type(version) == "string" then
		local major = tonumber(version:match("^(%d+)"))
		if major and major >= 12 then
			return true, string.format("client version %s is a restricted Midnight engine", tostring(version))
		end
	end
	return false, string.format("build %s interface %s not known-restricted", tostring(version), tostring(tocN or "?"))
end

-- Decide whether to request COMBAT_LOG_EVENT_UNFILTERED and do it (guarded).
-- `force` is used by the explicit `/euihot observe on` override.
-- Returns accepted(boolean).
function ns.SetupCLEU(force)
	ns.initCapabilities()
	local cap = ns.capabilities
	local EVENT = "COMBAT_LOG_EVENT_UNFILTERED"

	cap.cleuFunction = ns.api and ns.api.CombatLogAvailable() or false
	cap.cleuError = nil
	cap.cleuOverride = force and true or false
	if ns.db and not ns.db.enabled then
		cap.cleuRequested, cap.cleuAccepted = false, false
		cap.cleuGateReason = "addon disabled"
		ns.unregister(EVENT)
		return false
	end

	-- 1. No API on this client: never register.
	if not cap.cleuFunction then
		cap.cleuRequested = false
		cap.cleuAccepted = false
		cap.cleuGateReason = "CombatLogGetCurrentEventInfo unavailable"
		ns.markEventUnavailable(EVENT)
		return false
	end

	-- 2. Engine gate.
	local restricted, gateReason = ns.RestrictedEngineReason()
	cap.cleuGateReason = gateReason

	-- Default policy: auto-register only on clean (non-restricted) engines.
	local want
	if force then
		want = true
	elseif ns.observeCLEU == false then
		want = false
	else
		want = not restricted
	end

	if not want then
		cap.cleuRequested = false
		cap.cleuAccepted = false
		if not restricted and ns.observeCLEU == false then
			cap.cleuGateReason = "disabled by /euihot observe off"
		end
		ns.markEventUnavailable(EVENT)
		return false
	end

	-- 3. Request guarded registration. Acceptance is NOT delivery proof.
	cap.cleuRequested = true
	local accepted = ns.register(EVENT)
	cap.cleuAccepted = accepted and true or false
	if not accepted then
		cap.cleuError = "RegisterEvent was refused by the client"
	end
	return accepted
end

------------------------------------------------------------------------------
-- startup
------------------------------------------------------------------------------

local RUNTIME_EVENTS = {
	"PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",
	"UNIT_AURA", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_HEAL_PREDICTION",
	"UNIT_HEAL_ABSORB_AMOUNT_CHANGED", "PLAYER_EQUIPMENT_CHANGED",
	"ACTIVE_TALENT_GROUP_CHANGED", "SPELLS_CHANGED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_POWER_UPDATE",
	"UPDATE_SHAPESHIFT_FORM", "UNIT_DISPLAYPOWER",
	"ACTIONBAR_UPDATE_STATE", "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED",
	"UPDATE_BONUS_ACTIONBAR", "UPDATE_OVERRIDE_ACTIONBAR", "UPDATE_VEHICLE_ACTIONBAR",
	"UPDATE_MACROS", "PLAYER_TARGET_CHANGED", "UNIT_SPELLCAST_SUCCEEDED",
	"UNIT_SPELLCAST_FAILED", "PLAYER_DEAD", "PLAYER_ALIVE",
}

-- Disabling stops the timer and unregisters gameplay events. Secure hooks cannot
-- be removed, so their callbacks have a disabled guard before doing any work.
function ns.SetRuntimeEnabled(enabled)
	enabled = enabled and true or false
	ns.db.enabled = enabled
	if ns.runtimeEnabled == enabled then return end
	ns.runtimeEnabled = enabled
	for _, event in ipairs(RUNTIME_EVENTS) do
		if enabled then ns.register(event) else ns.unregister(event) end
	end
	if enabled then
		ns.inCombat = ns.api.InCombat()
		-- Gear, talents and applications may have changed while unsubscribed.
		if ns.learner then ns.learner.Reset() end
		ns.SetupCLEU(ns.observeCLEU == true)
	else
		ns.session.fake = nil
		ns.SetupCLEU(false)
	end
	if ns.overlay and ns.overlay.SetEnabled then ns.overlay.SetEnabled(enabled) end
	if ns.queuedSwing then ns.queuedSwing.SetEnabled() end
end

-- Called once after the matching ADDON_LOADED. Attempts a real init and, only
-- if everything the overlay depends on is absent, prints a single useful line.
function ns.Startup()
	if ns.started then return end
	ns.started = true

	ns.resetSession()
	ns.InitDatabase()
	if ns.InitOptions then ns.InitOptions() end

	ns.initCapabilities()
	if ns.learner and ns.learner.Setup then ns.learner.Setup() end
	ns.SetRuntimeEnabled(ns.db.enabled)
	ns.unregister("ADDON_LOADED")

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
for _, event in ipairs({ "UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE",
	"UNIT_SPELLCAST_CHANNEL_STOP", "UNIT_SPELLCAST_INTERRUPTED" }) do
	ns.on(event, function(_, unit) requestPaintForUnit(unit) end)
end
ns.on("UNIT_POWER_UPDATE", function(_, unit, powerType)
	if powerType == "RAGE" then requestPaintForUnit(unit) end
end)

-- Form changes can alter maximum health and the native bar layout, and aura /
-- spell data may settle slightly after the first notification. Do not reset
-- learned tick phase or manual calibration just because the player changes form.
ns.on("UPDATE_SHAPESHIFT_FORM", function()
	if ns.overlay then ns.overlay.RequestFormRefresh() end
end)
ns.on("UNIT_DISPLAYPOWER", function(_, unit)
	if unit == "player" and ns.overlay then ns.overlay.RequestFormRefresh() end
end)

------------------------------------------------------------------------------
-- slash commands
------------------------------------------------------------------------------

local function parseNumber(s)
	return tonumber(s)
end

local HELP = "commands: test <v> | test off | teststatus | status | window | approximate on|off | debug [on|off] | debug window | enable on|off | alpha <a> | color <r> <g> <b> | color overlay <r> <g> <b> | color native | interval <id> <s>|off | amount <id> <tickTotal> [stacks]|off [stacks] | observe on|off | spell add|remove <id> [name] | amountmode total|effective | excludehots on|off | reset | help"

-- Bound for a manual tick-total calibration. It only has to be a sane upper
-- limit on a single heal tick, not a game mechanic.
ns.AMOUNT_OVERRIDE_MAX = 100000000

function ns.HandleCommand(input)
	local raw = (input or ""):gsub("^%s+", ""):gsub("%s+$", "")
	local cmd, rest = raw:match("^(%S*)%s*(.*)$")
	cmd = (cmd or ""):lower()
	local args = {}
	for word in rest:gmatch("%S+") do args[#args + 1] = word end

	if cmd == "help" or cmd == "" then
		ns.print(HELP)
		ns.print("settings: /euihot options (or menu) | /euihot minimap on|off; minimap left-click settings, right-click diagnostics, drag to move.")
		ns.print("next-swing borders: /euihot queue on|off | queue color <r> <g> <b> | queue status")
		return
	elseif cmd == "queue" then
		local op = (args[1] or "status"):lower()
		if op == "on" or op == "off" then
			ns.db.queuedSwingEnabled = op == "on"
			if ns.queuedSwing then ns.queuedSwing.SetEnabled() end
		elseif op == "color" then
			local r, g, b = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
			if not ns.isFinite(r) or not ns.isFinite(g) or not ns.isFinite(b) or r > 1 or g > 1 or b > 1 then
				ns.print("usage: /euihot queue color <r> <g> <b> (0..1)"); return
			end
			ns.db.queuedSwingColor = { r, g, b }
			if ns.queuedSwing then ns.queuedSwing.Refresh() end
		elseif op ~= "status" then
			ns.print("usage: /euihot queue on|off | queue color <r> <g> <b> | queue status"); return
		end
		local s = ns.queuedSwing
		ns.print(string.format("next-swing enabled=%s buttons=%d highlighted=%d state=%s",
			tostring(ns.db.queuedSwingEnabled), s and #s.candidates or 0, s and s.active or 0,
			s and s.reason or "module unavailable"))
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
		if ns.overlay then ns.overlay.RequestPaint() end
		return
	elseif cmd == "status" then
		ns.EmitStatus()
		return
	elseif cmd == "options" or cmd == "menu" then
		if ns.OpenOptions then ns.OpenOptions() end
		return
	elseif cmd == "minimap" then
		local v = (args[1] or ""):lower()
		if v ~= "on" and v ~= "off" then ns.print("usage: /euihot minimap on|off"); return end
		ns.db.minimapHidden = v == "off"
		if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end
		return
	elseif cmd == "approximate" then
		local v = (args[1] or ""):lower()
		if v ~= "on" and v ~= "off" then ns.print("usage: /euihot approximate on|off"); return end
		ns.db.approximatePrediction = v == "on"
		if ns.estimates then ns.estimates.Invalidate() end
		if ns.overlay then ns.overlay.RequestPaint() end
		ns.print(v == "on" and "approximate prediction ON: public tooltip/manual amounts; heal absorbs ignored; restricted native overlap unverified (may double-count). /euihot test off to use real auras."
			or "approximate prediction OFF: conservative restrictions restored.")
		return
	elseif cmd == "teststatus" then
		ns.EmitTestStatus()
		return
	elseif cmd == "window" then
		if ns.OpenDebugWindow then
			ns.OpenDebugWindow()
		else
			ns.print("debug window unavailable (DebugWindow.lua not loaded).")
		end
		return
	elseif cmd == "debug" then
		local v = (args[1] or ""):lower()
		if v == "window" then
			if ns.OpenDebugWindow then
				ns.OpenDebugWindow()
			else
				ns.print("debug window unavailable (DebugWindow.lua not loaded).")
			end
			return
		end
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
		ns.SetRuntimeEnabled(ns.db.enabled)
		ns.print("overlay " .. (ns.db.enabled and "enabled" or "disabled") .. ".")
		return
	elseif cmd == "alpha" then
		local a = parseNumber(args[1])
		if a and a >= 0 and a <= 1 and ns.isFinite(a) then
			ns.db.alpha = a
			if ns.overlay then ns.overlay.RequestStyle() end
			ns.print("alpha = " .. tostring(a))
		else
			ns.print("usage: /euihot alpha <0..1>")
		end
		return
	elseif cmd == "color" then
		local first = (args[1] or ""):lower()
		if first == "native" then
			ns.db.shareNativeStyle = true
			if ns.overlay then ns.overlay.RequestStyle() end
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
			if ns.overlay then ns.overlay.RequestStyle() end
			ns.print(string.format("overlay color = %s,%s,%s (native inheritance off). Use /euihot color native to restore.",
				tostring(r), tostring(g), tostring(b)))
		else
			ns.print("usage: /euihot color <r> <g> <b> | color overlay <r> <g> <b> | color native  (0..1)")
		end
		return
	elseif cmd == "interval" then
		local id = parseNumber(args[1])
		if ns.isPositiveInt(id) and args[2] and args[2]:lower() == "off" then
			ns.db.intervalOverrides[id] = nil
			if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
			ns.print(string.format("cleared manual interval for spell %s.", tostring(id)))
			return
		end
		local secs = parseNumber(args[2])
		if ns.isPositiveInt(id) and ns.isFinite(secs) and secs > 0 and secs <= 300 then
			ns.db.intervalOverrides[id] = secs
			if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
			ns.print(string.format("manual interval spell %s = %.2fs (persisted; recalibrate after gear/spec change).", tostring(id), secs))
		else
			ns.print("usage: /euihot interval <positive spellID> <seconds 0..300> | interval <spellID> off")
		end
		return
	elseif cmd == "amount" then
		local id = parseNumber(args[1])
		local meta = ns.isPositiveInt(id) and ns.spells.Meta(id) or nil
		if not meta then
			ns.print("usage: /euihot amount <positive spellID> <tickTotal> [stacks] | amount <spellID> off [stacks]  (spell must be a tracked candidate; /euihot spell add first)")
			return
		end
		if args[2] and args[2]:lower() == "off" then
			local stacks = parseNumber(args[3])
			if ns.isPositiveInt(stacks) then
				if ns.db.amountOverrides[id] then ns.db.amountOverrides[id][math.floor(stacks)] = nil end
				ns.print(string.format("cleared manual amount for spell %s at stack %s.", tostring(id), tostring(math.floor(stacks))))
			else
				ns.db.amountOverrides[id] = nil
				ns.print(string.format("cleared manual amount for spell %s.", tostring(id)))
			end
			if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
			return
		end
		-- Non-stacking families are calibrated as stack 1 by definition; only
		-- stacking families (Lifebloom) accept a specific stack count.
		local total = parseNumber(args[2])
		local stacks = 1
		if meta.stacksMatter then
			stacks = parseNumber(args[3]) or 1
		end
		if not ns.isFinite(total) or total <= 0 or total > ns.AMOUNT_OVERRIDE_MAX then
			ns.print("usage: /euihot amount <positive spellID> <tickTotal 0..100000000> [stacks] | amount <spellID> off [stacks]")
			return
		end
		if not ns.isPositiveInt(stacks) then
			ns.print("usage: /euihot amount <spellID> <tickTotal> [stacks]; stacks must be a positive integer")
			return
		end
		stacks = math.floor(stacks)
		ns.db.amountOverrides[id] = ns.db.amountOverrides[id] or {}
		ns.db.amountOverrides[id][stacks] = total
		if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
		ns.print(string.format("manual tick total spell %s = %s at %s stack(s) (persisted, user-authoritative; recalibrate after gear/rank change).",
			tostring(id), tostring(total), tostring(stacks)))
		return
	elseif cmd == "observe" then
		local v = (args[1] or ""):lower()
		if v == "on" then
			if not ns.db.enabled then
				ns.observeCLEU = true
				ns.print("observe on saved for this session; learning remains paused while addon disabled.")
				return
			end
			if not (ns.api and ns.api.CombatLogAvailable and ns.api.CombatLogAvailable()) then
				ns.observeCLEU = true
				ns.print("observe on: CLEU function unavailable on this client; no registration attempted.")
				return
			end
			ns.observeCLEU = true
			local accepted = ns.SetupCLEU(true)
			if accepted then
				ns.print("observe on: CLEU registration requested and accepted; delivery is unverified until a SPELL_PERIODIC_HEAL is actually seen (check /euihot status).")
			else
				ns.print("observe on: CLEU registration was refused by this client; automatic learning unavailable.")
			end
		elseif v == "off" then
			ns.observeCLEU = false
			if ns.capabilities then
				ns.capabilities.cleuRequested = false
				ns.capabilities.cleuAccepted = false
				ns.capabilities.cleuOverride = false
				ns.capabilities.cleuGateReason = "disabled by /euihot observe off"
			end
			ns.unregister("COMBAT_LOG_EVENT_UNFILTERED")
			ns.print("observe off: CLEU unregistered; automatic learning off for this session.")
		else
			ns.print("usage: /euihot observe on|off")
		end
		return
	elseif cmd == "spell" then
		local op = (args[1] or ""):lower()
		local id = parseNumber(args[2])
		if ns.isPositiveInt(id) and op == "add" then
			ns.db.extraSpells[id] = { name = args[3] or ("spell " .. id), family = "custom" }
			ns.db.removedSpells[id] = nil
			if ns.overlay then ns.overlay.RequestPaint() end
			ns.print("registered spell " .. id .. ".")
		elseif ns.isPositiveInt(id) and op == "remove" then
			ns.db.removedSpells[id] = true
			if ns.overlay then ns.overlay.RequestPaint() end
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
			if ns.overlay then ns.overlay.RequestPaint() end
			ns.print("amount mode = " .. m .. "; learned magnitudes reset.")
		else
			ns.print("usage: /euihot amountmode total|effective")
		end
		return
	elseif cmd == "excludehots" then
		local v = (args[1] or ""):lower()
		ns.db.assumeApiExcludesHoTs = (v == "on" or v == "true" or v == "1")
		if ns.overlay then ns.overlay.RequestPaint() end
		ns.print("assume API excludes HoTs = " .. tostring(ns.db.assumeApiExcludesHoTs))
		return
	elseif cmd == "reset" then
		ns.resetSession()
		if ns.api and ns.api.InvalidateAuraCache then ns.api.InvalidateAuraCache() end
		if ns.overlay and ns.overlay.RequestPaint then ns.overlay.RequestPaint() end
		ns.print("session learning reset (CLEU registration/delivery capability preserved).")
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

-- Client build line. Public and never raises.
function ns.BuildString()
	local f = GetBuildInfo
	if type(f) == "function" then
		local ok, version, build, date, toc = pcall(f)
		if ok then
			return string.format("%s build %s (%s, toc %s)", tostring(version), tostring(build), tostring(date), tostring(toc))
		end
	end
	return "GetBuildInfo unavailable (addon v" .. tostring(ns.version) .. ")"
end

-- Remove WoW chat/format escape artifacts so report text is plain copyable
-- text. We never generate colour codes ourselves, but error text might carry one.
function ns.StripFormatting(s)
	if type(s) ~= "string" then s = tostring(s) end
	s = s:gsub("|c%x%x%x%x%x%x%x%x", "") -- |cAARRGGBB
	s = s:gsub("|r", "")
	s = s:gsub("|H.-|h", "")
	s = s:gsub("|h", "")
	s = s:gsub("|T.-|t", "")
	s = s:gsub("||", "|")
	return s
end

function ns.Truncate(s, n)
	s = tostring(s or "")
	n = n or 200
	if #s > n then return s:sub(1, n) .. "..." end
	return s
end

-- Last-resort copyable text when a report builder itself fails; never repeats a
-- raw Lua error verbatim and never raises.
function ns.BuildStatusFallback(err)
	return string.format(
		"addon v%s diagnostics unavailable (protected)\nerror=%s\nbuild=%s\nThis fallback is safe to copy; /euihot status may work after /reload.",
		tostring(ns.version), ns.Truncate(err, 200), ns.BuildString())
end

-- PUBLIC, non-printing report builders. They return plain text and never touch
-- chat; EmitStatus/EmitTestStatus below print them, and the debug window shows
-- them in a selectable EditBox. Both are error-protected so a weird widget can
-- never raise in a user's chat frame: a failed build returns useful fallback
-- text instead of a repeated Lua error (a partial report is preferred).
function ns.BuildStatusReport(includeDebug)
	local ok, res = pcall(ns._BuildStatusReport, includeDebug)
	if ok and type(res) == "string" and res ~= "" then
		return ns.StripFormatting(res)
	end
	return ns.BuildStatusFallback(ok and "empty report" or res)
end

function ns.BuildTestStatusReport()
	local ok, res = pcall(ns._BuildTestStatusReport)
	if ok and type(res) == "string" and res ~= "" then
		return ns.StripFormatting(res)
	end
	return ns.BuildStatusFallback(ok and "empty report" or res)
end

function ns.EmitStatus()
	ns.print(ns.BuildStatusReport(nil))
end

function ns._BuildStatusReport(includeDebug)
	if not ns.db then ns.InitDatabase() end
	if includeDebug == nil then includeDebug = ns.db.debug and true or false end
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
	add("approximate prediction=%s", tostring(ns.db.approximatePrediction))
	local swing = ns.queuedSwing
	if swing then
		add("next-swing enabled=%s candidates=%d highlighted=%d state=%s",
			tostring(ns.db.queuedSwingEnabled), #swing.candidates, swing.active, swing.reason)
	end
	if ns.db.approximatePrediction then
		add("ROUGH ESTIMATE: healing absorbs ignored; restricted native overlap unverified; tooltip bonuses/tick phase may differ from actual healing.")
	end

	-- CLEU access / registration: requested vs accepted vs actually DELIVERED.
	-- "Accepted" is not proof the event is accessible; only an observed delivery
	-- (counter > 0) verifies it.
	local cap = ns.capabilities or {}
	local cleuFn = ns.api and ns.api.CombatLogAvailable and ns.api.CombatLogAvailable() or false
	local cleuReg = ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED")
	local delivered = cap.cleuDelivered or 0
	add("cleu function=%s requested=%s registration=%s delivered=%s%s",
		tostring(cleuFn), tostring(cap.cleuRequested), tostring(cleuReg), tostring(delivered),
		cap.cleuError and (" error=" .. tostring(cap.cleuError)) or "")
	if cap.cleuGateReason then add("cleu gate: %s", tostring(cap.cleuGateReason)) end
	local CAL = "/euihot interval <id> <seconds> and /euihot amount <id> <tickTotal> [stacks]"
	if not cleuFn or not cleuReg then
		add("automatic tick learning unavailable; %s", ns.db.approximatePrediction
			and "approximate mode uses public tooltips or manual calibration (not observed ticks)."
			or ("calibrate manually: " .. CAL .. " (cannot bypass restricted native values in conservative mode)"))
	elseif delivered == 0 then
		add("automatic tick learning unverified (no CLEU delivered yet: acceptance is not delivery); calibrate manually: %s", CAL)
	end

	-- overlay structure
	local st = ns.overlay and ns.overlay.state or {}
	local counts = st.counts or {}
	add("work counters (session totals, not CPU): timer=%s ticks=%s model=%s resolve=%s render=%s auraScans=%s",
		tostring(st.ticker ~= nil or (st.timerFrame and st.timerFrame:GetScript("OnUpdate") ~= nil) or false),
		tostring(counts.ticks or 0), tostring(counts.model or 0), tostring(counts.resolve or 0),
		tostring(counts.render or 0), tostring(ns.api.auraScans or 0))
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
	local shown = false
	if f and f.IsShown then
		local okS, v = pcall(f.IsShown, f)
		shown = okS and v and true or false
	end
	add("overlay frame=%s shown=%s parent=%s hp=%s",
		f and (tostring(frameName) .. " ref=" .. tostring(f)) or "MISSING",
		tostring(shown),
		tostring(st.parent ~= nil), tostring(hpName))
	add("build=%s", ns.BuildString())
	add("native predOn=%s predMy=%s predOther=%s missClip=%s",
		tostring(st.ab and st.ab._predOn), tostring(st.ab and st.ab._predMy ~= nil),
		tostring(st.ab and st.ab._predOther ~= nil), tostring(st.ab and st.ab._missClip ~= nil))

	-- active HoTs, each with spell/rank, expiry, stacks, learned amount/interval,
	-- remaining ticks, and the total/visible prediction.
	local auras = (ns.api and ns.api.ReadPredictionAuras and ns.api.ReadPredictionAuras()) or {}
	local tracked = 0
	local now = ns.now()
	local okHot, hotErr = pcall(function()
		for i = 1, #auras do
			local aura = auras[i]
			local meta = ns.spells.Meta(aura.spellID)
			if meta and aura.sourceUnit == "player" then
				tracked = tracked + 1
				local data = ns.learner.GetSpellData(aura.spellID, aura)
				local ticks = ns.model.ComputeTicks(aura, data, now)
				local amount, manual
				if meta.stacksMatter then
					amount = ns.learner.AmountForStack(aura.spellID, aura.stacks)
					manual = ns.spells.AmountOverride(aura.spellID, aura.stacks) ~= nil
				else
					amount = data.basePerStack
					manual = data.manualAmount and true or false
				end
				local tag = meta.approximate and " (approximate)" or ""
				if manual then tag = tag .. " (manual)" end
				if data.manualInterval then tag = tag .. " (manual interval)" end
				if data.amountSource then tag = tag .. " amountSource=" .. data.amountSource end
				if data.intervalSource then tag = tag .. " intervalSource=" .. data.intervalSource end
				if data.estimateError then tag = tag .. " tooltip=" .. data.estimateError end
				if data.ragePercent then tag = tag .. " rage conversion=" .. tostring(data.ragePercent) .. "% per point (resource-gated)" end
				add("  hot %s [%s] stacks=%s exp=%s dur=%s interval=%s ticksLeft=%s amount=%s%s",
					tostring(aura.spellID), tostring(meta.name or meta.family), tostring(aura.stacks),
					tostring(ns.round(aura.expirationTime, 1)), tostring(ns.round(aura.duration, 1)),
					tostring(ns.round(data.interval, 2)), tostring(ticks),
					tostring(amount and ns.round(amount, 1) or "?"), tag)
			end
		end
	end)
	if not okHot then
		add("hot scan error (protected): %s", ns.Truncate(hotErr, 160))
	end
	add("tracked active HoTs=%d", tracked)

	local res = ns.session.lastStatus
	if res and res.fake then
		-- Fake is a render exercise only. Never report a real-model "no active
		-- HoT" or a numeric visible amount: the native clip (and a restricted
		-- current health) may hide part of it.
		add("fake test requested=%s rendered=%s range=%s",
			tostring(res.requested), tostring(res.rendered and true or false),
			tostring(ns.session.lastRange or "n/a"))
		add("fake visible amount unknown (engine-clipped; native clip may hide it, health may be restricted)")
		add("fake render reason=%s", tostring(res.renderReason or res.reason or "n/a"))
	elseif res and res.approximate then
		add("approximate HoT total=%s requested=%s visible=unknown (engine-clipped) reason=%s render=%s",
			tostring(res.hotEstimate), tostring(res.added), tostring(res.reason), tostring(res.renderReason or "n/a"))
	elseif res then
		local visible = res.added
		add("prediction total=%s visible=%s native=%s reason=%s render=%s",
			tostring(res.hotEstimate), tostring(visible),
			tostring(res.native and res.native.total), tostring(res.reason),
			tostring(res.renderReason or "n/a"))
	else
		add("prediction not evaluated yet")
	end
	if ns.session.lastSuppress then
		add("last suppress: %s", tostring(ns.session.lastSuppress))
	end
	if ns.session.lastRange then
		add("last range: %s", tostring(ns.session.lastRange))
	end
	if ns.session.fake then
		add("fake active=%s", tostring(ns.session.fake.value))
	end

	if includeDebug then
		local ok, err = pcall(ns.EmitDebugDetails, lines)
		if not ok then add("debug details error (protected): %s", ns.Truncate(err, 160)) end
	end

	return table.concat(lines, "\n")
end

-- Concise ONE-LINE render status, for users whose chat scrollback is broken by
-- the long /status dump. Reports only PUBLIC facts; a secret range/value is
-- never formatted or read back (only the widget keeps it).
function ns.EmitTestStatus()
	ns.print(ns.BuildTestStatusReport())
end

function ns._BuildTestStatusReport()
	if not ns.db then ns.InitDatabase() end
	local st = (ns.overlay and ns.overlay.state) or {}

	local unit, uerr
	local player = ns.api and ns.api.GetPlayerFrame and ns.api.GetPlayerFrame()
	if player then unit, uerr = ns.api.GetFrameUnit(player) end

	local ab = st.ab
	local native
	if not ab then
		native = "no-frame"
	elseif ab._predOn ~= true then
		native = "disabled"
	elseif not ab._predMy or not ab._predOther then
		native = "bars-missing"
	else
		native = "ready"
	end

	local f = st.frame
	local shown = false
	if f and f.IsShown then
		local ok2, v = pcall(f.IsShown, f)
		shown = ok2 and v and true or false
	end

	local fakeReq = ns.session and ns.session.fake and ns.session.fake.value
	local cleuFn = ns.api and ns.api.CombatLogAvailable and ns.api.CombatLogAvailable() or false
	local delivered = (ns.capabilities and ns.capabilities.cleuDelivered) or 0

	-- `unit` may be nil with a public reason; never print a secret unit name.
	local unitLabel = unit
	if unitLabel == nil then unitLabel = (uerr or "?") end

	return string.format(
		"teststatus unit=%s native=%s fakeRequested=%s overlayShown=%s range=%s render=%s visible=%s cleu=%s delivered=%s",
		tostring(unitLabel), tostring(native), tostring(fakeReq or "none"), tostring(shown),
		tostring(ns.session and ns.session.lastRange or "n/a"),
		tostring(ns.session and ns.session.lastRenderReason or "n/a"),
		"unknown (engine-clipped)", tostring(cleuFn), tostring(delivered))
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
		ns.db.approximatePrediction and "approximate(opt-in; absorbs ignored; secret overlap unverified)"
			or (ns.db.assumeApiExcludesHoTs and "excludes-HoT(opt-in)" or "conservative max(0,hot-native)"),
		tostring(ns.db.amountMode))
	local cap = ns.capabilities or {}
	add("cleu requested=%s accepted=%s delivered=%s override=%s gate=%s",
		tostring(cap.cleuRequested), tostring(cap.cleuAccepted), tostring(cap.cleuDelivered),
		tostring(cap.cleuOverride), tostring(cap.cleuGateReason))
	local manualIntervals, manualAmounts = 0, 0
	for _ in pairs(ns.db.intervalOverrides or {}) do manualIntervals = manualIntervals + 1 end
	for _, ov in pairs(ns.db.amountOverrides or {}) do
		if type(ov) == "table" then for _ in pairs(ov) do manualAmounts = manualAmounts + 1 end end
	end
	add("manual calibration intervals=%d amountEntries=%d (user-authoritative; not learned)", manualIntervals, manualAmounts)
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
		add("tick fake=%s hot=%s added=%s nativeTotal=%s reason=%s render=%s",
			tostring(last.fake), tostring(last.hotEstimate), tostring(last.added),
			tostring(last.native and last.native.total), tostring(last.reason),
			tostring(last.renderReason or "n/a"))
	end
	add("render range=%s reason=%s", tostring(ns.session.lastRange or "n/a"),
		tostring(ns.session.lastRenderReason or "n/a"))
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
ns.initCapabilities()
ns.register("ADDON_LOADED")
ns.SetupSlash()
