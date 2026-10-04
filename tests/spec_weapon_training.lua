-- tests/spec_weapon_training.lua
-- DoHelper weapon training reference: static model coverage, the lazy tab,
-- scroll/trainer detail behaviour, branding/aliases, and the guarded map
-- adapters (classic/modern resolution, native + TomTom, false/error/secret,
-- and combat refusal).
local function click(widget, ...)
	widget:GetScript("OnClick")(widget, ...)
end

local function contains(text, fragment)
	return type(text) == "string" and text:find(fragment, 1, true) ~= nil
end

local function hasValue(list, value)
	for _, v in ipairs(list or {}) do if v == value then return true end end
	return false
end

local function weaponKeys(classKey, wt)
	local out = {}
	for _, w in ipairs(wt.WeaponsForClass(classKey)) do out[#out + 1] = w.key end
	return out
end

local function findEntry(entries, fragment)
	for _, e in ipairs(entries) do
		if contains(e.text, fragment) then return e end
	end
	return nil
end

-----------------------------------------------------------------------------
-- static model
-----------------------------------------------------------------------------

T.register("weapon training: every race-class combination is classified and all classes reachable", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining
	assert_eq(#wt.RACE_ORDER, 10, "all ten race rows are present")
	assert_eq(#wt.CLASS_ORDER, 9, "all nine classes are present")

	local valid = 0
	for _, rk in ipairs(wt.RACE_ORDER) do
		local race = wt.RACES_BY_KEY[rk]
		assert_not_nil(race, "race " .. rk)
		for _, ck in ipairs(wt.CLASS_ORDER) do
			local expected = false
			for _, k in ipairs(race.classes) do if k == ck then expected = true end end
			assert_eq(wt.IsValidCombo(rk, ck), expected, rk .. " / " .. ck)
			if expected then valid = valid + 1 end
		end
		local list = wt.ClassesForRace(rk)
		assert_true(#list > 0, rk .. " must expose at least one class")
		for _, c in ipairs(list) do assert_true(wt.IsValidCombo(rk, c.key), "ClassesForRace must only return valid classes") end
	end
	assert_true(valid > 0, "some combinations are valid")

	-- Every class is reachable from at least one race.
	for _, ck in ipairs(wt.CLASS_ORDER) do
		local found = false
		for _, rk in ipairs(wt.RACE_ORDER) do if wt.IsValidCombo(rk, ck) then found = true end end
		assert_true(found, "class " .. ck .. " is unreachable")
	end

	-- Rails: invalid combos are refused by the model.
	assert_false(wt.IsValidCombo("TAUREN", "PALADIN"))
	assert_false(wt.IsValidCombo("GNOME", "DRUID"))
	assert_false(wt.IsValidCombo("HUMAN", "SHAMAN"))
	assert_true(wt.IsValidCombo("UNDEAD", "PALADIN"), "Undead paladin is a supplied Forever addition")
	assert_true(wt.IsValidCombo("ORC", "MAGE"))
end)

T.register("weapon training: class eligibility, provisional polearm and Forever changes", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining

	local warrior = weaponKeys("WARRIOR", wt)
	assert_eq(#warrior, 14, "warrior has all conventional weapons")
	assert_false(hasValue(warrior, "WAND"), "warriors never use wands")
	assert_true(hasValue(warrior, "POLEARM"))

	assert_false(hasValue(weaponKeys("HUNTER", wt), "MACE1"))
	assert_false(hasValue(weaponKeys("HUNTER", wt), "WAND"))
	assert_true(hasValue(weaponKeys("HUNTER", wt), "BOW"))

	assert_true(hasValue(weaponKeys("ROGUE", wt), "AXE1"), "Forever rogue one-handed axe")
	assert_true(hasValue(weaponKeys("SHAMAN", wt), "AXE2"), "Forever shaman two-handed axe")
	assert_true(hasValue(weaponKeys("SHAMAN", wt), "MACE2"), "Forever shaman two-handed mace")
	assert_false(hasValue(weaponKeys("DRUID", wt), "AXE1"))
	assert_false(hasValue(weaponKeys("DRUID", wt), "BOW"))

	local druid = wt.WeaponsForClass("DRUID")
	local pole
	for _, w in ipairs(druid) do if w.key == "POLEARM" then pole = w end end
	assert_not_nil(pole, "druid polearm row exists")
	assert_eq(pole.status, "provisional", "druid polearm is provisional")
	assert_eq(pole.minLevel, 20)

	local priest = wt.WeaponsForClass("PRIEST")
	local wand
	for _, w in ipairs(priest) do if w.key == "WAND" then wand = w end end
	assert_not_nil(wand)
	assert_true(wand.noTrainer, "wand is a default proficiency with no trainer")

	-- Every class's weapons exist in the canonical order with valid statuses.
	for _, ck in ipairs(wt.CLASS_ORDER) do
		local seen = {}
		for _, w in ipairs(wt.WeaponsForClass(ck)) do
			assert_not_nil(wt.WEAPONS[w.key], "unknown weapon " .. tostring(w.key))
			assert_true(w.status == "allowed" or w.status == "provisional")
			assert_false(seen[w.key] == true, "duplicate weapon " .. w.key .. " for " .. ck)
			seen[w.key] = true
		end
	end
end)

T.register("weapon training: starts, partial/unknown data and the Tauren druid example", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining

	-- Tauren Druid: Mulgore -> Thunder Bluff, supplied MACE1 + STAFF.
	local race = wt.Race("TAUREN")
	assert_eq(race.startZone, "Mulgore")
	assert_eq(race.capital, "Thunder Bluff")
	assert_eq(race.faction, "Horde")
	local start = wt.Starts("TAUREN", "DRUID")
	assert_true(hasValue(start.weapons, "MACE1"))
	assert_true(hasValue(start.weapons, "STAFF"))
	assert_eq(start.conf, "CLASSIC")
	assert_true(wt.IsStarting("TAUREN", "DRUID", "MACE1"))
	assert_false(wt.IsStarting("TAUREN", "DRUID", "MACE2"))

	-- Trainer routing for the example.
	local function ids(raceKey, classKey, weaponKey)
		local out = {}
		for _, t in ipairs(wt.TrainersFor(raceKey, classKey, weaponKey)) do out[#out + 1] = t.id end
		return out
	end
	assert_true(hasValue(ids("TAUREN", "DRUID", "MACE2"), "ansekhwa"), "2H mace -> Ansekhwa")
	assert_true(hasValue(ids("TAUREN", "DRUID", "DAGGER"), "sayoc"), "dagger -> Sayoc")
	assert_true(hasValue(ids("TAUREN", "DRUID", "DAGGER"), "archibald"), "dagger -> Archibald")
	assert_true(hasValue(ids("TAUREN", "DRUID", "FIST"), "sayoc"), "fist -> Sayoc")
	assert_true(hasValue(ids("TAUREN", "DRUID", "POLEARM"), "archibald"), "provisional polearm -> Archibald")

	-- Hunter: only partial ranged starts supplied; no silent Orc-bow correction.
	assert_true(hasValue(wt.Starts("NIGHTELF", "HUNTER").weapons, "BOW"))
	assert_true(hasValue(wt.Starts("ORC", "HUNTER").weapons, "GUN"))
	assert_false(hasValue(wt.Starts("ORC", "HUNTER").weapons, "BOW"), "Orc hunter start is supplied as GUN")
	assert_eq(wt.Starts("HUMAN", "HUNTER").conf, "UNCONFIRMED")
	assert_eq(#wt.Starts("HUMAN", "HUNTER").weapons, 0)
	assert_eq(wt.Starts("SKYBORNE_HIGH", "HUNTER").conf, "UNCONFIRMED")

	-- Rogue qualifier: some configurations add Sword; Skyborne exact unknown.
	assert_true(hasValue(wt.Starts("HUMAN", "ROGUE").weapons, "SWORD1"))
	assert_false(hasValue(wt.Starts("DWARF", "ROGUE").weapons, "SWORD1"))
	assert_eq(wt.Starts("SKYBORNE_HIGH", "ROGUE").conf, "UNCONFIRMED")

	-- Shaman: new Dwarf start is client-verify; classic races are established.
	assert_eq(wt.Starts("DWARF", "SHAMAN").conf, "CHECK")
	assert_eq(wt.Starts("ORC", "SHAMAN").conf, "CLASSIC")
	assert_eq(wt.Starts("SKYBORNE_WIND", "SHAMAN").conf, "UNCONFIRMED")

	-- Skyborne have no invented faction or start zone.
	assert_eq(wt.Race("SKYBORNE_HIGH").faction, nil)
	assert_eq(wt.Race("SKYBORNE_WIND").startZone, nil)

	-- BuildEntries marks the provisional polearm row and carries trainer buttons.
	local entries = wt.BuildEntries("TAUREN", "DRUID")
	local poleRow = findEntry(entries, "Polearm")
	assert_not_nil(poleRow)
	assert_true(contains(poleRow.text, "provisional"))
	assert_not_nil(poleRow.trainers)
	local hasArchibald = false
	for _, t in ipairs(poleRow.trainers) do if t.id == "archibald" then hasArchibald = true end end
	assert_true(hasArchibald, "provisional polearm row must offer Archibald")
end)

T.register("weapon training: eight trainers, faction matching and Skyborne both-factions", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining
	assert_eq(#wt.AllTrainers(), 8, "all eight supplied trainers are present")

	assert_eq(wt.Trainer("woo_ping").faction, "Alliance")
	assert_true(contains(wt.Trainer("woo_ping").city, "Stormwind"))
	assert_eq(wt.Trainer("archibald").faction, "Horde")
	assert_eq(wt.Trainer("woo_ping").weapons[1], "CROSSBOW")
	assert_true(wt.Trainer("woo_ping").locationApprox, "locations are approximate, not exact")

	local function ids(raceKey, classKey, weaponKey)
		local out = {}
		for _, t in ipairs(wt.TrainersFor(raceKey, classKey, weaponKey)) do out[#out + 1] = t.id end
		return out
	end

	-- Alliance crossbow: only Alliance trainers.
	local alliance = ids("HUMAN", "WARRIOR", "CROSSBOW")
	assert_true(hasValue(alliance, "woo_ping"))
	assert_true(hasValue(alliance, "bixi"))
	assert_false(hasValue(alliance, "archibald"), "no Horde trainer for an Alliance race")

	-- Horde crossbow: only the Horde trainer.
	local horde = ids("TAUREN", "WARRIOR", "CROSSBOW")
	assert_eq(#horde, 1)
	assert_eq(horde[1], "archibald")

	-- Skyborne (unknown faction) may show both factions, clearly listed.
	local sky = ids("SKYBORNE_HIGH", "WARRIOR", "DAGGER")
	assert_true(hasValue(sky, "sayoc") and hasValue(sky, "woo_ping"), "Skyborne lists both factions")

	-- Wands have no trainer for any caster.
	assert_eq(#wt.TrainersFor("HUMAN", "MAGE", "WAND"), 0)
	assert_eq(#wt.TrainersFor("HUMAN", "WARRIOR", "WAND"), 0, "ineligible weapon yields no trainer")
end)

-----------------------------------------------------------------------------
-- lazy tab / scroll / reuse / detail
-----------------------------------------------------------------------------

T.register("weapon training: tab is lazy, hides the preview and restores old tabs", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	assert_true(f:IsShown())
	assert_false(f.weaponPage:IsShown(), "weapon page is not shown on the settings tab")
	assert_true(f.preview:IsShown(), "preview visible on the settings tab")
	assert_nil(f:GetScript("OnUpdate"), "options window has no idle updater")

	click(f.controls.weaponTab)
	assert_eq(f.selectedTab, "weapons")
	assert_true(f.weaponPage:IsShown())
	assert_false(f.preview:IsShown(), "preview hidden on the weapon tab")

	-- All existing tabs still work, and the preview returns.
	for _, pair in ipairs({ { "notesTab", "notes" }, { "combatTab", "combat" }, { "spellsTab", "spells" } }) do
		click(f.controls[pair[1]])
		assert_eq(f.selectedTab, pair[2], pair[1])
		assert_false(f.weaponPage:IsShown())
		assert_true(f.preview:IsShown(), "preview restored on " .. pair[2])
	end
	click(f.controls.settingsTab)
	assert_eq(f.selectedTab, "settings")
	assert_true(f.preview:IsShown())
	assert_false(f.weaponPage:IsShown())
end)

T.register("weapon training: selectors reach all races/classes, rows reuse and scroll clamps", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.weaponTab)
	local page = f.weaponPage
	local wt = e.ns.weaponTraining

	-- Cycle through every race and confirm the selected class is always valid.
	local seenRaces = {}
	for _ = 1, #wt.RACE_ORDER do
		assert_true(wt.IsValidCombo(page.selectedRace, page.selectedClass), page.selectedRace .. "/" .. page.selectedClass)
		seenRaces[page.selectedRace] = true
		click(page.buttons.raceNext)
	end
	for _, rk in ipairs(wt.RACE_ORDER) do assert_true(seenRaces[rk], "race reachable: " .. rk) end
	assert_eq(page.selectedRace, "HUMAN", "cycling wraps back to the first race")

	-- All classes reachable across races.
	local seenClasses = {}
	for _ = 1, #wt.RACE_ORDER do
		local n = #wt.ClassesForRace(page.selectedRace)
		for _ = 1, n do
			seenClasses[page.selectedClass] = true
			click(page.buttons.classNext)
		end
		click(page.buttons.raceNext)
	end
	for _, ck in ipairs(wt.CLASS_ORDER) do assert_true(seenClasses[ck], "class reachable: " .. ck) end

	-- Row widgets are reused across refreshes.
	local blocksBefore = page.blocks
	assert_true(#blocksBefore > 0)
	click(page.buttons.classNext)
	click(page.buttons.classPrev)
	assert_true(page.blocks[1] == blocksBefore[1], "the first row widget is reused")

	-- Scroll range is clamped on the mouse wheel.
	page.content:SetHeight(2000)
	page.scroll:UpdateScrollChildRect()
	local wheel = page.scroll:GetScript("OnMouseWheel")
	wheel(page.scroll, -1000)
	assert_eq(page.scroll:GetVerticalScroll(), page.scroll:GetVerticalScrollRange())
	wheel(page.scroll, 1000)
	assert_eq(page.scroll:GetVerticalScroll(), 0)
end)

T.register("weapon training: clicking a trainer opens one reused detail panel and never moves the map", function()
	local e = Mocks.NewEnv()
	local f = e.ns.OpenOptions()
	click(f.controls.weaponTab)
	local page = f.weaponPage
	local wt = e.ns.weaponTraining

	local first
	for _, b in ipairs(page.visibleTrainerButtons) do
		if b.trainerId == "woo_ping" then first = b end
	end
	assert_not_nil(first, "Human Warrior must offer Woo Ping for crossbows/daggers")
	click(first)
	assert_eq(wt.lastTrainer and wt.lastTrainer.id, "woo_ping")
	local detail = _G["EllesmereUI_HoTPredictionWeaponTrainer"]
	assert_not_nil(detail)
	assert_true(detail:IsShown())
	assert_eq(detail, wt.EnsureDetail(), "the one detail panel is reused")
	assert_nil(Mocks.waypoint, "opening a trainer must not place a waypoint")
	assert_nil(f:GetScript("OnUpdate"), "no idle updater on the options window")
	assert_nil(detail:GetScript("OnUpdate"), "no idle updater on the detail panel")

	-- Selecting a second trainer reuses the same frame.
	local second
	for _, b in ipairs(page.visibleTrainerButtons) do
		if b.trainerId == "buliwyf" then second = b end
	end
	assert_not_nil(second)
	click(second)
	assert_eq(_G["EllesmereUI_HoTPredictionWeaponTrainer"], detail)
	assert_eq(wt.lastTrainer.id, "buliwyf")
	assert_nil(Mocks.waypoint)

	-- Escape registry holds the name exactly once.
	local hits = 0
	for i = 1, #UISpecialFrames do if UISpecialFrames[i] == "EllesmereUI_HoTPredictionWeaponTrainer" then hits = hits + 1 end end
	assert_eq(hits, 1)

	click(detail.closeButton)
	assert_false(detail:IsShown())
end)

T.register("weapon training: detail text reports city, district, coordinates and confidence", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining
	local txt = wt.DetailText(wt.Trainer("ansekhwa"))
	assert_true(contains(txt, "Thunder Bluff"))
	assert_true(contains(txt, "Lower Rise"))
	assert_true(contains(txt, "40.9, 62.7"))
	assert_true(contains(txt, "Two-Handed Mace"))
	assert_true(contains(txt, "Classic-established reference"))
	assert_true(contains(txt, "not live verified"))
end)

-----------------------------------------------------------------------------
-- map adapter
-----------------------------------------------------------------------------

T.register("weapon training: coordinates normalize and map ids resolve classic and modern only when valid", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining

	assert_near(wt.NormalizeCoord(57.1), 0.571, 1e-9)
	assert_near(wt.NormalizeCoord(0.5), 0.5, 1e-9)
	assert_nil(wt.NormalizeCoord(-1))
	assert_nil(wt.NormalizeCoord(150))
	assert_nil(wt.NormalizeCoord(Mocks.MakeSecret()))
	assert_nil(wt.NormalizeCoord("nope"))

	local cands = wt.MapCandidates("Stormwind")
	assert_eq(#cands, 2)
	assert_eq(cands[1].mapID, 1453)
	assert_eq(cands[2].mapID, 84)

	-- Classic client exposes only the classic id.
	C_Map = { GetMapInfo = function(id) if id == 1453 then return { mapType = "CITY", name = "Stormwind" } end end }
	local mapID, source = wt.ResolveMap("Stormwind")
	assert_eq(mapID, 1453)
	assert_eq(source, "classic")

	-- Modern client exposes only the modern id.
	C_Map = { GetMapInfo = function(id) if id == 84 then return { mapType = "CITY", name = "Stormwind" } end end }
	mapID, source = wt.ResolveMap("Stormwind")
	assert_eq(mapID, 84)
	assert_eq(source, "modern")

	-- Wrong map type fails closed.
	C_Map = { GetMapInfo = function() return { mapType = "ZONE", name = "Stormwind" } end }
	local bad, _, _, reason = wt.ResolveMap("Stormwind")
	assert_nil(bad)
	assert_true(contains(reason, "not a city"))

	-- Localized / renamed client fails closed rather than placing a wrong waypoint.
	C_Map = { GetMapInfo = function() return { mapType = "CITY", name = "Sturmwind" } end }
	bad, _, _, reason = wt.ResolveMap("Stormwind")
	assert_nil(bad)
	assert_true(contains(reason, "localized") or contains(reason, "not 'Stormwind'"))

	-- Missing API yields a useful reason, never an exception.
	C_Map = nil
	bad, _, _, reason = wt.ResolveMap("Stormwind")
	assert_nil(bad)
	assert_true(contains(reason, "GetMapInfo"))

	-- Unknown city fails closed.
	bad = wt.ResolveMap("Atlantis")
	assert_nil(bad)
end)

T.register("weapon training: native waypoint success, TomTom fallback, and false/error/secret honesty", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining

	-- Native success; coordinates normalized to 0-1 and SuperTrack called.
	C_Map = {
		GetMapInfo = function(id) if id == 1453 then return { mapType = "CITY", name = "Stormwind" } end end,
		SetUserWaypoint = function(point) Mocks.waypoint = point end,
	}
	UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { uiMapID = id, x = x, y = y } end }
	C_SuperTrack = { SetSuperTrackedUserWaypoint = function(v) Mocks.superTracked = v end }
	local ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_true(ok, "native waypoint success")
	assert_eq(method, "native")
	assert_near(Mocks.waypoint.x, 0.571, 1e-9)
	assert_near(Mocks.waypoint.y, 0.577, 1e-9)
	assert_eq(Mocks.waypoint.uiMapID, 1453)
	assert_true(Mocks.superTracked)

	-- Native explicit false falls back to TomTom.
	Mocks.waypoint, Mocks.superTracked = nil, nil
	C_Map.SetUserWaypoint = function() return false end
	local tomtomCalls = 0
	TomTom = { AddWaypoint = function(_, id, x, y) tomtomCalls = tomtomCalls + 1; Mocks.waypoint = { uiMapID = id, x = x, y = y }; return true end }
	ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_true(ok)
	assert_eq(method, "tomtom")
	assert_eq(tomtomCalls, 1)
	assert_true(contains(wt.lastWaypoint.nativeError, "false"))

	-- Native error + TomTom false: honest failure, no success claim.
	C_Map.SetUserWaypoint = function() error("boom") end
	TomTom.AddWaypoint = function() return false end
	Mocks.waypoint = nil
	ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_false(ok)
	assert_eq(method, "unsupported")
	assert_not_nil(wt.lastWaypoint.nativeError)
	assert_not_nil(wt.lastWaypoint.tomtomError)
	assert_nil(Mocks.waypoint)

	-- Secret point is refused and never passed to the client.
	C_Map.SetUserWaypoint = function() return true end
	UiMapPoint = { CreateFromCoordinates = function() return Mocks.MakeSecret() end }
	TomTom = nil
	Mocks.waypoint = nil
	ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_false(ok)
	assert_eq(method, "unsupported")
	assert_nil(Mocks.waypoint)

	-- Missing APIs: useful coordinates in the message, not an exception.
	C_Map, UiMapPoint = nil, nil
	ok, method, msg = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_false(ok)
	assert_eq(method, "unresolved")
	assert_true(contains(msg, "57.1"))
	assert_true(contains(msg, "no waypoint placed"))

	-- Out-of-range coordinates are refused before any API call.
	ok, method = wt.SetWaypoint("Stormwind", 999, 57.7)
	assert_false(ok)
	assert_eq(method, "invalid")
end)

T.register("weapon training: combat refusal and Show map are guarded", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining
	C_Map = {
		GetMapInfo = function(id) if id == 1453 then return { mapType = "CITY", name = "Stormwind" } end end,
		SetUserWaypoint = function(p) Mocks.waypoint = p end,
		OpenWorldMap = function(id) Mocks.openedMap = id end,
	}
	UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { uiMapID = id, x = x, y = y } end }

	-- Waypoint succeeds out of combat.
	local ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_true(ok)
	assert_eq(method, "native")

	-- Combat refuses and leaves the map/waypoint untouched.
	Mocks.inCombat = true
	Mocks.waypoint, Mocks.openedMap = nil, nil
	local before = Mocks.waypoint
	ok, method, msg = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_false(ok)
	assert_eq(method, "combat")
	assert_true(contains(msg, "Combat"))
	assert_eq(Mocks.waypoint, before)
	ok, method = wt.ShowMap("Stormwind")
	assert_false(ok)
	assert_eq(method, "combat")
	assert_nil(Mocks.openedMap)
	Mocks.inCombat = false

	-- Show map works out of combat.
	ok, method, msg = wt.ShowMap("Stormwind")
	assert_true(ok)
	assert_eq(method, "native")
	assert_eq(Mocks.openedMap, 1453)

	-- Resolvable map but no opening API: useful failure, not an exception.
	C_Map.OpenWorldMap = nil
	ok, method, msg = wt.ShowMap("Stormwind")
	assert_false(ok)
	assert_eq(method, "unsupported")
	assert_true(contains(msg, "1453"))
end)

-----------------------------------------------------------------------------
-- branding, aliases, legacy settings
-----------------------------------------------------------------------------

T.register("weapon training: DoHelper branding, aliases and legacy settings compatibility", function()
	local e = Mocks.NewEnv()
	assert_eq(e.ns.version, "0.9.0")
	assert_eq(SLASH_DOHELPER1, "/dohelper")
	assert_eq(SLASH_DOHELPER2, "/dh")
	assert_true(type(SlashCmdList["DOHELPER"]) == "function")
	-- Historical commands remain aliases.
	assert_eq(SLASH_ELLESMEREUIHOTPRED1, "/euihot")
	assert_eq(SLASH_ELLESMEREUIHOTPRED2, "/hotpred")
	assert_true(type(SlashCmdList["ELLESMEREUIHOTPRED"]) == "function")

	-- /dohelper weapons opens the weapon tab; the historical command does too.
	SlashCmdList["DOHELPER"]("weapons")
	local f = e.ns.optionsWindow
	assert_true(f:IsShown())
	assert_eq(f.selectedTab, "weapons")
	click(f.controls.settingsTab)
	e.ns.HandleCommand("weapons")
	assert_eq(e.ns.optionsWindow.selectedTab, "weapons")

	-- Public chat prefix.
	local before = #Mocks.chat
	e.ns.HandleCommand("help")
	assert_true(contains(Mocks.chat[before + 1], "[DoHelper]"), "chat prefix is DoHelper")

	-- Legacy category identifier is unchanged (settings-path compatibility).
	local captured
	Settings = {
		RegisterCanvasLayoutCategory = function(panel, name) captured = name; return { panel = panel } end,
		RegisterAddOnCategory = function() end,
	}
	e.ns.InitOptions()
	assert_eq(captured, "EllesmereUI HoT Prediction")
	Settings = nil

	-- TOC keeps the historical SavedVariables name and ships the new module.
	local toc = ReadFile((_G.__HOT_ROOT or ".") .. "/EllesmereUI_HoTPrediction/EllesmereUI_HoTPrediction.toc")
	assert_true(contains(toc, "DoHelper"))
	assert_true(contains(toc, "Version: 0.9.0"))
	assert_true(contains(toc, "SavedVariables: EllesmereUI_HoTPredictionDB"))
	assert_true(contains(toc, "WeaponTraining.lua"))

	-- The keybinding category is DoHelper but the binding globals are unchanged.
	assert_eq(BINDING_HEADER_ELLESMEREUI_HOTPRED, "DoHelper")
	assert_eq(BINDING_NAME_ELLESMEREUI_HOTPRED_TOGGLE_NOTES, "Toggle notes window")
end)

T.register("weapon training: legacy settings register once and saved data is preserved", function()
	local e = Mocks.NewEnv()
	local added = 0
	InterfaceOptions_AddCategory = function(panel)
		added = added + 1
		assert_eq(panel.name, "EllesmereUI HoT Prediction")
	end
	e.ns.InitOptions()
	e.ns.InitOptions()
	assert_eq(added, 1, "legacy Interface Options category registers exactly once")
	InterfaceOptions_AddCategory = nil

	-- SavedVariables keep their historical name and survive a reload merge.
	EllesmereUI_HoTPredictionDB = { notes = { text = "legacy note" }, alpha = 0.42, enabled = true }
	e.ns.InitDatabase()
	assert_eq(e.ns.db.notes.text, "legacy note")
	assert_eq(e.ns.db.alpha, 0.42)
	assert_true(EllesmereUI_HoTPredictionDB.notes.text == "legacy note", "no rename or migration")

	-- Re-merging the same SavedVariables (a reload) preserves the values.
	e.ns.InitDatabase()
	assert_eq(e.ns.db.notes.text, "legacy note")
	assert_eq(e.ns.db.alpha, 0.42)
end)
