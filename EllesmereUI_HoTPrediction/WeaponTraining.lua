-- EllesmereUI_HoTPrediction / WeaponTraining.lua
-- DoHelper weapon training reference.
--
-- This module is deliberately split in three:
--   1. A STATIC, TYPED REFERENCE (races, classes, starts, trainers, map ids).
--      Every value comes from the user-supplied WoW Forever reference and is
--      labelled with its confidence. Nothing here is independently verified.
--   2. A MAP ADAPTER that resolves candidate map ids through C_Map.GetMapInfo
--      and places a waypoint through native and/or optional TomTom APIs. Every
--      external call is pcall-guarded, fails closed in combat, and never claims
--      success on an explicit false/error/secret value. When the map cannot be
--      resolved no waypoint is placed (no fabricated legacy area id).
--   3. A LAZY UI BUILDER called from Options.lua, plus one reusable trainer
--      detail panel. No timers, events or polling of any kind.
--
-- The file must load and be testable under a plain Lua interpreter with mocked
-- globals: nothing at load time touches the live client.

local addonName, ns = ...

local WT = {}
ns.weaponTraining = WT

local unpack = unpack or table.unpack -- luacheck: ignore

-----------------------------------------------------------------------------
-- shared confidence labels / provenance
-----------------------------------------------------------------------------

WT.SOURCE_NOTE = "User-supplied WoW Forever reference; not live verified"
WT.CONF = {
	CLASSIC = "Classic-established reference",
	FOREVER = "Supplied Forever change",
	PROVISIONAL = "Forever beta / provisional",
	CHECK = "Supplied typical / verify client",
	UNCONFIRMED = "Unconfirmed - client verification required",
}

-----------------------------------------------------------------------------
-- static reference: weapons
-----------------------------------------------------------------------------

-- Compact weapon keys with full human-readable labels for the UI.
WT.WEAPONS = {
	AXE1 = { label = "One-Handed Axe", minLevel = 1, cost = "~10s" },
	AXE2 = { label = "Two-Handed Axe", minLevel = 1, cost = "~10s" },
	SWORD1 = { label = "One-Handed Sword", minLevel = 1, cost = "~10s" },
	SWORD2 = { label = "Two-Handed Sword", minLevel = 1, cost = "~10s" },
	MACE1 = { label = "One-Handed Mace", minLevel = 1, cost = "~10s" },
	MACE2 = { label = "Two-Handed Mace", minLevel = 1, cost = "~10s" },
	DAGGER = { label = "Dagger", minLevel = 1, cost = "~10s" },
	FIST = { label = "Fist Weapon", minLevel = 1, cost = "~10s" },
	STAFF = { label = "Staff", minLevel = 1, cost = "~10s" },
	POLEARM = { label = "Polearm", minLevel = 20, cost = "~1g" },
	BOW = { label = "Bow", minLevel = 1, cost = "~10s" },
	CROSSBOW = { label = "Crossbow", minLevel = 1, cost = "~10s" },
	GUN = { label = "Gun", minLevel = 1, cost = "~10s" },
	THROWN = { label = "Thrown", minLevel = 1, cost = "~10s" },
	WAND = { label = "Wand", minLevel = 1, cost = "default caster proficiency", noTrainer = true },
}
WT.WEAPON_ORDER = {
	"AXE1", "AXE2", "SWORD1", "SWORD2", "MACE1", "MACE2", "DAGGER", "FIST",
	"STAFF", "POLEARM", "BOW", "CROSSBOW", "GUN", "THROWN", "WAND",
}

-----------------------------------------------------------------------------
-- static reference: races (order = UI cycling order; all 10 accessible)
-----------------------------------------------------------------------------

WT.RACES = {
	{ key = "HUMAN", name = "Human", faction = "Alliance", startZone = "Elwynn Forest",
		capital = "Stormwind", cityKey = "Stormwind",
		classes = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "MAGE", "WARLOCK" } },
	{ key = "DWARF", name = "Dwarf", faction = "Alliance", startZone = "Dun Morogh",
		capital = "Ironforge", cityKey = "Ironforge",
		classes = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN" } },
	{ key = "NIGHTELF", name = "Night Elf", faction = "Alliance", startZone = "Teldrassil",
		capital = "Darnassus", cityKey = "Darnassus",
		classes = { "WARRIOR", "HUNTER", "ROGUE", "PRIEST", "DRUID" } },
	{ key = "GNOME", name = "Gnome", faction = "Alliance", startZone = "Dun Morogh",
		capital = "Ironforge", cityKey = "Ironforge",
		classes = { "WARRIOR", "ROGUE", "PRIEST", "MAGE", "WARLOCK" } },
	{ key = "ORC", name = "Orc", faction = "Horde", startZone = "Durotar",
		capital = "Orgrimmar", cityKey = "Orgrimmar",
		classes = { "WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "MAGE", "WARLOCK" } },
	{ key = "UNDEAD", name = "Undead", faction = "Horde", startZone = "Tirisfal Glades",
		capital = "Undercity", cityKey = "Undercity",
		classes = { "WARRIOR", "PALADIN", "ROGUE", "PRIEST", "MAGE", "WARLOCK" } },
	{ key = "TAUREN", name = "Tauren", faction = "Horde", startZone = "Mulgore",
		capital = "Thunder Bluff", cityKey = "Thunder Bluff",
		classes = { "WARRIOR", "HUNTER", "SHAMAN", "DRUID" } },
	{ key = "TROLL", name = "Troll", faction = "Horde", startZone = "Durotar",
		capital = "Orgrimmar", cityKey = "Orgrimmar",
		classes = { "WARRIOR", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK" } },
	{ key = "SKYBORNE_HIGH", name = "Skyborne - High Order", faction = nil, startZone = nil,
		capital = nil, cityKey = nil,
		classes = { "WARRIOR", "HUNTER", "ROGUE", "MAGE", "DRUID" } },
	{ key = "SKYBORNE_WIND", name = "Skyborne - Windshaper", faction = nil, startZone = nil,
		capital = nil, cityKey = nil,
		classes = { "WARRIOR", "HUNTER", "ROGUE", "SHAMAN", "DRUID" } },
}
WT.RACE_ORDER = {}
WT.RACES_BY_KEY = {}
for _, r in ipairs(WT.RACES) do
	WT.RACE_ORDER[#WT.RACE_ORDER + 1] = r.key
	WT.RACES_BY_KEY[r.key] = r
end

-----------------------------------------------------------------------------
-- static reference: classes (eligibility + provisional + notes)
-----------------------------------------------------------------------------

WT.CLASSES = {
	WARRIOR = {
		name = "Warrior",
		allowed = { "AXE1", "AXE2", "SWORD1", "SWORD2", "MACE1", "MACE2", "DAGGER",
			"FIST", "STAFF", "POLEARM", "BOW", "CROSSBOW", "GUN", "THROWN" },
		provisional = {},
		notes = {
			{ text = "Polearms require level 20; everything else is level 1.", conf = "CLASSIC" },
			{ text = "Dual Wield is learned from the CLASS trainer at level 20, not a weapon master.", conf = "CLASSIC" },
			{ text = "Warriors never use wands.", conf = "CLASSIC" },
		},
	},
	PALADIN = {
		name = "Paladin",
		allowed = { "AXE1", "AXE2", "SWORD1", "SWORD2", "MACE1", "MACE2", "POLEARM" },
		provisional = {},
		notes = {
			{ text = "Undead paladin is a supplied Forever addition; the starting package retains the supplied / check-client qualifier.", conf = "FOREVER" },
		},
	},
	HUNTER = {
		name = "Hunter",
		allowed = { "AXE1", "AXE2", "SWORD1", "SWORD2", "DAGGER", "FIST", "STAFF",
			"POLEARM", "BOW", "CROSSBOW", "GUN", "THROWN" },
		provisional = {},
		notes = {
			{ text = "No maces and no wands for hunters.", conf = "CLASSIC" },
			{ text = "Ranged starts are only partially supplied: Night Elf/Troll bow, Dwarf/Orc/Tauren gun. Human/Skyborne starts are unconfirmed; no melee starts are invented.", conf = "CHECK" },
			{ text = "Forever: Dual Wield is available without the old Survival talent dependency; no unsupported level claim is made.", conf = "FOREVER" },
		},
	},
	ROGUE = {
		name = "Rogue",
		allowed = { "DAGGER", "THROWN", "SWORD1", "AXE1", "MACE1", "FIST", "BOW", "CROSSBOW", "GUN" },
		provisional = {},
		notes = {
			{ text = "Forever change: rogues can train one-handed axes (not in Vanilla).", conf = "FOREVER" },
			{ text = "Dual Wield is learned from the class trainer at level 10, not a weapon master.", conf = "CLASSIC" },
			{ text = "Typical starts are Dagger + Thrown; some configurations additionally start with one-handed Sword. Exact starts are client-verify.", conf = "CHECK" },
		},
	},
	PRIEST = {
		name = "Priest",
		allowed = { "MACE1", "DAGGER", "STAFF", "WAND" },
		provisional = {},
		notes = {
			{ text = "Wands are a default caster proficiency; no trainer teaches them.", conf = "CLASSIC" },
			{ text = "The new Gnome priest start package must be checked in the client.", conf = "CHECK" },
		},
	},
	SHAMAN = {
		name = "Shaman",
		allowed = { "MACE1", "MACE2", "AXE1", "AXE2", "DAGGER", "FIST", "STAFF" },
		provisional = {},
		notes = {
			{ text = "Forever change: two-handed axes and two-handed maces are normally trainable with no Enhancement talent requirement.", conf = "FOREVER" },
			{ text = "Dwarf shaman (new) and Skyborne starts must be checked in the client; Skyborne is unconfirmed.", conf = "CHECK" },
		},
	},
	MAGE = {
		name = "Mage",
		allowed = { "STAFF", "WAND", "DAGGER", "SWORD1" },
		provisional = {},
		notes = {
			{ text = "Wands are a default caster proficiency; no trainer teaches them.", conf = "CLASSIC" },
			{ text = "The new Orc mage start package must be checked in the client; Skyborne is unconfirmed.", conf = "CHECK" },
		},
	},
	WARLOCK = {
		name = "Warlock",
		allowed = { "DAGGER", "WAND", "STAFF", "SWORD1" },
		provisional = {},
		notes = {
			{ text = "Wands are a default caster proficiency; no trainer teaches them.", conf = "CLASSIC" },
			{ text = "The new Troll warlock start package must be checked in the client.", conf = "CHECK" },
		},
	},
	DRUID = {
		name = "Druid",
		allowed = { "MACE1", "MACE2", "STAFF", "DAGGER", "FIST" },
		provisional = { "POLEARM" },
		notes = {
			{ text = "Polearms are a Forever beta / provisional possibility at level 20 and were never confirmed trainable for druids.", conf = "PROVISIONAL" },
			{ text = "Night Elf may additionally start with a Dagger; the ambiguity is kept and no definitive claim is made.", conf = "CHECK" },
			{ text = "Druids do not use axes, swords, ranged weapons or wands.", conf = "CLASSIC" },
		},
	},
}
-- canonical class order (all 9 classes)
WT.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

-----------------------------------------------------------------------------
-- static reference: starting packages (confidence labelled)
-----------------------------------------------------------------------------

WT.STARTS = {
	WARRIOR = {
		HUMAN = { weapons = { "AXE1", "MACE1", "SWORD1" }, conf = "CLASSIC" },
		DWARF = { weapons = { "AXE1", "AXE2", "MACE1" }, conf = "CLASSIC" },
		NIGHTELF = { weapons = { "DAGGER", "MACE1", "SWORD1" }, conf = "CLASSIC" },
		GNOME = { weapons = { "DAGGER", "MACE1", "SWORD1" }, conf = "CLASSIC" },
		ORC = { weapons = { "AXE1", "AXE2", "SWORD1" }, conf = "CLASSIC" },
		UNDEAD = { weapons = { "AXE1", "SWORD1", "SWORD2" }, conf = "CLASSIC" },
		TAUREN = { weapons = { "AXE1", "MACE1", "MACE2" }, conf = "CLASSIC" },
		TROLL = { weapons = { "AXE1", "DAGGER", "THROWN" }, conf = "CLASSIC" },
		SKYBORNE_HIGH = { weapons = {}, conf = "UNCONFIRMED" },
		SKYBORNE_WIND = { weapons = {}, conf = "UNCONFIRMED" },
	},
	PALADIN = {
		HUMAN = { weapons = { "MACE1", "MACE2", "SWORD1", "SWORD2" }, conf = "CLASSIC" },
		DWARF = { weapons = { "MACE1", "MACE2" }, conf = "CLASSIC" },
		UNDEAD = { weapons = { "MACE1", "MACE2" }, conf = "CHECK",
			note = "New Forever combination; the starting package is retained from the supplied reference and should be checked in the client." },
	},
	HUNTER = {
		NIGHTELF = { weapons = { "BOW" }, conf = "CHECK", rangedOnly = true },
		TROLL = { weapons = { "BOW" }, conf = "CHECK", rangedOnly = true },
		DWARF = { weapons = { "GUN" }, conf = "CHECK", rangedOnly = true },
		ORC = { weapons = { "GUN" }, conf = "CHECK", rangedOnly = true },
		TAUREN = { weapons = { "GUN" }, conf = "CHECK", rangedOnly = true },
		HUMAN = { weapons = {}, conf = "UNCONFIRMED",
			note = "Human hunter starts are unconfirmed in the supplied reference." },
		SKYBORNE_HIGH = { weapons = {}, conf = "UNCONFIRMED",
			note = "Skyborne starts are unconfirmed." },
		SKYBORNE_WIND = { weapons = {}, conf = "UNCONFIRMED",
			note = "Skyborne starts are unconfirmed." },
	},
	ROGUE = {
		HUMAN = { weapons = { "DAGGER", "THROWN", "SWORD1" }, conf = "CHECK",
			note = "Some configurations additionally start with one-handed Sword; exact starts are client-verify." },
		DWARF = { weapons = { "DAGGER", "THROWN" }, conf = "CHECK" },
		NIGHTELF = { weapons = { "DAGGER", "THROWN", "SWORD1" }, conf = "CHECK" },
		GNOME = { weapons = { "DAGGER", "THROWN", "SWORD1" }, conf = "CHECK" },
		ORC = { weapons = { "DAGGER", "THROWN" }, conf = "CHECK" },
		UNDEAD = { weapons = { "DAGGER", "THROWN", "SWORD1" }, conf = "CHECK" },
		TROLL = { weapons = { "DAGGER", "THROWN" }, conf = "CHECK" },
		SKYBORNE_HIGH = { weapons = {}, conf = "UNCONFIRMED",
			note = "Skyborne exact starts are unconfirmed." },
		SKYBORNE_WIND = { weapons = {}, conf = "UNCONFIRMED",
			note = "Skyborne exact starts are unconfirmed." },
	},
	PRIEST = {
		_default = { weapons = { "MACE1", "WAND" }, conf = "CLASSIC" },
		GNOME = { weapons = { "MACE1", "WAND" }, conf = "CHECK",
			note = "The new Gnome priest start package must be checked in the client." },
	},
	SHAMAN = {
		DWARF = { weapons = { "MACE1", "STAFF" }, conf = "CHECK",
			note = "New Dwarf shaman start; check in the client." },
		ORC = { weapons = { "MACE1", "STAFF" }, conf = "CLASSIC" },
		TAUREN = { weapons = { "MACE1", "STAFF" }, conf = "CLASSIC" },
		TROLL = { weapons = { "MACE1", "STAFF" }, conf = "CLASSIC" },
		SKYBORNE_WIND = { weapons = {}, conf = "UNCONFIRMED",
			note = "Skyborne exact starts are unconfirmed." },
	},
	MAGE = {
		_default = { weapons = { "STAFF", "WAND" }, conf = "CLASSIC" },
		ORC = { weapons = { "STAFF", "WAND" }, conf = "CHECK",
			note = "The new Orc mage start package must be checked in the client." },
		SKYBORNE_HIGH = { weapons = {}, conf = "UNCONFIRMED",
			note = "Skyborne starts are unconfirmed." },
	},
	WARLOCK = {
		_default = { weapons = { "DAGGER", "WAND" }, conf = "CLASSIC" },
		TROLL = { weapons = { "DAGGER", "WAND" }, conf = "CHECK",
			note = "The new Troll warlock start package must be checked in the client." },
	},
	DRUID = {
		NIGHTELF = { weapons = { "MACE1", "STAFF" }, conf = "CLASSIC",
			note = "Night Elf may additionally start with a Dagger; the ambiguity is kept." },
		TAUREN = { weapons = { "MACE1", "STAFF" }, conf = "CLASSIC" },
		SKYBORNE_HIGH = { weapons = {}, conf = "UNCONFIRMED",
			note = "Skyborne starts are unconfirmed." },
		SKYBORNE_WIND = { weapons = {}, conf = "UNCONFIRMED",
			note = "Skyborne starts are unconfirmed." },
	},
}

-----------------------------------------------------------------------------
-- static reference: trainers (8 supplied; locations approximate)
-----------------------------------------------------------------------------

WT.TRAINERS = {
	{ id = "woo_ping", name = "Woo Ping", faction = "Alliance", city = "Stormwind",
		cityKey = "Stormwind", district = "Trade District", x = 57.1, y = 57.7,
		weapons = { "CROSSBOW", "DAGGER", "SWORD1", "SWORD2", "STAFF", "POLEARM" },
		conf = "CLASSIC", locationApprox = true,
		note = "Weller's Arsenal is a classic-established location but was NOT supplied; district kept as Trade District." },
	{ id = "buliwyf", name = "Buliwyf Stonehand", faction = "Alliance", city = "Ironforge",
		cityKey = "Ironforge", district = "Military Ward", x = 62.2, y = 89.6,
		weapons = { "FIST", "GUN", "AXE1", "AXE2", "MACE1", "MACE2" },
		conf = "CLASSIC", locationApprox = true },
	{ id = "bixi", name = "Bixi Wobblebonk", faction = "Alliance", city = "Ironforge",
		cityKey = "Ironforge", district = "Military Ward", x = 62.2, y = 89.6,
		weapons = { "CROSSBOW", "DAGGER", "THROWN" },
		conf = "CLASSIC", locationApprox = true },
	{ id = "ilyenia", name = "Ilyenia Moonfire", faction = "Alliance", city = "Darnassus",
		cityKey = "Darnassus", district = "Warrior's Terrace", x = 57.6, y = 46.7,
		weapons = { "BOW", "DAGGER", "FIST", "STAFF", "THROWN" },
		conf = "CLASSIC", locationApprox = true },
	{ id = "sayoc", name = "Sayoc", faction = "Horde", city = "Orgrimmar",
		cityKey = "Orgrimmar", district = "Valley of Honor", x = 81.5, y = 19.6,
		weapons = { "BOW", "DAGGER", "FIST", "AXE1", "AXE2", "STAFF", "THROWN" },
		conf = "CLASSIC", locationApprox = true },
	{ id = "hanashi", name = "Hanashi", faction = "Horde", city = "Orgrimmar",
		cityKey = "Orgrimmar", district = "Valley of Honor", x = 81.5, y = 19.6,
		weapons = { "BOW", "AXE1", "AXE2", "STAFF", "THROWN" },
		conf = "CLASSIC", locationApprox = true },
	{ id = "ansekhwa", name = "Ansekhwa", faction = "Horde", city = "Thunder Bluff",
		cityKey = "Thunder Bluff", district = "Lower Rise", x = 40.9, y = 62.7,
		weapons = { "GUN", "MACE1", "MACE2", "STAFF" },
		conf = "CLASSIC", locationApprox = true },
	{ id = "archibald", name = "Archibald", faction = "Horde", city = "Undercity",
		cityKey = "Undercity", district = "War Quarter", x = 57.3, y = 32.8,
		weapons = { "CROSSBOW", "DAGGER", "SWORD1", "SWORD2", "POLEARM" },
		conf = "CLASSIC", locationApprox = true },
}
WT.TRAINERS_BY_ID = {}
for _, t in ipairs(WT.TRAINERS) do WT.TRAINERS_BY_ID[t.id] = t end

-----------------------------------------------------------------------------
-- static reference: general reminders
-----------------------------------------------------------------------------

WT.GENERAL_NOTES = {
	"Learn the eligible proficiency from a weapon master, equip the weapon, then raise the actual weapon skill in combat.",
	"Low weapon skill means misses, dodges and parries until the skill catches up.",
	"Class eligibility is independent of the race's starting package.",
	"Do not assume Vanilla +5 racial weapon skill bonuses in Forever; racials were redesigned.",
	"Distinctions: Classic-established reference / Supplied Forever change / Forever beta provisional. All are user-supplied, not independently confirmed.",
}

-----------------------------------------------------------------------------
-- static reference: map ids (classic and modern candidates, resolved at runtime)
-----------------------------------------------------------------------------

-- NEVER used blindly: each candidate is validated through C_Map.GetMapInfo.
WT.CITY_MAPS = {
	Stormwind = { classic = 1453, modern = 84 },
	Ironforge = { classic = 1455, modern = 87 },
	Darnassus = { classic = 1457, modern = 89 },
	Orgrimmar = { classic = 1454, modern = 85 },
	["Thunder Bluff"] = { classic = 1456, modern = 88 },
	Undercity = { classic = 1458, modern = 90 },
}

-----------------------------------------------------------------------------
-- model API (pure data, no widgets)
-----------------------------------------------------------------------------

function WT.Race(key) return WT.RACES_BY_KEY[key] end
function WT.Class(key) return WT.CLASSES[key] end
function WT.Weapon(key) return WT.WEAPONS[key] end
function WT.Trainer(id) return WT.TRAINERS_BY_ID[id] end
function WT.AllTrainers() return WT.TRAINERS end

-- Classes valid for a race, in canonical class order (stable cycling order).
function WT.ClassesForRace(raceKey)
	local race = WT.RACES_BY_KEY[raceKey]
	local out = {}
	if not race then return out end
	local valid = {}
	for _, key in ipairs(race.classes) do valid[key] = true end
	for _, key in ipairs(WT.CLASS_ORDER) do
		if valid[key] then out[#out + 1] = { key = key, name = WT.CLASSES[key].name } end
	end
	return out
end

function WT.IsValidCombo(raceKey, classKey)
	local race = WT.RACES_BY_KEY[raceKey]
	if not race or not WT.CLASSES[classKey] then return false end
	for _, key in ipairs(race.classes) do
		if key == classKey then return true end
	end
	return false
end

-- Ordered weapon entries for a class: allowed rows plus provisional rows.
function WT.WeaponsForClass(classKey)
	local class = WT.CLASSES[classKey]
	local out = {}
	if not class then return out end
	local allowed, provisional = {}, {}
	for _, key in ipairs(class.allowed or {}) do allowed[key] = true end
	for _, key in ipairs(class.provisional or {}) do provisional[key] = true end
	for _, key in ipairs(WT.WEAPON_ORDER) do
		local meta = WT.WEAPONS[key]
		if meta and (allowed[key] or provisional[key]) then
			out[#out + 1] = {
				key = key,
				label = meta.label,
				status = provisional[key] and "provisional" or "allowed",
				minLevel = meta.minLevel,
				cost = meta.cost,
				noTrainer = meta.noTrainer and true or false,
			}
		end
	end
	return out
end

-- Starting package for a race/class, falling back to the class _default.
function WT.Starts(raceKey, classKey)
	local byClass = WT.STARTS[classKey]
	if not byClass then return { weapons = {}, conf = "UNCONFIRMED" } end
	local entry = byClass[raceKey] or byClass._default
	if not entry then
		return { weapons = {}, conf = "UNCONFIRMED",
			note = "No starting package supplied for this combination." }
	end
	return entry
end

function WT.IsStarting(raceKey, classKey, weaponKey)
	local start = WT.Starts(raceKey, classKey)
	for _, key in ipairs(start.weapons or {}) do
		if key == weaponKey then return true end
	end
	return false
end

-- Trainers that teach a weapon for a race's faction. A race with no faction
-- (Skyborne) lists both factions; the UI notes that explicitly.
function WT.TrainersFor(raceKey, classKey, weaponKey)
	local out = {}
	local race = WT.RACES_BY_KEY[raceKey]
	if not race then return out end
	-- Class eligibility gate: only class weapons (or provisional) are offered.
	local eligible = false
	for _, w in ipairs(WT.WeaponsForClass(classKey)) do
		if w.key == weaponKey then eligible = true break end
	end
	if not eligible then return out end
	for _, t in ipairs(WT.TRAINERS) do
		local teaches = false
		for _, w in ipairs(t.weapons) do
			if w == weaponKey then teaches = true break end
		end
		if teaches and (race.faction == nil or t.faction == race.faction) then
			out[#out + 1] = t
		end
	end
	return out
end

function WT.ClassNotes(classKey)
	local class = WT.CLASSES[classKey]
	local out = {}
	if not class then return out end
	for _, n in ipairs(class.notes or {}) do
		out[#out + 1] = { text = n.text, conf = WT.CONF[n.conf] or n.conf }
	end
	return out
end

-- Human-readable weapon line for a race/class/weapon row.
function WT.WeaponLine(raceKey, classKey, weaponKey)
	local meta = WT.WEAPONS[weaponKey] or { label = weaponKey }
	local class = WT.CLASSES[classKey] or {}
	local provisional = false
	for _, key in ipairs(class.provisional or {}) do if key == weaponKey then provisional = true end end
	local status = provisional and "[provisional: Forever beta]" or "[allowed]"
	local starting
	local start = WT.Starts(raceKey, classKey)
	if (start.conf == "UNCONFIRMED") or #(start.weapons or {}) == 0 then
		starting = "starting unknown"
	elseif WT.IsStarting(raceKey, classKey, weaponKey) then
		starting = "supplied starting"
	else
		starting = "not a supplied starting weapon"
	end
	local req
	if meta.noTrainer then
		req = "default caster proficiency (no trainer)"
	else
		req = string.format("req level %d, %s", meta.minLevel or 1, meta.cost or "cost unknown")
	end
	return string.format("%s %s - %s  |  %s", meta.label, status, starting, req)
end

-- Build the scrollable reference entries for a race/class. Testable and
-- widget-free: each entry is { text =, color =?, trainers =? }.
function WT.BuildEntries(raceKey, classKey)
	local entries = {}
	local function text(t, color)
		entries[#entries + 1] = { text = t, color = color }
	end

	text("WEAPON TRAINING REFERENCE - " .. WT.SOURCE_NOTE, { 0.8, 0.9, 1 })
	text("This is a user-supplied reference, not a live client scan; trainers, costs and starting packages must be checked in game.")

	local race = WT.RACES_BY_KEY[raceKey]
	local class = WT.CLASSES[classKey]
	if not race or not class then
		text("No race/class selected.")
		return entries
	end

	if not WT.IsValidCombo(raceKey, classKey) then
		local names = {}
		for _, c in ipairs(WT.ClassesForRace(raceKey)) do names[#names + 1] = c.name end
		text(string.format("%s cannot be a %s. Available classes: %s.", race.name, class.name,
			#names > 0 and table.concat(names, ", ") or "none"), { 1, 0.6, 0.4 })
		return entries
	end

	local faction = race.faction or "unknown (faction unconfirmed)"
	local route
	if race.startZone and race.capital then
		route = string.format("%s -> %s", race.startZone, race.capital)
	else
		route = "unknown (start zone and capital not supplied; not invented)"
	end
	text(string.format("%s %s  |  Faction: %s  |  Start: %s", race.name, class.name, faction, route))

	local start = WT.Starts(raceKey, classKey)
	local startWeapons = {}
	for _, key in ipairs(start.weapons or {}) do
		startWeapons[#startWeapons + 1] = (WT.WEAPONS[key] and WT.WEAPONS[key].label) or key
	end
	local conf = WT.CONF[start.conf] or start.conf or "Unconfirmed"
	local startLine = #startWeapons > 0
		and string.format("Supplied starting skills: %s  |  Confidence: %s", table.concat(startWeapons, ", "), conf)
		or string.format("Starting skills: unknown  |  Confidence: %s", conf)
	text(startLine)
	if start.note then text(start.note, { 0.75, 0.85, 0.55 }) end
	if race.faction == nil then
		text("Skyborne faction and start zone are unconfirmed; trainer names below show both factions.", { 0.95, 0.8, 0.4 })
	end

	text("Eligible weapons and trainers", { 0.75, 0.9, 0.95 })
	for _, w in ipairs(WT.WeaponsForClass(classKey)) do
		local trainers = WT.TrainersFor(raceKey, classKey, w.key)
		local list = {}
		for _, t in ipairs(trainers) do
			list[#list + 1] = { id = t.id, name = t.name, faction = t.faction }
		end
		local color = w.status == "provisional" and { 0.98, 0.8, 0.42 } or { 0.9, 0.94, 0.97 }
		entries[#entries + 1] = {
			text = WT.WeaponLine(raceKey, classKey, w.key),
			color = color,
			trainers = list,
		}
	end

	text("Class notes", { 0.75, 0.9, 0.95 })
	for _, n in ipairs(WT.ClassNotes(classKey)) do
		text(string.format("- %s  [%s]", n.text, n.conf))
	end
	text("General reminders", { 0.75, 0.9, 0.95 })
	for _, n in ipairs(WT.GENERAL_NOTES) do text("- " .. n) end
	return entries
end

-----------------------------------------------------------------------------
-- map adapter (guarded, fails closed)
-----------------------------------------------------------------------------

-- Convert a supplied 0-100 percent coordinate to a 0-1 map coordinate. Values
-- already in 0-1 are accepted as-is. Out-of-range or secret values return nil.
function WT.NormalizeCoord(v)
	local n = ns.toNumber(v)
	if n == nil then return nil end
	if n < 0 or n > 100 then return nil end
	if n > 1 then n = n / 100 end
	if n > 1 then n = 1 end
	return n
end

function WT.MapCandidates(cityKey)
	local m = cityKey and WT.CITY_MAPS[cityKey]
	if not m then return {} end
	return {
		{ mapID = m.classic, source = "classic" },
		{ mapID = m.modern, source = "modern" },
	}
end

local function cityMatches(info, cityKey)
	if type(info) ~= "table" then return false end
	local name = info.name
	if ns.isSecret(name) or type(name) ~= "string" then return false end
	return name:lower() == tostring(cityKey):lower()
end

-- Resolve a supported map id for a city. Returns (mapID, source, info, reason).
-- It never returns an unvalidated retail id: each candidate must resolve to a
-- CITY map whose English name matches the requested city. A localized/renamed
-- or unknown client fails closed rather than placing a wrong waypoint.
function WT.ResolveMap(cityKey)
	local candidates = WT.MapCandidates(cityKey)
	if #candidates == 0 then
		return nil, nil, nil, "no known map id for '" .. tostring(cityKey) .. "'"
	end
	local cMap = C_Map
	if type(cMap) ~= "table" or type(cMap.GetMapInfo) ~= "function" then
		return nil, nil, nil, "C_Map.GetMapInfo unavailable on this client; map placement unsupported"
	end
	local lastReason
	for _, cand in ipairs(candidates) do
		local ok, info = pcall(cMap.GetMapInfo, cand.mapID)
		if ok and type(info) == "table" and not ns.isSecret(info) then
			local mapType = info.mapType
			if ns.isSecret(mapType) then
				lastReason = "map " .. tostring(cand.mapID) .. ": map data is restricted"
			elseif mapType ~= "CITY" then
				lastReason = "map " .. tostring(cand.mapID) .. " is not a city map (type " .. tostring(mapType) .. ")"
			elseif cityMatches(info, cityKey) then
				return cand.mapID, cand.source, info, nil
			else
				lastReason = "map " .. tostring(cand.mapID) .. " resolved to '" .. tostring(info.name) ..
					"', not '" .. tostring(cityKey) .. "' (localized or custom client): refusing a wrong waypoint"
			end
		else
			lastReason = "map " .. tostring(cand.mapID) .. " did not resolve on this client"
		end
	end
	return nil, nil, nil, lastReason or "no supported map id resolved"
end

local function inCombatLockdown()
	if type(InCombatLockdown) ~= "function" then return false end
	local ok, value = pcall(InCombatLockdown)
	if not ok then return true end -- an erroring lockdown API fails closed
	return value and true or false
end

WT.lastWaypoint = nil

-- Place a waypoint for a city. Coordinates are supplied as percent (0-100).
-- Returns (ok, method, message, result). Never claims success on explicit
-- false/error/secret, and never raises.
function WT.SetWaypoint(cityKey, x, y, opts)
	opts = opts or {}
	local result = { city = cityKey, x = x, y = y, ok = false }
	WT.lastWaypoint = result

	if inCombatLockdown() then
		result.method, result.message = "combat",
			"Combat lockdown: map and waypoint changes are disabled until combat ends."
		return false, "combat", result.message, result
	end

	local nx, ny = WT.NormalizeCoord(x), WT.NormalizeCoord(y)
	if not nx or not ny then
		result.method, result.message = "invalid",
			string.format("Coordinates out of range for %s (expected 0-100 percent); no waypoint placed.", tostring(cityKey))
		return false, "invalid", result.message, result
	end
	result.nx, result.ny = nx, ny

	local mapID, source, _info, reason = WT.ResolveMap(cityKey)
	if not mapID then
		result.method = "unresolved"
		result.message = string.format(
			"Could not resolve a supported %s map id (%s). Approximate coordinates %.1f, %.1f; no waypoint placed.",
			tostring(cityKey), tostring(reason), nx * 100, ny * 100)
		return false, "unresolved", result.message, result
	end
	result.mapID, result.mapSource = mapID, source

	-- Native client API first: C_Map.SetUserWaypoint + UiMapPoint.CreateFromCoordinates.
	local cMap = C_Map
	local hasNative = type(cMap) == "table" and type(cMap.SetUserWaypoint) == "function"
		and type(UiMapPoint) == "table" and type(UiMapPoint.CreateFromCoordinates) == "function"
	if hasNative then
		local pointOk, point = pcall(UiMapPoint.CreateFromCoordinates, mapID, nx, ny)
		if pointOk and point ~= nil and not ns.isSecret(point) then
			local setOk, setRes = pcall(cMap.SetUserWaypoint, point)
			if setOk and setRes ~= false then
				result.ok, result.method = true, "native"
				result.message = string.format("Set the user waypoint on %s (map %s, %.0f, %.0f).",
					tostring(cityKey), tostring(mapID), nx * 100, ny * 100)
				if type(C_SuperTrack) == "table" and type(C_SuperTrack.SetSuperTrackedUserWaypoint) == "function" then
					pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
				end
				return true, "native", result.message, result
			end
			result.nativeError = setOk and "SetUserWaypoint returned explicit false" or tostring(setRes)
		else
			result.nativeError = pointOk and "CreateFromCoordinates returned no usable point" or tostring(point)
		end
	end

	-- Optional TomTom support: fall back only when the native API is absent or
	-- refused. No hard dependency.
	if type(TomTom) == "table" then
		local fn = TomTom.AddWaypoint or TomTom.AddZWaypoint
		if type(fn) == "function" then
			local okT, resT = pcall(fn, TomTom, mapID, nx, ny, { title = cityKey, from = "DoHelper" })
			if okT and resT ~= false then
				result.ok, result.method = true, "tomtom"
				result.message = string.format("TomTom accepted a waypoint for %s (map %s, %.0f, %.0f).",
					tostring(cityKey), tostring(mapID), nx * 100, ny * 100)
				return true, "tomtom", result.message, result
			end
			result.tomtomError = okT and "TomTom returned explicit false" or tostring(resT)
		end
	end

	result.method = "unsupported"
	result.message = string.format(
		"No supported waypoint API on this client. %s is approximately %.1f, %.1f (map %s).",
		tostring(cityKey), nx * 100, ny * 100, tostring(mapID))
	return false, "unsupported", result.message, result
end

-- Open the world map to a city, guarded like SetWaypoint. The map/waypoint is
-- only changed by an explicit Show map / Set waypoint action, never by merely
-- selecting a trainer.
function WT.ShowMap(cityKey)
	if inCombatLockdown() then
		return false, "combat", "Combat lockdown: map opening is disabled until combat ends."
	end
	local mapID, _source, _info, reason = WT.ResolveMap(cityKey)
	if not mapID then
		return false, "unresolved", "Could not resolve a supported map for " .. tostring(cityKey) .. ": " .. tostring(reason)
	end
	local cMap = C_Map
	if type(cMap) == "table" and type(cMap.OpenWorldMap) == "function" then
		local ok = pcall(cMap.OpenWorldMap, mapID)
		if ok then return true, "native", "Opened the world map to " .. tostring(cityKey) .. " (map " .. tostring(mapID) .. ")." end
	end
	if type(ToggleWorldMap) == "function" and type(cMap) == "table" and type(cMap.SetMapByID) == "function" then
		local ok = pcall(function() cMap.SetMapByID(mapID); ToggleWorldMap() end)
		if ok then return true, "native", "Opened the world map to " .. tostring(cityKey) .. " (map " .. tostring(mapID) .. ")." end
	end
	return false, "unsupported", "No supported map-opening API on this client; " .. tostring(cityKey) ..
		" is map " .. tostring(mapID) .. ". Use the approximate coordinates instead."
end

-----------------------------------------------------------------------------
-- UI helpers (addon-owned widgets only)
-----------------------------------------------------------------------------

local WHITE = "Interface\\Buttons\\WHITE8X8"

local function safe(obj, method, ...)
	if obj and type(obj[method]) == "function" then
		local ok, res = pcall(obj[method], obj, ...)
		if ok then return res end
	end
	return nil
end

local function label(parent, text, x, y, width)
	local l = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	l:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	l:SetWidth(width or 400)
	l:SetJustifyH("LEFT")
	l:SetText(text)
	return l
end

-- Decorative background painted into the parent's own BACKGROUND draw layer so
-- it can never cover the parent's OVERLAY labels (same trick as Options.lua).
local function background(parent, x, y, width, height)
	local border = parent:CreateTexture(nil, "BACKGROUND")
	border:SetTexture(WHITE)
	border:SetVertexColor(0.12, 0.18, 0.22, 1)
	border:SetPoint("TOPLEFT", parent, "TOPLEFT", x - 1, y + 1)
	border:SetSize(width + 2, height + 2)
	local fill = parent:CreateTexture(nil, "BACKGROUND")
	fill:SetTexture(WHITE)
	fill:SetVertexColor(0.055, 0.075, 0.095, 1)
	fill:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
	fill:SetSize(width, height)
	parent.background = fill
	return fill
end

local function flatButton(b)
	if b.SetNormalTexture then
		b:SetNormalTexture(WHITE)
		local t = b.GetNormalTexture and b:GetNormalTexture()
		if t then t:SetVertexColor(0.1, 0.19, 0.23, 1) end
	end
	if b.SetPushedTexture then
		b:SetPushedTexture(WHITE)
		local t = b.GetPushedTexture and b:GetPushedTexture()
		if t then t:SetVertexColor(0.08, 0.32, 0.34, 1) end
	end
	b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
end

local PAGE_WIDTH = 770
local CONTENT_WIDTH = 748
local TRAINERS_PER_ROW = 5

local function newBlock(content)
	local block = CreateFrame("Frame", nil, content)
	block:SetSize(CONTENT_WIDTH, 60)
	block.label = label(block, "", 0, -2, CONTENT_WIDTH - 4)
	block.buttons = {}
	for i = 1, TRAINERS_PER_ROW do
		local b = CreateFrame("Button", nil, block, "UIPanelButtonTemplate")
		b:SetSize(145, 24)
		b:SetText("")
		flatButton(b)
		b:SetScript("OnClick", function(self)
			if self.trainerId then WT.OpenTrainer(self.trainerId) end
		end)
		block.buttons[i] = b
	end
	return block
end

function WT.BuildOptionsUI(f)
	if not f or f.weaponPage then return f and f.weaponPage end
	if type(CreateFrame) ~= "function" then return nil end

	local page = CreateFrame("Frame", nil, f)
	page:SetSize(PAGE_WIDTH, 492)
	page:SetPoint("TOPLEFT", f, "TOPLEFT", 15, -100)
	f.weaponPage = page
	background(page, -3, 4, PAGE_WIDTH + 6, 492)

	local heading = label(page, "Weapon training | DoHelper reference | " .. WT.SOURCE_NOTE, 8, -5, PAGE_WIDTH - 16)
	heading:SetTextColor(0.55, 0.75, 0.78, 1)
	page.heading = heading

	-- Race selector (cycling buttons; all 10 races reachable)
	label(page, "Race:", 8, -30, 60)
	local racePrev = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	racePrev:SetSize(26, 22); racePrev:SetPoint("TOPLEFT", page, "TOPLEFT", 64, -26)
	racePrev:SetText("<"); flatButton(racePrev)
	local raceLabel = label(page, "", 98, -30, 250)
	raceLabel:SetTextColor(0.92, 0.95, 0.97, 1)
	local raceNext = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	raceNext:SetSize(26, 22); raceNext:SetPoint("TOPLEFT", page, "TOPLEFT", 352, -26)
	raceNext:SetText(">"); flatButton(raceNext)

	-- Class selector (only classes valid for the selected race)
	label(page, "Class:", 8, -58, 60)
	local classPrev = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	classPrev:SetSize(26, 22); classPrev:SetPoint("TOPLEFT", page, "TOPLEFT", 64, -54)
	classPrev:SetText("<"); flatButton(classPrev)
	local classLabel = label(page, "", 98, -58, 250)
	classLabel:SetTextColor(0.92, 0.95, 0.97, 1)
	local classNext = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
	classNext:SetSize(26, 22); classNext:SetPoint("TOPLEFT", page, "TOPLEFT", 352, -54)
	classNext:SetText(">"); flatButton(classNext)
	page.raceLabel, page.classLabel = raceLabel, classLabel

	local message = label(page, "", 400, -30, PAGE_WIDTH - 410)
	message:SetTextColor(0.95, 0.8, 0.4, 1)
	page.message = message

	-- Scrollable, reusable reference rows.
	local scroll = CreateFrame("ScrollFrame", nil, page, "UIPanelScrollFrameTemplate")
	scroll:SetSize(PAGE_WIDTH - 20, 380)
	scroll:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -86)
	scroll:EnableMouseWheel(true)
	local content = CreateFrame("Frame", nil, scroll)
	content:SetSize(CONTENT_WIDTH, 380)
	scroll:SetScrollChild(content)
	page.scroll, page.content = scroll, content
	page.blocks = {}
	page.visibleTrainerButtons = {}

	scroll:SetScript("OnMouseWheel", function(self, delta)
		local range = self:GetVerticalScrollRange() or 0
		local position = self:GetVerticalScroll() or 0
		self:SetVerticalScroll(math.max(0, math.min(range, position - delta * 40)))
	end)

	f.weaponState = f.weaponState or { raceIndex = 1, classIndex = 1 }
	f.controls = f.controls or {}

	local function getBlock(i)
		local b = page.blocks[i]
		if not b then
			b = newBlock(content)
			page.blocks[i] = b
		end
		return b
	end

	function WT.RefreshUI(win)
		win = win or f
		local page2 = win.weaponPage
		local state = win.weaponState
		if not page2 or not state then return end
		local races = WT.RACE_ORDER
		if state.raceIndex < 1 then state.raceIndex = 1 end
		if state.raceIndex > #races then state.raceIndex = #races end
		local raceKey = races[state.raceIndex]
		local classes = WT.ClassesForRace(raceKey)
		if #classes == 0 then classes = { { key = "WARRIOR", name = "Warrior" } } end
		if state.classIndex < 1 then state.classIndex = 1 end
		if state.classIndex > #classes then state.classIndex = #classes end
		local classKey = classes[state.classIndex].key

		page2.raceLabel:SetText(WT.RACES_BY_KEY[raceKey].name)
		page2.classLabel:SetText(classes[state.classIndex].name)
		page2.message:SetText(string.format("%d / %d races   %d / %d classes",
			state.raceIndex, #races, state.classIndex, #classes))
		page2.selectedRace, page2.selectedClass = raceKey, classKey

		local entries = WT.BuildEntries(raceKey, classKey)
		local oldScroll = safe(page2.scroll, "GetVerticalScroll") or 0
		page2.visibleTrainerButtons = {}

		local y = 2
		local used = 0
		for i, entry in ipairs(entries) do
			local block = getBlock(i)
			used = used + 1
			block:Show()
			block.label:SetText(entry.text or "")
			local c = entry.color
			if c then block.label:SetTextColor(c[1], c[2], c[3], 1)
			else block.label:SetTextColor(0.9, 0.94, 0.97, 1) end
			local lh = safe(block.label, "GetStringHeight") or 14
			local shown = 0
			if entry.trainers then
				for _, t in ipairs(entry.trainers) do
					shown = shown + 1
					local b = block.buttons[shown]
					b.trainerId = t.id
					b:SetText(t.name)
					b:ClearAllPoints()
					b:SetPoint("TOPLEFT", block, "TOPLEFT", 2 + (shown - 1) * 149, -(lh + 4))
					b:Show()
					page2.visibleTrainerButtons[#page2.visibleTrainerButtons + 1] = b
				end
			end
			for j = shown + 1, #block.buttons do
				block.buttons[j]:Hide()
				block.buttons[j].trainerId = nil
			end
			local height = lh + (shown > 0 and 30 or 0) + 8
			block:SetHeight(height)
			block:ClearAllPoints()
			block:SetPoint("TOPLEFT", page2.content, "TOPLEFT", 0, -y)
			y = y + height
		end
		for i = used + 1, #page2.blocks do page2.blocks[i]:Hide() end
		page2.content:SetHeight(math.max(376, y + 4))
		safe(page2.scroll, "UpdateScrollChildRect")
		local range = safe(page2.scroll, "GetVerticalScrollRange") or 0
		safe(page2.scroll, "SetVerticalScroll", math.min(oldScroll, range))
	end

	racePrev:SetScript("OnClick", function()
		local n = #WT.RACE_ORDER
		f.weaponState.raceIndex = ((f.weaponState.raceIndex - 2) % n) + 1
		f.weaponState.classIndex = 1
		WT.RefreshUI(f)
	end)
	raceNext:SetScript("OnClick", function()
		local n = #WT.RACE_ORDER
		f.weaponState.raceIndex = (f.weaponState.raceIndex % n) + 1
		f.weaponState.classIndex = 1
		WT.RefreshUI(f)
	end)
	classPrev:SetScript("OnClick", function()
		local n = #WT.ClassesForRace(WT.RACE_ORDER[f.weaponState.raceIndex])
		if n == 0 then return end
		f.weaponState.classIndex = ((f.weaponState.classIndex - 2) % n) + 1
		WT.RefreshUI(f)
	end)
	classNext:SetScript("OnClick", function()
		local n = #WT.ClassesForRace(WT.RACE_ORDER[f.weaponState.raceIndex])
		if n == 0 then return end
		f.weaponState.classIndex = (f.weaponState.classIndex % n) + 1
		WT.RefreshUI(f)
	end)

	page.Refresh = function() WT.RefreshUI(f) end
	page.buttons = {
		racePrev = racePrev, raceNext = raceNext,
		classPrev = classPrev, classNext = classNext,
	}
	f.controls.weaponRacePrev, f.controls.weaponRaceNext = racePrev, raceNext
	f.controls.weaponClassPrev, f.controls.weaponClassNext = classPrev, classNext
	WT.RefreshUI(f)
	return page
end

-----------------------------------------------------------------------------
-- reusable trainer detail panel
-----------------------------------------------------------------------------

local DETAIL_NAME = "EllesmereUI_HoTPredictionWeaponTrainer"

local function detailText(t)
	local labels = {}
	for _, w in ipairs(t.weapons) do
		labels[#labels + 1] = (WT.WEAPONS[w] and WT.WEAPONS[w].label) or w
	end
	local lines = {
		"Faction: " .. tostring(t.faction),
		"City: " .. tostring(t.city) .. "  |  District: " .. tostring(t.district),
		string.format("Approximate coordinates: %.1f, %.1f (percent)", t.x, t.y),
		"Weapons taught: " .. table.concat(labels, ", "),
		"Data confidence: " .. (WT.CONF[t.conf] or t.conf or "Unconfirmed"),
		"Location: approximate, not exact. " .. WT.SOURCE_NOTE,
	}
	if t.note then lines[#lines + 1] = "Note: " .. t.note end
	lines[#lines + 1] = "Selecting a trainer never changes the map or a waypoint; use the buttons below."
	return table.concat(lines, "\n")
end
WT.DetailText = detailText

function WT.EnsureDetail()
	if WT.detail then return WT.detail end
	if type(CreateFrame) ~= "function" then return nil end
	local f = CreateFrame("Frame", DETAIL_NAME, UIParent, "BackdropTemplate")
	WT.detail = f
	f:SetSize(470, 260)
	f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
	f:SetFrameStrata("FULLSCREEN_DIALOG")
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", function(self) safe(self, "StartMoving") end)
	f:SetScript("OnDragStop", function(self) safe(self, "StopMovingOrSizing") end)
	f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
	f:SetBackdropColor(0.025, 0.035, 0.048, 0.99)
	f:SetBackdropBorderColor(0.18, 0.38, 0.4, 1)

	local title = label(f, "Weapon trainer", 16, -14, 440)
	title:SetFont("Fonts\\FRIZQT__.TTF", 16, "")
	title:SetTextColor(0.8, 1, 0.96, 1)
	f.titleLabel = title

	local body = label(f, "", 16, -44, 438)
	body:SetTextColor(0.9, 0.94, 0.97, 1)
	f.body = body

	local status = label(f, "", 16, -196, 438)
	status:SetTextColor(0.7, 0.88, 0.8, 1)
	f.status = status

	local function button(text, x, width, action)
		local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
		b:SetSize(width, 24)
		b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", x, 14)
		b:SetText(text)
		b:SetScript("OnClick", action)
		flatButton(b)
		return b
	end
	f.showMapButton = button("Show map", 16, 120, function()
		local t = WT.lastTrainer
		if not t then return end
		local ok, _method, msg = WT.ShowMap(t.cityKey or t.city)
		if status then status:SetText((ok and "Map: " or "Map unavailable: ") .. tostring(msg)) end
	end)
	f.waypointButton = button("Set waypoint", 144, 120, function()
		local t = WT.lastTrainer
		if not t then return end
		local ok, _method, msg = WT.SetWaypoint(t.cityKey or t.city, t.x, t.y)
		if status then status:SetText((ok and "Waypoint: " or "Waypoint not set: ") .. tostring(msg)) end
	end)
	f.closeButton = button("Close", 288, 120, function() f:Hide() end)

	if type(UISpecialFrames) == "table" then
		local present = false
		for i = 1, #UISpecialFrames do if UISpecialFrames[i] == DETAIL_NAME then present = true break end end
		if not present then UISpecialFrames[#UISpecialFrames + 1] = DETAIL_NAME end
	end
	return f
end

-- Open (or reuse) the detail panel for one trainer. This only reads data: the
-- map/waypoint is untouched until the user clicks an explicit control.
function WT.OpenTrainer(id)
	local t = WT.Trainer(id)
	if not t then return nil end
	local f = WT.EnsureDetail()
	if not f then
		ns.print("trainer detail unavailable: this client cannot create frames.")
		return nil
	end
	WT.lastTrainer = t
	f.titleLabel:SetText(t.name)
	f.body:SetText(detailText(t))
	f.status:SetText("")
	f:Show()
	return f
end

function WT.CloseDetail()
	if WT.detail then WT.detail:Hide() end
end
