local BAM = "Interface\\AddOns\\DoHelper\\Sounds\\bam.mp3"

local function env()
	local e = Mocks.NewEnv()
	local calls = {}
	PlaySound = function(id, channel) calls[#calls + 1] = { id, channel }; return true end
	PlaySoundFile = function(path, channel) calls[#calls + 1] = { path, channel }; return true end
	return e, calls
end
local function event(sub, crit, source)
	local a = { n = 21, [2] = sub, [4] = source or Mocks.playerGUID }
	a[(sub == "SWING_DAMAGE" or sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL") and 18 or 21] = crit
	return a
end
local function click(w) w:GetScript("OnClick")(w) end

local function restrictedEnv()
	Mocks.Reset()
	Mocks.SetBuild("12.0.1", 1, "", 120001)
	local calls = {}
	PlaySound = function(id, channel) calls[#calls + 1] = { id, channel }; return true end
	PlaySoundFile = function(path, channel) calls[#calls + 1] = { path, channel }; return true end
	Mocks.BuildEUF()
	local ns = Mocks.LoadAddon()
	Mocks.Fire("ADDON_LOADED", "DoHelper")
	Mocks.Fire("PLAYER_LOGIN")
	return ns, calls
end

-- A fresh SavedVariables table before ADDON_LOADED, for migration tests.
local function presetEnv(db)
	Mocks.Reset()
	_G.EllesmereUI_HoTPredictionDB = db
	Mocks.BuildEUF()
	local ns = Mocks.LoadAddon()
	Mocks.Fire("ADDON_LOADED", "DoHelper")
	Mocks.Fire("PLAYER_LOGIN")
	return ns
end

T.register("crit sounds: disabled by default; preview works and no timer is added", function()
	local e, calls = env()
	e.ns.critSounds.HandleCLEU(event("SPELL_DAMAGE", true))
	assert_eq(#calls, 0)
	assert_true(e.ns.critSounds.Play(true))
	assert_eq(calls[1][1], BAM, "the bundled bam.mp3 is the default cue")
	assert_eq(calls[1][2], "Master")
	assert_nil(e.ns.critSounds.eventFrame, "uses shared guarded subscription")
end)

T.register("crit sounds: all supported damage and healing tuples use exact crit fields", function()
	local e, calls = env()
	local d = e.ns.db.critSounds
	d.enabled, d.cooldown = true, 0
	for _, sub in ipairs({ "SWING_DAMAGE", "RANGE_DAMAGE", "SPELL_DAMAGE", "SPELL_PERIODIC_DAMAGE", "SPELL_HEAL", "SPELL_PERIODIC_HEAL" }) do
		local n = #calls
		e.ns.critSounds.HandleCLEU(event(sub, false)); assert_eq(#calls, n)
		e.ns.critSounds.HandleCLEU(event(sub, true)); assert_eq(#calls, n + 1)
	end
	d.damage = false
	e.ns.critSounds.HandleCLEU(event("SPELL_DAMAGE", true)); assert_eq(#calls, 6)
	d.healing = false
	e.ns.critSounds.HandleCLEU(event("SPELL_HEAL", true)); assert_eq(#calls, 6)
end)

T.register("crit sounds: other players, pets, cast attempts and unreadable fields fail closed", function()
	local e, calls = env()
	e.ns.db.critSounds.enabled = true
	e.ns.critSounds.HandleCLEU(event("SPELL_DAMAGE", true, "Other"))
	e.ns.critSounds.HandleCLEU(event("SWING_DAMAGE", true, "Pet"))
	e.ns.critSounds.HandleCLEU(event("SPELL_CAST_SUCCESS", true))
	e.ns.critSounds.HandleCLEU(event("SPELL_DAMAGE", Mocks.MakeSecret()))
	e.ns.critSounds.HandleCLEU(event("SPELL_DAMAGE", true, Mocks.MakeSecret()))
	e.ns.critSounds.HandleCLEU(event(Mocks.MakeSecret(), true))
	assert_eq(#calls, 0)
	assert_eq(e.ns.critSounds.diagnostics.playerCrits, 0, "unreadable events never count as observed crits")
	e.ns.SetRuntimeEnabled(false)
	e.ns.critSounds.HandleCLEU(event("SPELL_DAMAGE", true)); assert_eq(#calls, 0)
end)

T.register("crit sounds: cooldown suppresses multi-target bursts but preview is independent", function()
	local e, calls = env()
	e.ns.db.critSounds.enabled = true
	e.ns.critSounds.HandleCLEU(event("SPELL_DAMAGE", true))
	e.ns.critSounds.HandleCLEU(event("SPELL_DAMAGE", true)); assert_eq(#calls, 1)
	assert_true(e.ns.critSounds.Play(true)); assert_eq(#calls, 2)
	Mocks.now = Mocks.now + 0.5
	e.ns.critSounds.HandleCLEU(event("SPELL_HEAL", true)); assert_eq(#calls, 3)
	assert_eq(e.ns.critSounds.diagnostics.playerCrits, 3, "observed crits are counted even when playback is suppressed")
end)

T.register("crit sounds: external path validation is atomic and playback failures never fall back", function()
	local e, calls = env()
	local s = e.ns.critSounds
	local v = { enabled = true, damage = true, healing = false, path = "Interface/AddOns/DoHelper/Sounds/bam.ogg", channel = "SFX", cooldown = "1.25" }
	assert_true(s.SetConfig(v))
	assert_eq(e.ns.db.critSounds.cooldown, 1.25)
	assert_true(s.Play(true))
	assert_eq(calls[1][1], "Interface\\AddOns\\DoHelper\\Sounds\\bam.ogg")
	assert_eq(calls[1][2], "SFX")
	for _, path in ipairs({ "https://example.com/bam.mp3", "/home/bam.ogg", "Interface/AddOns/../bam.ogg", "Interface/AddOns/DoHelper/bam.exe" }) do
		v.path = path
		assert_false(s.SetConfig(v))
		assert_eq(e.ns.db.critSounds.path, "Interface\\AddOns\\DoHelper\\Sounds\\bam.ogg")
	end
	PlaySoundFile = function() return false end
	assert_false(s.Play(true))
	PlaySoundFile = function() error("missing file") end
	assert_false(s.Play(true))
	PlaySoundFile = function() return Mocks.MakeSecret() end
	assert_false(s.Play(true))
	assert_eq(#calls, 1, "no silent built-in fallback")
	assert_eq(s.diagnostics.lastPlaybackOk, false, "refused playback is recorded honestly")
end)

T.register("crit sounds: shared listener accepts modern and legacy combat-log payloads", function()
	local e, calls = env()
	e.ns.db.critSounds.enabled, e.ns.db.critSounds.cooldown = true, 0
	local a = event("SPELL_DAMAGE", true)
	CombatLogGetCurrentEventInfo = function() return (unpack or table.unpack)(a, 1, 21) end
	Mocks.Fire("COMBAT_LOG_EVENT_UNFILTERED")
	assert_eq(#calls, 1)
	Mocks.Fire("COMBAT_LOG_EVENT_UNFILTERED", (unpack or table.unpack)(a, 1, 21))
	assert_eq(#calls, 2)
	assert_eq(e.ns.critSounds.diagnostics.delivered, 2, "every delivery is counted")
end)

T.register("crit sounds: restricted engines never acquire a new event subscription", function()
	local ns = restrictedEnv()
	ns.db.critSounds.enabled = true
	ns.critSounds.Setup()
	assert_false(ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
	assert_eq(ns.critSounds.DetectionState(), "blocked")
	assert_true(ns.critSounds.Status():find("blocked", 1, true) ~= nil)
end)

T.register("crit sounds: Try crit detection is the explicit opt-in that registers on a restricted engine", function()
	local ns, calls = restrictedEnv()
	ns.db.critSounds.enabled = true
	ns.db.critSounds.cooldown = 0
	assert_false(ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
	assert_eq(ns.critSounds.DetectionState(), "blocked")
	local ok, msg = ns.critSounds.TryDetection()
	assert_true(ok, msg)
	assert_true(ns.observeCLEU, "the session override is set by the explicit click")
	assert_true(ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
	assert_eq(ns.critSounds.DetectionState(), "unverified", "registration alone is not delivery")
	Mocks.SetCLEU(event("SPELL_DAMAGE", true))
	Mocks.Fire("COMBAT_LOG_EVENT_UNFILTERED")
	assert_eq(ns.critSounds.diagnostics.delivered, 1)
	assert_eq(ns.critSounds.diagnostics.playerCrits, 1)
	assert_eq(#calls, 1, "playback is attempted after a readable player crit")
	assert_eq(calls[1][1], BAM)
	assert_eq(ns.critSounds.DetectionState(), "verified")
	assert_true(ns.critSounds.Status():find("verified", 1, true) ~= nil)
	assert_true(ns.critSounds.Status():find("last playback=played", 1, true) ~= nil)
end)

T.register("crit sounds: a refused subscription is reported as rejected, never as working", function()
	local e = Mocks.NewEnv()
	local frame = e.ns.eventFrame
	local original = frame.RegisterEvent
	frame.RegisterEvent = function(self, name)
		if name == "COMBAT_LOG_EVENT_UNFILTERED" then return false end
		return original(self, name)
	end
	local ok, msg = e.ns.critSounds.TryDetection()
	assert_false(ok)
	assert_true(msg:find("refused", 1, true) ~= nil)
	assert_eq(e.ns.critSounds.DetectionState(), "rejected")
	assert_true(e.ns.critSounds.Status():find("rejected", 1, true) ~= nil)
	assert_false(e.ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
end)

T.register("crit sounds: a missing combat-log API is unsupported and attempts nothing", function()
	local e = Mocks.NewEnv({ noCLEU = true })
	assert_false(e.ns.api.CombatLogAvailable())
	local ok, msg = e.ns.critSounds.TryDetection()
	assert_false(ok)
	assert_true(msg:find("unavailable", 1, true) ~= nil)
	assert_eq(e.ns.critSounds.DetectionState(), "unsupported")
	assert_false(e.ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
	assert_true(e.ns.observeCLEU, "the explicit click records the session intent")
	assert_true(e.ns.critSounds.Status():find("unsupported", 1, true) ~= nil)
end)

T.register("crit sounds: the detection override is session-only and never saved", function()
	local e = Mocks.NewEnv()
	assert_nil(e.ns.observeCLEU)
	e.ns.critSounds.TryDetection()
	assert_true(e.ns.observeCLEU)
	local db = _G.EllesmereUI_HoTPredictionDB
	assert_nil(db.observeCLEU, "no override in SavedVariables")
	assert_nil(db.critSounds.observeCLEU, "no override in the sounds settings")
	assert_nil(db.critSounds.attempts, "counters are not saved")
	-- A fresh restricted load starts with no override and no registration.
	local ns = restrictedEnv()
	assert_nil(ns.observeCLEU)
	assert_false(ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
end)

T.register("crit sounds: a disabled helper refuses detection and filters playback", function()
	local e, calls = env()
	e.ns.db.critSounds.enabled = true
	e.ns.SetRuntimeEnabled(false)
	local ok, msg = e.ns.critSounds.TryDetection()
	assert_false(ok)
	assert_true(msg:find("disabled", 1, true) ~= nil)
	assert_eq(e.ns.critSounds.DetectionState(), "disabled")
	e.ns.critSounds.HandleCLEU(event("SPELL_DAMAGE", true))
	assert_eq(#calls, 0)
	assert_false(e.ns.critSounds.Play(false))
	assert_eq(#calls, 0)
end)

T.register("crit sounds: status reports registration, delivery, observed crits and playback honestly", function()
	local e, calls = env()
	local s = e.ns.critSounds
	s.diagnostics.delivered, s.diagnostics.playerCrits = 3, 0
	e.ns.db.critSounds.enabled = true
	local status = s.Status()
	assert_true(status:find("registered=", 1, true) ~= nil)
	assert_true(status:find("events delivered=3", 1, true) ~= nil)
	assert_true(status:find("readable player crits=0", 1, true) ~= nil)
	assert_true(status:find("last playback=no attempt", 1, true) ~= nil)
	assert_eq(s.DetectionState(), "delivering")
	Mocks.SetCLEU(event("SPELL_HEAL", true))
	Mocks.Fire("COMBAT_LOG_EVENT_UNFILTERED")
	assert_eq(s.diagnostics.delivered, 4)
	assert_eq(s.diagnostics.playerCrits, 1)
	assert_eq(#calls, 1)
	assert_eq(s.DetectionState(), "verified")
	assert_true(s.Status():find("last playback=played", 1, true) ~= nil)
end)

T.register("crit sounds: incoming combat-text events are never registered as guesses", function()
	local ns = restrictedEnv()
	ns.critSounds.TryDetection()
	assert_false(ns.eventRegistered("UNIT_COMBAT"))
	assert_false(ns.eventRegistered("COMBAT_TEXT_UPDATE"))
end)

T.register("crit sounds: the old blank default migrates once and a later blank choice is preserved", function()
	local ns = presetEnv({ critSounds = { path = "" } })
	assert_eq(ns.db.critSounds.path, BAM, "the blank legacy default becomes bam.mp3")
	assert_eq(ns.db.schema, 2, "the migration marker is written")
	ns.db.critSounds.path = ""
	ns.InitDatabase()
	assert_eq(ns.db.critSounds.path, "", "after the marker a deliberate blank (built-in) is kept")
	local ns2 = presetEnv({ critSounds = { path = "Interface\\AddOns\\DoHelper\\Sounds\\custom.ogg" } })
	assert_eq(ns2.db.critSounds.path, "Interface\\AddOns\\DoHelper\\Sounds\\custom.ogg", "a custom path is preserved")
	local ns3 = presetEnv({})
	assert_eq(ns3.db.critSounds.path, BAM, "a fresh install defaults to bam.mp3")
end)

T.register("crit sounds: options tab saves custom file, tests and switches cleanly", function()
	local e, calls = env()
	local f = e.ns.OpenOptions()
	click(f.controls.soundsTab)
	assert_eq(f.selectedTab, "sounds")
	assert_true(f.soundsPage:IsShown()); assert_false(f.notesPage:IsShown())
	local c = f.controls
	c.soundsEnabled:SetChecked(true)
	c.soundsPath:SetText("Interface\\AddOns\\DoHelper\\Sounds\\bam.mp3")
	c.soundsCooldown:SetText("0.75")
	click(c.soundsTest)
	assert_eq(#calls, 1)
	assert_true(e.ns.db.critSounds.enabled)
	assert_eq(e.ns.db.critSounds.cooldown, 0.75)
	click(c.notesTab); assert_false(f.soundsPage:IsShown())
	click(c.soundsTab); assert_eq(c.soundsPath:GetText(), e.ns.db.critSounds.path)
	assert_nil(f.soundsPage:GetScript("OnUpdate"))
end)

T.register("crit sounds: the cue picker cycles bam.mp3 and the built-in warning", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions("sounds")
	local c = f.controls
	assert_eq(c.soundsPath:GetText(), BAM, "the field shows the bundled default")
	assert_eq(c.soundsCue:GetText(), "Cue: bam.mp3")
	click(c.soundsCue)
	assert_eq(c.soundsPath:GetText(), "")
	assert_eq(c.soundsCue:GetText(), "Cue: built-in")
	click(c.soundsCue)
	assert_eq(c.soundsPath:GetText(), BAM)
	assert_eq(c.soundsCue:GetText(), "Cue: bam.mp3")
	click(c.soundsTest)
	assert_eq(e.ns.db.critSounds.path, BAM)
end)

T.register("crit sounds: the GUI Try crit detection button is the only automatic-registration path", function()
	local ns = restrictedEnv()
	ns.db.critSounds.enabled = true
	local f = ns.OpenOptions("sounds")
	assert_false(ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED"), "opening the tab registers nothing")
	click(f.controls.soundsDetect)
	assert_true(ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
	assert_true(ns.observeCLEU)
	click(f.controls.soundsStop)
	assert_false(ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
	assert_false(ns.observeCLEU)
end)

T.register("crit sounds: sounds page controls fit and do not overlap", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions("sounds")
	local pageRect = Mocks.FrameRect(f.soundsPage)
	local keys = { "soundsApply", "soundsTest", "soundsDetect", "soundsStop", "soundsCue", "soundsChannel" }
	local rects = {}
	for _, key in ipairs(keys) do
		local r = Mocks.FrameRect(f.controls[key])
		assert_true(r.left >= pageRect.left and r.right <= pageRect.right, key .. " stays inside the page horizontally")
		assert_true(r.top <= pageRect.top and r.bottom >= pageRect.bottom, key .. " stays inside the page vertically")
		rects[key] = r
	end
	for i = 1, #keys do
		for j = i + 1, #keys do
			assert_false(Mocks.RectsOverlap(rects[keys[i]], rects[keys[j]]), keys[i] .. " must not overlap " .. keys[j])
		end
	end
	assert_not_nil(Mocks.FindFontString(f.soundsPage, "crit detection="), "the detection status line is shown")
end)
