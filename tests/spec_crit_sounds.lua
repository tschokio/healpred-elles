local function env()
	local e = Mocks.NewEnv()
	local calls = {}
	PlaySound = function(id, channel) calls[#calls + 1] = { id, channel }; return true end
	PlaySoundFile = function(path, channel) calls[#calls + 1] = { path, channel }; return true end
	return e, calls
end
local function event(sub, crit, source)
	local a = { [2] = sub, [4] = source or Mocks.playerGUID }
	a[(sub == "SWING_DAMAGE" or sub == "SPELL_HEAL" or sub == "SPELL_PERIODIC_HEAL") and 18 or 21] = crit
	return a
end
local function click(w) w:GetScript("OnClick")(w) end

T.register("crit sounds: disabled by default; preview works and no timer is added", function()
	local e, calls = env()
	e.ns.critSounds.HandleCLEU(event("SPELL_DAMAGE", true))
	assert_eq(#calls, 0)
	assert_true(e.ns.critSounds.Play(true))
	assert_eq(calls[1][1], 8959)
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
end)

T.register("crit sounds: restricted engines never acquire a new event subscription", function()
	Mocks.Reset()
	Mocks.SetBuild("12.0.1", 1, "", 120001)
	local ns = Mocks.LoadAddon()
	Mocks.Fire("ADDON_LOADED", "DoHelper")
	ns.db.critSounds.enabled = true
	ns.critSounds.Setup()
	assert_false(ns.eventRegistered("COMBAT_LOG_EVENT_UNFILTERED"))
	assert_true(ns.critSounds.Status():find("unavailable", 1, true) ~= nil)
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
