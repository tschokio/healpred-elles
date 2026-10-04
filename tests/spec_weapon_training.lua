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

local function toSet(list)
	local s = {}
	for _, v in ipairs(list or {}) do s[v] = true end
	return s
end

local function sameMembers(a, b)
	for k in pairs(a) do if not b[k] then return false end end
	for k in pairs(b) do if not a[k] then return false end end
	return true
end

-----------------------------------------------------------------------------
-- INDEPENDENT expected data, transcribed from WEAPON_TRAINING_REFERENCE.md /
-- the supplied document. These MUST NOT be derived from the production
-- tables, so a bad matrix/weapon/trainer edit is caught.
-----------------------------------------------------------------------------

local EXPECTED_RACE_CLASSES = {
	HUMAN = toSet({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "MAGE", "WARLOCK" }),
	DWARF = toSet({ "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN" }),
	NIGHTELF = toSet({ "WARRIOR", "HUNTER", "ROGUE", "PRIEST", "DRUID" }),
	GNOME = toSet({ "WARRIOR", "ROGUE", "PRIEST", "MAGE", "WARLOCK" }),
	ORC = toSet({ "WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "MAGE", "WARLOCK" }),
	UNDEAD = toSet({ "WARRIOR", "PALADIN", "ROGUE", "PRIEST", "MAGE", "WARLOCK" }),
	TAUREN = toSet({ "WARRIOR", "HUNTER", "SHAMAN", "DRUID" }),
	TROLL = toSet({ "WARRIOR", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK" }),
	SKYBORNE_HIGH = toSet({ "WARRIOR", "HUNTER", "ROGUE", "MAGE", "DRUID" }),
	SKYBORNE_WIND = toSet({ "WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "DRUID" }),
}

local EXPECTED_CLASS_WEAPONS = {
	WARRIOR = { allowed = toSet({ "AXE1", "AXE2", "SWORD1", "SWORD2", "MACE1", "MACE2",
		"DAGGER", "FIST", "STAFF", "POLEARM", "BOW", "CROSSBOW", "GUN", "THROWN" }), provisional = {} },
	PALADIN = { allowed = toSet({ "AXE1", "AXE2", "SWORD1", "SWORD2", "MACE1", "MACE2", "POLEARM" }), provisional = {} },
	HUNTER = { allowed = toSet({ "AXE1", "AXE2", "SWORD1", "SWORD2", "DAGGER", "FIST",
		"STAFF", "POLEARM", "BOW", "CROSSBOW", "GUN", "THROWN" }), provisional = {} },
	ROGUE = { allowed = toSet({ "DAGGER", "THROWN", "SWORD1", "AXE1", "MACE1", "FIST", "BOW", "CROSSBOW", "GUN" }), provisional = {} },
	PRIEST = { allowed = toSet({ "MACE1", "DAGGER", "STAFF", "WAND" }), provisional = {} },
	SHAMAN = { allowed = toSet({ "MACE1", "MACE2", "AXE1", "AXE2", "DAGGER", "FIST", "STAFF" }), provisional = {} },
	MAGE = { allowed = toSet({ "STAFF", "WAND", "DAGGER", "SWORD1" }), provisional = {} },
	WARLOCK = { allowed = toSet({ "DAGGER", "WAND", "STAFF", "SWORD1" }), provisional = {} },
	DRUID = { allowed = toSet({ "MACE1", "MACE2", "STAFF", "DAGGER", "FIST" }), provisional = toSet({ "POLEARM" }) },
}

local EXPECTED_TRAINERS = {
	woo_ping = { x = 57.1, y = 57.7, city = "Stormwind", district = "Trade District",
		weapons = toSet({ "CROSSBOW", "DAGGER", "SWORD1", "SWORD2", "STAFF", "POLEARM" }) },
	buliwyf = { x = 62.2, y = 89.6, city = "Ironforge", district = "Military Ward",
		weapons = toSet({ "FIST", "GUN", "AXE1", "AXE2", "MACE1", "MACE2" }) },
	bixi = { x = 62.2, y = 89.6, city = "Ironforge", district = "Military Ward",
		weapons = toSet({ "CROSSBOW", "DAGGER", "THROWN" }) },
	ilyenia = { x = 57.6, y = 46.7, city = "Darnassus", district = "Warrior's Terrace",
		weapons = toSet({ "BOW", "DAGGER", "FIST", "STAFF", "THROWN" }) },
	sayoc = { x = 81.5, y = 19.6, city = "Orgrimmar", district = "Valley of Honor",
		weapons = toSet({ "BOW", "DAGGER", "FIST", "AXE1", "AXE2", "STAFF", "THROWN" }) },
	hanashi = { x = 81.5, y = 19.6, city = "Orgrimmar", district = "Valley of Honor",
		weapons = toSet({ "BOW", "AXE1", "AXE2", "STAFF", "THROWN" }) },
	ansekhwa = { x = 40.9, y = 62.7, city = "Thunder Bluff", district = "Lower Rise",
		weapons = toSet({ "GUN", "MACE1", "MACE2", "STAFF" }) },
	archibald = { x = 57.3, y = 32.8, city = "Undercity", district = "War Quarter",
		weapons = toSet({ "CROSSBOW", "DAGGER", "SWORD1", "SWORD2", "POLEARM" }) },
}

-----------------------------------------------------------------------------
-- static model
-----------------------------------------------------------------------------

T.register("weapon training: every race-class combination is classified and all classes reachable", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining
	assert_eq(#wt.RACE_ORDER, 10, "all ten race rows are present")
	assert_eq(#wt.CLASS_ORDER, 9, "all nine classes are present")

	local valid = 0
	-- Independent expected matrix: 10 race rows, exact 9-class membership.
	for rk, expectedSet in pairs(EXPECTED_RACE_CLASSES) do
		local race = wt.RACES_BY_KEY[rk]
		assert_not_nil(race, "race " .. rk)
		for _, ck in ipairs(wt.CLASS_ORDER) do
			local expected = expectedSet[ck] == true
			assert_eq(wt.IsValidCombo(rk, ck), expected, rk .. " / " .. ck)
			if expected then valid = valid + 1 end
		end
		local actualSet = toSet({})
		for _, c in ipairs(wt.ClassesForRace(rk)) do actualSet[c.key] = true end
		assert_true(sameMembers(actualSet, expectedSet), rk .. " class list must match the supplied document")
		local list = wt.ClassesForRace(rk)
		assert_true(#list > 0, rk .. " must expose at least one class")
		for _, c in ipairs(list) do assert_true(wt.IsValidCombo(rk, c.key), "ClassesForRace must only return valid classes") end
	end
	assert_eq(valid, 56, "exact total number of valid race/class combinations")
	for rk in pairs(wt.RACES_BY_KEY) do assert_not_nil(EXPECTED_RACE_CLASSES[rk], "unexpected race " .. rk) end
	assert_eq(#wt.RACE_ORDER, 10, "all ten race rows are present")

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

	-- Exact independently-transcribed weapon membership for all nine classes.
	for _, ck in ipairs(wt.CLASS_ORDER) do
		local expected = EXPECTED_CLASS_WEAPONS[ck]
		assert_not_nil(expected, "expected weapons missing for " .. ck)
		local allowed, provisional = {}, {}
		local seen = {}
		for _, w in ipairs(wt.WeaponsForClass(ck)) do
			assert_not_nil(wt.WEAPONS[w.key], "unknown weapon " .. tostring(w.key))
			assert_true(w.status == "allowed" or w.status == "provisional")
			assert_false(seen[w.key] == true, "duplicate weapon " .. w.key .. " for " .. ck)
			seen[w.key] = true
			if w.status == "provisional" then provisional[w.key] = true else allowed[w.key] = true end
		end
		assert_true(sameMembers(allowed, expected.allowed), ck .. " allowed weapons must match the reference")
		assert_true(sameMembers(provisional, expected.provisional), ck .. " provisional weapons must match the reference")
	end
	assert_eq(#wt.CLASS_ORDER, 9, "all nine classes present")
	for ck in pairs(EXPECTED_CLASS_WEAPONS) do assert_not_nil(wt.CLASSES[ck], "unexpected class " .. ck) end
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

	-- Independent coords/city/district/weapon-set expectations for all eight.
	for id, exp in pairs(EXPECTED_TRAINERS) do
		local t = wt.Trainer(id)
		assert_not_nil(t, "missing trainer " .. id)
		assert_near(t.x, exp.x, 1e-9, id .. " x")
		assert_near(t.y, exp.y, 1e-9, id .. " y")
		assert_eq(t.city, exp.city, id .. " city")
		assert_eq(t.district, exp.district, id .. " district")
		assert_true(sameMembers(toSet(t.weapons), exp.weapons), id .. " weapon set")
	end
	assert_eq(#wt.AllTrainers(), 8)
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
	-- No developer-facing "what was supplied" note in the Woo Ping detail.
	assert_false(contains(wt.DetailText(wt.Trainer("woo_ping")), "Weller's Arsenal"))
	assert_false(contains(wt.DetailText(wt.Trainer("woo_ping")), "NOT supplied"))
end)

T.register("weapon training: Hunter partial starts and Forever combinations are flagged", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining

	-- Hunter ranged-only partial data.
	local start = wt.Starts("TROLL", "HUNTER")
	assert_true(start.rangedOnly, "hunter starts are partial (ranged only)")
	local entries = wt.BuildEntries("TROLL", "HUNTER")
	assert_not_nil(findEntry(entries, "Partial starting data: ranged only; other starting skills unknown"),
		"explicit partial-data line is shown")
	assert_not_nil(findEntry(entries, "Partial supplied starting skills (ranged only)"))
	-- A non-start weapon in a partial list says status unknown, not "not starting".
	local axe = findEntry(entries, "One-Handed Axe")
	assert_not_nil(axe)
	assert_true(contains(axe.text, "starting status unknown (partial data)"), "partial row qualifier")
	local bow = findEntry(entries, "Bow")
	assert_true(contains(bow.text, "supplied starting"))

	-- Human Hunter (no starting package) is a supplied Forever change.
	assert_true(wt.IsForeverChange("HUMAN", "HUNTER"))
	assert_not_nil(findEntry(wt.BuildEntries("HUMAN", "HUNTER"), "Supplied Forever change: this race/class"))

	-- All six supplied Forever combos are flagged visibly.
	for _, pair in ipairs({
		{ "HUMAN", "HUNTER" }, { "DWARF", "SHAMAN" }, { "GNOME", "PRIEST" },
		{ "ORC", "MAGE" }, { "TROLL", "WARLOCK" }, { "UNDEAD", "PALADIN" },
	}) do
		assert_true(wt.IsForeverChange(pair[1], pair[2]), pair[1] .. "/" .. pair[2] .. " is a Forever change")
		assert_not_nil(findEntry(wt.BuildEntries(pair[1], pair[2]), "Supplied Forever change: this race/class"),
			pair[1] .. "/" .. pair[2] .. " flags Forever")
	end
	-- A classic combination is not flagged.
	assert_false(wt.IsForeverChange("TAUREN", "DRUID"))
	assert_nil(findEntry(wt.BuildEntries("TAUREN", "DRUID"), "Supplied Forever change: this race/class"))
end)

T.register("weapon training: trainer detail geometry is readable and never overlaps", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining
	local f = wt.OpenTrainer("woo_ping")
	assert_not_nil(f)

	local body = Mocks.FrameRect(f.bodyScroll)
	local status = Mocks.FrameRect(f.statusBox)
	local show = Mocks.FrameRect(f.showMapButton)
	local wp = Mocks.FrameRect(f.waypointButton)
	local close = Mocks.FrameRect(f.closeButton)

	-- The body scroll, status area and button row are vertically disjoint.
	assert_true(body.bottom >= status.top, "body must sit above the status area")
	assert_true(status.bottom >= show.top and status.bottom >= wp.top and status.bottom >= close.top,
		"status must sit above the button row")
	assert_false(Mocks.RectsOverlap(body, status), "body/status overlap")
	assert_false(Mocks.RectsOverlap(status, show), "status/button overlap")
	assert_false(Mocks.RectsOverlap(body, show), "body/button overlap")

	-- A long trainer body scrolls rather than overflowing into the status area.
	f.SetDetailBody(string.rep("A long wrapped trainer note line that keeps growing.\n", 40))
	assert_true(f.bodyContent:GetHeight() > f.bodyScroll:GetHeight(),
		"a long body must scroll")
	local wheel = f.bodyScroll:GetScript("OnMouseWheel")
	wheel(f.bodyScroll, -1000)
	assert_eq(f.bodyScroll:GetVerticalScroll(), f.bodyScroll:GetVerticalScrollRange(),
		"mouse wheel clamps to the bottom")
	wheel(f.bodyScroll, 1000)
	assert_eq(f.bodyScroll:GetVerticalScroll(), 0, "mouse wheel clamps to the top")

	-- A long status message is bounded, never overlapping the buttons.
	wt.lastTrainer = wt.Trainer("woo_ping")
	assert_true(#wt.ClampStatus(string.rep("x", 2000)) <= 260)
	C_Map, TomTom = nil, nil
	click(f.waypointButton)
	assert_true(#f.status:GetText() <= 260, "status text must be clamped")
	assert_false(Mocks.RectsOverlap(Mocks.FrameRect(f.statusBox), Mocks.FrameRect(f.showMapButton)))

	-- The waypoint button passes the trainer name as the waypoint title.
	C_Map = { GetMapInfo = function(id) if id == 1453 then return { mapType = 3, mapID = 1453, name = "Stormwind" } end end }
	UiMapPoint = nil
	TomTom = { AddWaypoint = function(_, _, _, _, opts)
		Mocks.tomtomTitle = opts and opts.title
		return { uid = "uid-title" }
	end }
	click(f.waypointButton)
	assert_eq(Mocks.tomtomTitle, "Woo Ping", "editor title is the trainer name")
end)

-----------------------------------------------------------------------------
-- map adapter
-----------------------------------------------------------------------------

T.register("weapon training: coordinates are percent-only and map ids resolve with the numeric Zone enum", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining

	-- Percent-only units: no normalized-vs-percent guessing.
	assert_near(wt.NormalizeCoord(57.1), 0.571, 1e-9)
	assert_near(wt.NormalizeCoord(0.5), 0.005, 1e-9, "0.5 percent")
	assert_near(wt.NormalizeCoord(1), 0.01, 1e-9, "1 percent")
	assert_near(wt.NormalizeCoord(100), 1, 1e-9, "100 percent")
	assert_near(wt.NormalizeCoord(0), 0, 1e-9)
	assert_nil(wt.NormalizeCoord(-1))
	assert_nil(wt.NormalizeCoord(150))
	assert_nil(wt.NormalizeCoord(Mocks.MakeSecret()))
	assert_nil(wt.NormalizeCoord("nope"))

	local cands = wt.MapCandidates("Stormwind")
	assert_eq(#cands, 2)
	assert_eq(cands[1].mapID, 1453)
	assert_eq(cands[2].mapID, 84)
	assert_eq(#wt.MapCandidates(Mocks.MakeSecret()), 0, "secret city key has no candidates")

	-- Classic client exposes only the classic id; the live name is "Stormwind City".
	C_Map = { GetMapInfo = function(id) if id == 1453 then return { mapType = 3, mapID = 1453, name = "Stormwind City" } end end }
	local mapID, source = wt.ResolveMap("Stormwind")
	assert_eq(mapID, 1453)
	assert_eq(source, "classic")

	-- Modern client exposes only the modern id.
	C_Map = { GetMapInfo = function(id) if id == 84 then return { mapType = 3, mapID = 84, name = "Stormwind" } end end }
	mapID, source = wt.ResolveMap("Stormwind")
	assert_eq(mapID, 84)
	assert_eq(source, "modern")

	-- Enum.UIMapType.Zone is honoured when the client exposes it.
	Enum = { UIMapType = { Zone = 3 } }
	C_Map = { GetMapInfo = function(id) if id == 1453 then return { mapType = 3, name = "Stormwind" } end end }
	mapID = wt.ResolveMap("Stormwind")
	assert_eq(mapID, 1453)

	-- Non-numeric / wrong numeric map type fails closed (no "CITY" type exists).
	C_Map = { GetMapInfo = function() return { mapType = "ZONE", name = "Stormwind" } end }
	local bad, _, _, reason = wt.ResolveMap("Stormwind")
	assert_nil(bad)
	assert_true(contains(reason, "not a zone/city"))
	C_Map = { GetMapInfo = function() return { mapType = 2, name = "Stormwind" } end }
	bad, _, _, reason = wt.ResolveMap("Stormwind")
	assert_nil(bad)
	assert_true(contains(reason, "not a zone/city"))

	-- A mismatched returned mapID is refused.
	C_Map = { GetMapInfo = function() return { mapType = 3, mapID = 999, name = "Stormwind" } end }
	bad, _, _, reason = wt.ResolveMap("Stormwind")
	assert_nil(bad)
	assert_true(contains(reason, "mismatched"))

	-- Known localized alias resolves; truly unknown name fails closed.
	C_Map = { GetMapInfo = function() return { mapType = 3, name = "Eisenschmiede" } end }
	assert_eq(wt.ResolveMap("Ironforge"), 1455, "German Ironforge alias resolves")
	C_Map = { GetMapInfo = function() return { mapType = 3, name = "Atlantis" } end }
	bad, _, _, reason = wt.ResolveMap("Stormwind")
	assert_nil(bad)
	assert_true(contains(reason, "localized") or contains(reason, "not a known"))

	-- Restricted map name/mapType never raises, and never resolves.
	C_Map = { GetMapInfo = function() return { mapType = 3, name = Mocks.MakeSecret() } end }
	bad, _, _, reason = wt.ResolveMap("Stormwind")
	assert_nil(bad)
	assert_true(contains(reason, "localized") or contains(reason, "not a known"))
	C_Map = { GetMapInfo = function() return { mapType = Mocks.MakeSecret(), name = "Stormwind" } end }
	bad, _, _, reason = wt.ResolveMap("Stormwind")
	assert_nil(bad)
	assert_true(contains(reason, "restricted"))

	-- Missing API yields a useful reason, never an exception.
	C_Map = nil
	bad, _, _, reason = wt.ResolveMap("Stormwind")
	assert_nil(bad)
	assert_true(contains(reason, "GetMapInfo"))

	-- Unknown city / secret city fail closed.
	bad = wt.ResolveMap("Atlantis")
	assert_nil(bad)
	bad = wt.ResolveMap(Mocks.MakeSecret())
	assert_nil(bad)
end)

T.register("weapon training: native waypoint requires confirmed true; TomTom requires a UID", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining

	-- Native success; coordinates normalized to 0-1 and SuperTrack called.
	C_Map = {
		GetMapInfo = function(id) if id == 1453 then return { mapType = 3, mapID = 1453, name = "Stormwind" } end end,
		SetUserWaypoint = function(point) Mocks.waypoint = point; return true end,
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

	-- SetUserWaypoint nil / false / secret are never success (no TomTom fallback).
	for _, variant in ipairs({
		{ name = "nil", fn = function() end, err = "did not confirm" },
		{ name = "false", fn = function() return false end, err = "did not confirm" },
		{ name = "secret", fn = function() return Mocks.MakeSecret() end, err = "restricted" },
	}) do
		Mocks.waypoint, Mocks.superTracked = nil, nil
		C_Map.SetUserWaypoint = variant.fn
		TomTom = nil
		ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7)
		assert_false(ok, "SetUserWaypoint " .. variant.name .. " must not report success")
		assert_eq(method, "unsupported")
		assert_true(contains(wt.lastWaypoint.nativeError, variant.err), variant.name .. " reason")
		assert_nil(Mocks.waypoint)
	end

	-- TomTom returning nil / false / secret is never success.
	for _, variant in ipairs({
		{ name = "nil", fn = function() return nil end, err = "UID" },
		{ name = "false", fn = function() return false end, err = "UID" },
		{ name = "secret", fn = function() return Mocks.MakeSecret() end, err = "restricted" },
	}) do
		C_Map.SetUserWaypoint = function() return false end
		TomTom = { AddWaypoint = variant.fn }
		ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7)
		assert_false(ok, "TomTom " .. variant.name .. " must not report success")
		assert_eq(method, "unsupported")
		assert_true(contains(wt.lastWaypoint.tomtomError, variant.err), variant.name .. " tomtom reason")
	end

	-- Native false falls back to TomTom, which must return a UID. The trainer
	-- name is used as the waypoint title.
	local tomtomCalls = 0
	C_Map.SetUserWaypoint = function() return false end
	TomTom = { AddWaypoint = function(_, id, x, y, opts)
		tomtomCalls = tomtomCalls + 1
		Mocks.tomtomTitle = opts and opts.title
		Mocks.waypoint = { uiMapID = id, x = x, y = y }
		return { uid = "uid-1" }
	end }
	ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7, { title = "Woo Ping" })
	assert_true(ok)
	assert_eq(method, "tomtom")
	assert_eq(tomtomCalls, 1)
	assert_eq(Mocks.tomtomTitle, "Woo Ping", "trainer name is the waypoint title")
	assert_true(contains(wt.lastWaypoint.nativeError, "did not confirm"))

	-- Native error + TomTom error: honest failure, no success claim.
	C_Map.SetUserWaypoint = function() error("boom") end
	TomTom.AddWaypoint = function() error("tomtom boom") end
	Mocks.waypoint = nil
	ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_false(ok)
	assert_eq(method, "unsupported")
	assert_not_nil(wt.lastWaypoint.nativeError)
	assert_not_nil(wt.lastWaypoint.tomtomError)
	assert_nil(Mocks.waypoint)

	-- Restricted error objects are never read/coerced: no raise, honest failure.
	C_Map.SetUserWaypoint = function() error(Mocks.MakeSecret()) end
	TomTom.AddWaypoint = function() error(Mocks.MakeSecret()) end
	ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_false(ok)
	assert_eq(method, "unsupported")
	assert_eq(type(wt.lastWaypoint.nativeError), "string", "restricted native error stays uncoerced")
	assert_eq(type(wt.lastWaypoint.tomtomError), "string", "restricted TomTom error stays uncoerced")
	assert_nil(Mocks.waypoint)

	-- CanSetUserWaypointOnMap refusal skips native and falls back to TomTom.
	C_Map.CanSetUserWaypointOnMap = function() return false end
	C_Map.SetUserWaypoint = function() Mocks.waypoint = "native-should-not-run"; return true end
	TomTom = { AddWaypoint = function() return { uid = "uid-can" } end }
	ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_true(ok)
	assert_eq(method, "tomtom")
	assert_true(contains(wt.lastWaypoint.nativeError, "CanSetUserWaypointOnMap"))
	C_Map.CanSetUserWaypointOnMap = nil

	-- Restricted / explicit-false UiMapPoint is refused and never passed on.
	C_Map.SetUserWaypoint = function() return true end
	TomTom = nil
	UiMapPoint = { CreateFromCoordinates = function() return Mocks.MakeSecret() end }
	Mocks.waypoint = nil
	ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_false(ok)
	assert_eq(method, "unsupported")
	assert_nil(Mocks.waypoint)
	assert_true(contains(wt.lastWaypoint.nativeError, "restricted"))
	UiMapPoint = { CreateFromCoordinates = function() return false end }
	ok = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_false(ok)

	-- Missing APIs: useful coordinates in the message, not an exception.
	C_Map, UiMapPoint = nil, nil
	ok, method, msg = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_false(ok)
	assert_eq(method, "unresolved")
	assert_true(contains(msg, "57.1"))
	assert_true(contains(msg, "no waypoint placed"))

	-- Out-of-range / secret coordinates are refused before any API call.
	ok, method = wt.SetWaypoint("Stormwind", 999, 57.7)
	assert_false(ok)
	assert_eq(method, "invalid")
	ok, method = wt.SetWaypoint("Stormwind", Mocks.MakeSecret(), 57.7)
	assert_false(ok)
	assert_eq(method, "invalid")

	-- No raw secret input is retained in WT.lastWaypoint.
	wt.SetWaypoint(Mocks.MakeSecret(), 57.1, 57.7)
	assert_nil(wt.lastWaypoint.city, "secret city must not be retained")
	assert_near(wt.lastWaypoint.x, 57.1, 1e-9)
	wt.SetWaypoint("Stormwind", Mocks.MakeSecret(), Mocks.MakeSecret())
	assert_nil(wt.lastWaypoint.x, "secret coordinates must not be retained")
	assert_nil(wt.lastWaypoint.y)
end)

T.register("weapon training: combat refusal and Show map use the global OpenWorldMap", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining
	C_Map = {
		GetMapInfo = function(id) if id == 1453 then return { mapType = 3, mapID = 1453, name = "Stormwind" } end end,
		SetUserWaypoint = function(p) Mocks.waypoint = p; return true end,
	}
	UiMapPoint = { CreateFromCoordinates = function(id, x, y) return { uiMapID = id, x = x, y = y } end }

	-- Waypoint succeeds out of combat.
	local ok, method = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_true(ok)
	assert_eq(method, "native")

	-- Combat refuses and leaves the map/waypoint untouched.
	Mocks.inCombat = true
	Mocks.waypoint, Mocks.openedMap = nil, nil
	OpenWorldMap = function(id) Mocks.openedMap = id end
	ok, method, msg = wt.SetWaypoint("Stormwind", 57.1, 57.7)
	assert_false(ok)
	assert_eq(method, "combat")
	assert_true(contains(msg, "Combat"))
	assert_nil(Mocks.waypoint)
	ok, method = wt.ShowMap("Stormwind")
	assert_false(ok)
	assert_eq(method, "combat")
	assert_nil(Mocks.openedMap)
	Mocks.inCombat = false

	-- Show map works out of combat through the GLOBAL OpenWorldMap.
	ok, method, msg = wt.ShowMap("Stormwind")
	assert_true(ok)
	assert_eq(method, "native")
	assert_eq(Mocks.openedMap, 1453)

	-- OpenWorldMap false / error / secret never reports success.
	for _, variant in ipairs({
		{ name = "false", fn = function() return false end },
		{ name = "error", fn = function() error("no map") end },
		{ name = "secret", fn = function() return Mocks.MakeSecret() end },
	}) do
		OpenWorldMap = variant.fn
		ok, method, msg = wt.ShowMap("Stormwind")
		assert_false(ok, "OpenWorldMap " .. variant.name .. " must not report success")
		assert_eq(method, "unsupported")
		assert_true(contains(msg, "1453"))
	end

	-- A visible mismatch fails closed rather than claiming the wrong map.
	OpenWorldMap = function() end
	WorldMapFrame = { GetMapID = function() return 999 end }
	ok = wt.ShowMap("Stormwind")
	assert_false(ok, "wrong visible map id must fail closed")

	-- A game-rule disabled no-op (map not actually shown) is not called opened.
	WorldMapFrame = { IsShown = function() return false end }
	ok = wt.ShowMap("Stormwind")
	assert_false(ok, "an OpenWorldMap no-op must not report success")

	-- A real visible-map path: shown and the requested map id verified.
	WorldMapFrame = {
		IsShown = function() return true end,
		GetMapID = function() return 1453 end,
	}
	ok, method = wt.ShowMap("Stormwind")
	assert_true(ok, "visible correct map must succeed")
	assert_eq(method, "native")
	WorldMapFrame = nil

	-- Fallback shows the WorldMapFrame without toggling an already-open map.
	OpenWorldMap = nil
	local shownCalls, setMap = 0, nil
	WorldMapFrame = {
		IsShown = function() return true end,
		Show = function() shownCalls = shownCalls + 1 end,
		SetMapID = function(_, id) setMap = id end,
		GetMapID = function() return setMap end,
	}
	ok, method = wt.ShowMap("Stormwind")
	assert_true(ok)
	assert_eq(method, "native")
	assert_eq(setMap, 1453)
	assert_eq(shownCalls, 0, "an already-open map must not be toggled")
	-- A hidden frame is shown FIRST; a real OnShow resets the map to the
	-- player's current map, so SetMapID must run after Show to survive it.
	local state = { shown = false, id = 999 }
	WorldMapFrame = {
		IsShown = function(self) return state.shown end,
		Show = function(self) state.shown = true; state.id = 999 end, -- OnShow reset
		SetMapID = function(self, id) state.id = id end,
		GetMapID = function(self) return state.id end,
	}
	ok, method = wt.ShowMap("Stormwind")
	assert_true(ok)
	assert_eq(method, "native")
	assert_true(state.shown, "hidden frame is shown")
	assert_eq(state.id, 1453, "SetMapID after Show must override the OnShow reset")

	-- An incomplete frame lacking SetMapID cannot be used: fail closed.
	WorldMapFrame = {
		IsShown = function() return true end,
		Show = function() end,
	}
	ok, method = wt.ShowMap("Stormwind")
	assert_false(ok, "a frame lacking SetMapID must not report success")
	assert_eq(method, "unsupported")

	-- A frame whose SetMapID does not take (wrong visible map) fails closed.
	WorldMapFrame = {
		IsShown = function() return true end,
		Show = function() end,
		SetMapID = function() end,
		GetMapID = function() return 42 end,
	}
	ok = wt.ShowMap("Stormwind")
	assert_false(ok, "a frame returning the wrong map must fail closed")

	-- A frame whose IsShown errors fails closed instead of raising.
	WorldMapFrame = {
		IsShown = function() error("nope") end,
		Show = function() end,
		SetMapID = function() end,
	}
	ok = wt.ShowMap("Stormwind")
	assert_false(ok, "an erroring IsShown must fail closed")
	WorldMapFrame = nil

	-- Last resort: load Blizzard_WorldMap through the documented loader, retry.
	OpenWorldMap, Mocks.openedMap = nil, nil
	C_AddOns = { LoadAddOn = function(name)
		assert_eq(name, "Blizzard_WorldMap")
		OpenWorldMap = function(id) Mocks.openedMap = id end
	end }
	ok, method = wt.ShowMap("Stormwind")
	assert_true(ok)
	assert_eq(Mocks.openedMap, 1453)
	C_AddOns = nil

	-- A restricted combat return counts as locked, and the addon fallback is used
	-- when the client global is missing.
	InCombatLockdown = nil
	e.ns.inCombat = true
	ok, method = wt.ShowMap("Stormwind")
	assert_false(ok)
	assert_eq(method, "combat")
	e.ns.inCombat = false
	InCombatLockdown = function() return Mocks.MakeSecret() end
	ok, method = wt.ShowMap("Stormwind")
	assert_false(ok)
	assert_eq(method, "combat")

	-- Resolvable map but no opening API: useful failure, not an exception.
	InCombatLockdown = function() return false end
	OpenWorldMap, WorldMapFrame, C_AddOns = nil, nil, nil
	ok, method, msg = wt.ShowMap("Stormwind")
	assert_false(ok)
	assert_eq(method, "unsupported")
	assert_true(contains(msg, "1453"))
end)

T.register("weapon training: ShowMap frame fallback is verified and fails closed", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining
	C_Map = {
		GetMapInfo = function(id) if id == 1453 then return { mapType = 3, mapID = 1453, name = "Stormwind" } end end,
	}

	-- A hidden frame whose OnShow resets the map: SetMapID must run after Show.
	local state = { shown = false, id = 999 }
	WorldMapFrame = {
		IsShown = function() return state.shown end,
		Show = function() state.shown = true; state.id = 999 end,
		SetMapID = function(_, id) state.id = id end,
		GetMapID = function() return state.id end,
	}
	local ok, method = wt.ShowMap("Stormwind")
	assert_true(ok)
	assert_eq(method, "native")
	assert_true(state.shown)
	assert_eq(state.id, 1453, "SetMapID after Show overrides the OnShow reset")

	-- An incomplete frame lacking SetMapID must fail closed.
	WorldMapFrame = { IsShown = function() return true end, Show = function() end }
	ok, method = wt.ShowMap("Stormwind")
	assert_false(ok)
	assert_eq(method, "unsupported")

	-- A frame that returns the wrong map after SetMapID fails closed.
	WorldMapFrame = {
		IsShown = function() return true end,
		Show = function() end,
		SetMapID = function() end,
		GetMapID = function() return 7 end,
	}
	assert_false(wt.ShowMap("Stormwind"), "wrong returned map must fail closed")

	-- Global OpenWorldMap no-op (not actually shown) is not called opened.
	OpenWorldMap = function() end
	WorldMapFrame = { IsShown = function() return false end }
	assert_false(wt.ShowMap("Stormwind"), "a no-op open must fail closed")

	-- Global OpenWorldMap with a verified visible map is a real success.
	WorldMapFrame = { IsShown = function() return true end, GetMapID = function() return 1453 end }
	ok, method = wt.ShowMap("Stormwind")
	assert_true(ok)
	assert_eq(method, "native")

	-- An explicit false global return fails closed without claiming success.
	OpenWorldMap = function() return false end
	WorldMapFrame = nil
	ok, method = wt.ShowMap("Stormwind")
	assert_false(ok)
	assert_eq(method, "unsupported")
end)

-----------------------------------------------------------------------------
-- branding, aliases, legacy settings
-----------------------------------------------------------------------------

T.register("weapon training: frame setters and unreadable postconditions cannot claim success", function()
	local e = Mocks.NewEnv()
	local wt = e.ns.weaponTraining
	C_Map = { GetMapInfo = function(id)
		if id == 1453 then return { mapType = 3, mapID = id, name = "Stormwind City" } end
	end }
	for _, result in ipairs({ false, Mocks.MakeSecret() }) do
		WorldMapFrame = {
			IsShown = function() return true end, Show = function() end,
			SetMapID = function() return result end, GetMapID = function() return 1453 end,
		}
		assert_false(wt.ShowMap("Stormwind"), "rejected setter cannot report an opened map")
		WorldMapFrame.IsShown = function() return false end
		WorldMapFrame.Show = function() return result end
		WorldMapFrame.SetMapID = function() error("must not set after refused show") end
		assert_false(wt.ShowMap("Stormwind"), "rejected Show cannot report success")
	end
	WorldMapFrame = {
		IsShown = function() return true end, Show = function() end,
		SetMapID = function() end, GetMapID = function() return nil end,
	}
	assert_false(wt.ShowMap("Stormwind"), "nil map query is not confirmation")
	OpenWorldMap = function() end
	assert_false(wt.ShowMap("Stormwind"), "global path also refuses unreadable map query")
end)

T.register("weapon training: DoHelper branding, aliases and legacy settings compatibility", function()
	local e = Mocks.NewEnv()
	assert_eq(e.ns.version, "0.10.0")
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

	-- Public Blizzard category identifier is now DoHelper (test assertion updated).
	local captured
	Settings = {
		RegisterCanvasLayoutCategory = function(panel, name) captured = name; return { panel = panel } end,
		RegisterAddOnCategory = function() end,
	}
	e.ns.InitOptions()
	assert_eq(captured, "DoHelper")
	Settings = nil

	-- TOC keeps the historical SavedVariables name and ships the new module.
	local toc = ReadFile((_G.__HOT_ROOT or ".") .. "/DoHelper/DoHelper.toc")
	assert_true(contains(toc, "## Title: DoHelper"))
	assert_true(not contains(toc, "HoTPrediction:") and not contains(toc, "HoT Prediction"), "TOC title is simply DoHelper")
	assert_true(contains(toc, "Version: 0.10.0"))
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
		assert_eq(panel.name, "DoHelper")
	end
	e.ns.InitOptions()
	e.ns.InitOptions()
	assert_eq(added, 1, "legacy Interface Options category registers exactly once")
	InterfaceOptions_AddCategory = nil

	-- SavedVariables keep their historical name; a pre-topics `text` is migrated
	-- into the first topic and survives a reload merge.
	EllesmereUI_HoTPredictionDB = { notes = { text = "legacy note" }, alpha = 0.42, enabled = true }
	e.ns.InitDatabase()
	assert_eq(e.ns.db.alpha, 0.42)
	assert_eq(e.ns.notes.SiteText(e.ns.notes.ActiveId()), "legacy note")
	assert_eq(e.ns.notes.ActiveSite().title, "General")
	assert_true(EllesmereUI_HoTPredictionDB.notes.sites ~= nil, "the text is migrated into a topic")

	-- Re-merging the same SavedVariables (a reload) preserves the migrated value.
	e.ns.InitDatabase()
	assert_eq(e.ns.notes.SiteText(e.ns.notes.ActiveId()), "legacy note")
	assert_eq(e.ns.db.alpha, 0.42)
end)
