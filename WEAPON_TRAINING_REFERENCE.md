# DoHelper — Weapon training reference data

This file documents the **data and provenance** behind the `Weapon training`
tab in `DoHelper/WeaponTraining.lua`. The data is a static,
code-embedded translation of the user-supplied WoW Forever reference.

> **Provenance:** every value below is **user-supplied** and **not live
> verified**. The tab is stamped *“User-supplied WoW Forever reference; not live
> verified”*. Trainers, locations, costs and starting packages are approximate
> and must be confirmed in the client. Nothing here is independently
> confirmed, and no network research was performed.

## Confidence legend

| Label | Meaning |
| --- | --- |
| `Classic-established reference` | Widely known from the classic-era game, still supplied as-is. |
| `Supplied Forever change` | A supplied difference from Vanilla (e.g. new races/classes/weapon access). |
| `Forever beta / provisional` | Possible but never confirmed for Forever. |
| `Supplied typical / verify client` | A supplied typical package that is explicitly client-verify. |
| `Unconfirmed - client verification required` | No package supplied; nothing invented. |

General reminders shown in the tab: learn the eligible proficiency from a
weapon master, equip the weapon, then raise the actual weapon skill in combat;
low skill means misses/dodges/parries; class eligibility is independent of the
race's starting package; do **not** assume Vanilla +5 racial weapon bonuses in
Forever (racials were redesigned).

## Weapon keys and labels

| Key | Label | Min level | Approx. cost |
| --- | --- | --- | --- |
| `AXE1` | One-Handed Axe | 1 | ~10s |
| `AXE2` | Two-Handed Axe | 1 | ~10s |
| `SWORD1` | One-Handed Sword | 1 | ~10s |
| `SWORD2` | Two-Handed Sword | 1 | ~10s |
| `MACE1` | One-Handed Mace | 1 | ~10s |
| `MACE2` | Two-Handed Mace | 1 | ~10s |
| `DAGGER` | Dagger | 1 | ~10s |
| `FIST` | Fist Weapon | 1 | ~10s |
| `STAFF` | Staff | 1 | ~10s |
| `POLEARM` | Polearm | 20 | ~1g |
| `BOW` | Bow | 1 | ~10s |
| `CROSSBOW` | Crossbow | 1 | ~10s |
| `GUN` | Gun | 1 | ~10s |
| `THROWN` | Thrown | 1 | ~10s |
| `WAND` | Wand | 1 | default caster proficiency, **no trainer** |

Normal weapon training is typically minimum level 1 / ~10 silver; polearms are
typically minimum level 20 / ~1 gold. The trainer client is authoritative.

## Race → class matrix (order = UI cycling order)

| Race | Faction | Start zone → capital | Classes |
| --- | --- | --- | --- |
| Human | Alliance | Elwynn Forest → Stormwind | Warrior, Paladin, Hunter (new), Rogue, Priest, Mage, Warlock |
| Dwarf | Alliance | Dun Morogh → Ironforge | Warrior, Paladin, Hunter, Rogue, Priest, Shaman (new) |
| Night Elf | Alliance | Teldrassil → Darnassus | Warrior, Hunter, Rogue, Priest, Druid |
| Gnome | Alliance | Dun Morogh → Ironforge | Warrior, Rogue, Priest (new), Mage, Warlock |
| Orc | Horde | Durotar → Orgrimmar | Warrior, Hunter, Rogue, Shaman, Mage (new), Warlock |
| Undead | Horde | Tirisfal Glades → Undercity | Warrior, Paladin (new), Rogue, Priest, Mage, Warlock |
| Tauren | Horde | Mulgore → Thunder Bluff | Warrior, Hunter, Shaman, Druid |
| Troll | Horde | Durotar → Orgrimmar | Warrior, Hunter, Rogue, Priest, Shaman, Mage, Warlock (new) |
| Skyborne - High Order | **unknown** | **unknown** | Warrior, Hunter, Rogue, Mage, Druid |
| Skyborne - Windshaper | **unknown** | **unknown** | Warrior, Hunter, Rogue, Shaman, Druid |

Skyborne faction/start zone are **not invented**; the UI shows trainer names
from **both** factions and notes that.

## Class weapon eligibility

* **Warrior:** AXE1, AXE2, SWORD1, SWORD2, MACE1, MACE2, DAGGER, FIST, STAFF,
  POLEARM, BOW, CROSSBOW, GUN, THROWN (never WAND). Polearms level 20; Dual
  Wield is a **class trainer** skill at level 20.
* **Paladin:** AXE1, AXE2, SWORD1, SWORD2, MACE1, MACE2, POLEARM. Undead
  paladin is a supplied Forever addition and keeps the check-client qualifier.
* **Hunter:** AXE1, AXE2, SWORD1, SWORD2, DAGGER, FIST, STAFF, POLEARM, BOW,
  CROSSBOW, GUN, THROWN (no maces, no wands). Forever Dual Wield is available
  without the old Survival talent dependency (no unsupported level claim).
* **Rogue:** DAGGER, THROWN, SWORD1, AXE1, MACE1, FIST, BOW, CROSSBOW, GUN.
  *Supplied Forever change:* AXE1 (not Vanilla). Dual Wield is a class trainer
  skill at level 10.
* **Shaman:** MACE1, MACE2, AXE1, AXE2, DAGGER, FIST, STAFF. *Supplied Forever
  change:* AXE2/MACE2 are normally trainable with no Enhancement talent
  requirement.
* **Druid:** MACE1, MACE2, STAFF, DAGGER, FIST; **POLEARM provisional** (Forever
  beta at level 20, never confirmed). Night Elf may additionally start with a
  Dagger (ambiguity kept).
* **Priest:** MACE1, DAGGER, STAFF, WAND.
* **Mage:** STAFF, WAND, DAGGER, SWORD1.
* **Warlock:** DAGGER, WAND, STAFF, SWORD1.

## Starting packages

| Class | Race | Supplied starting weapons | Confidence |
| --- | --- | --- | --- |
| Warrior | Human | AXE1, MACE1, SWORD1 | Classic-established |
| Warrior | Dwarf | AXE1, AXE2, MACE1 | Classic-established |
| Warrior | Night Elf | DAGGER, MACE1, SWORD1 | Classic-established |
| Warrior | Gnome | DAGGER, MACE1, SWORD1 | Classic-established |
| Warrior | Orc | AXE1, AXE2, SWORD1 | Classic-established |
| Warrior | Undead | AXE1, SWORD1, SWORD2 | Classic-established |
| Warrior | Tauren | AXE1, MACE1, MACE2 | Classic-established |
| Warrior | Troll | AXE1, DAGGER, THROWN | Classic-established |
| Paladin | Human | MACE1, MACE2, SWORD1, SWORD2 | Classic-established |
| Paladin | Dwarf | MACE1, MACE2 | Classic-established |
| Paladin | Undead | MACE1, MACE2 | Supplied typical / verify client |
| Hunter | Night Elf / Troll | BOW (ranged only) | Supplied typical / verify client |
| Hunter | Dwarf / Orc / Tauren | GUN (ranged only) | Supplied typical / verify client |
| Hunter | Human / Skyborne | *(none)* | Unconfirmed |
| Rogue | Human / Night Elf / Gnome / Undead | DAGGER, THROWN, SWORD1 | Supplied typical / verify client |
| Rogue | Dwarf / Orc / Troll | DAGGER, THROWN | Supplied typical / verify client |
| Rogue | Skyborne | *(none)* | Unconfirmed |
| Priest | *(default)* | MACE1, WAND | Classic-established |
| Priest | Gnome | MACE1, WAND | Supplied typical / verify client |
| Shaman | Orc / Tauren / Troll | MACE1, STAFF | Classic-established |
| Shaman | Dwarf | MACE1, STAFF | Supplied typical / verify client |
| Shaman | Skyborne Windshaper | *(none)* | Unconfirmed |
| Mage | *(default)* | STAFF, WAND | Classic-established |
| Mage | Orc | STAFF, WAND | Supplied typical / verify client |
| Mage | Skyborne High Order | *(none)* | Unconfirmed |
| Warlock | *(default)* | DAGGER, WAND | Classic-established |
| Warlock | Troll | DAGGER, WAND | Supplied typical / verify client |
| Druid | Night Elf | MACE1, STAFF (Dagger possible) | Classic-established + ambiguity |
| Druid | Tauren | MACE1, STAFF | Classic-established |
| Druid | Skyborne | *(none)* | Unconfirmed |

Hunter melee starts were **not** supplied and are not invented. The Orc hunter
ranged start is retained as the supplied GUN value rather than being silently
“corrected” to the classic bow.

## Trainers (8 supplied; locations approximate, not exact)

| Trainer | Faction | City | District | Coords | Weapons |
| --- | --- | --- | --- | --- | --- |
| Woo Ping | Alliance | Stormwind | Trade District | 57.1, 57.7 | CROSSBOW, DAGGER, SWORD1, SWORD2, STAFF, POLEARM |
| Buliwyf Stonehand | Alliance | Ironforge | Military Ward | 62.2, 89.6 | FIST, GUN, AXE1, AXE2, MACE1, MACE2 |
| Bixi Wobblebonk | Alliance | Ironforge | Military Ward | 62.2, 89.6 | CROSSBOW, DAGGER, THROWN |
| Ilyenia Moonfire | Alliance | Darnassus | Warrior's Terrace | 57.6, 46.7 | BOW, DAGGER, FIST, STAFF, THROWN |
| Sayoc | Horde | Orgrimmar | Valley of Honor | 81.5, 19.6 | BOW, DAGGER, FIST, AXE1, AXE2, STAFF, THROWN |
| Hanashi | Horde | Orgrimmar | Valley of Honor | 81.5, 19.6 | BOW, AXE1, AXE2, STAFF, THROWN |
| Ansekhwa | Horde | Thunder Bluff | Lower Rise | 40.9, 62.7 | GUN, MACE1, MACE2, STAFF |
| Archibald | Horde | Undercity | War Quarter | 57.3, 32.8 | CROSSBOW, DAGGER, SWORD1, SWORD2, POLEARM |

Wands have no trainer (default caster proficiency). Weller's Arsenal is a
classic-established Stormwind location but was **not** supplied, so it is not
used as an authoritative detail.

### Worked example: Tauren Druid

Mulgore → Thunder Bluff (Horde), supplied start MACE1 + STAFF. Eligible weapons
and trainers: MACE2 → Ansekhwa; DAGGER → Sayoc/Archibald; FIST → Sayoc;
STAFF → Sayoc/Hanashi/Ansekhwa; POLEARM → Archibald, **provisional** (level 20,
not confirmed eligible).

## City map ids and the guarded adapter

Candidate map ids (resolved at runtime; never used blindly):

| City | Classic id | Modern id |
| --- | --- | --- |
| Stormwind | 1453 | 84 |
| Ironforge | 1455 | 87 |
| Darnassus | 1457 | 89 |
| Orgrimmar | 1454 | 85 |
| Thunder Bluff | 1456 | 88 |
| Undercity | 1458 | 90 |

`WeaponTraining.ResolveMap(city)` accepts a candidate only when
`C_Map.GetMapInfo(id)` returns a table with the numeric `Enum.UIMapType.Zone`
map type (documented value `3`; there is no `CITY` map type), a matching `mapID`,
and a name matching a known English/known-localized alias (for example
`Stormwind` / `Stormwind City`, `Sturmwind`, `Eisenschmiede`, `Donnerfels`,
`Unterstadt`). A wrong type, a mismatched id, or an unknown localized name fails
closed without placing a waypoint. `SetWaypoint(city, xPercent, yPercent)`
converts **percent only** to 0–1 (`0.5` → `0.005`, `1` → `0.01`, `100` → `1`),
refuses in combat, then:

1. checks optional `C_Map.CanSetUserWaypointOnMap(id)` (fail closed on
   error/false/restricted) and uses native
   `C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(id, x, y))` only when
   it returns a confirmed `true` (optional
   `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`);
2. otherwise (or if native returns nil/false/secret or raises) falls back to
   optional modern TomTom `TomTom:AddWaypoint(uiMapID, x, y, opts)`, which must
   return a waypoint UID;
3. otherwise returns an honest failure that includes the approximate
   coordinates and the resolved map id.

`ShowMap(city)` uses the documented global `OpenWorldMap(mapID)`; when the map
frame is available it verifies `IsShown`/`GetMapID` and fails closed on a no-op
or the wrong visible map. The guarded `WorldMapFrame` fallback shows a hidden map
first and then calls `SetMapID` (a real `OnShow` resets the map, so the order
matters), retries through `C_AddOns.LoadAddOn("Blizzard_WorldMap")` when present,
and still verifies the frame before claiming success; it never toggles an
already-open map closed. Every external call is `pcall`-protected and
secret/restricted values (including error objects) are refused without coercion.
No proficiency is learned by clicking anything in this tab.

## Maintainer notes

* `WeaponTraining.lua` is split into static data, the map adapter and a lazy UI
  builder called from `Options.lua`. It adds no timers, events or polling.
* The historical AddOn folder, SavedVariables name, global frame ids and binding
  globals are **compatibility identifiers** and are intentionally unchanged; the
  Blizzard settings category is shown as **DoHelper**.
