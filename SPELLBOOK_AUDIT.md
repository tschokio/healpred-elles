# Forever class spellbook audit — v0.6.0

Reviewed 2026-10-04, ForeverChanges beta **1.60.1.70205**, from the actual embedded
rank data in each page, including trainer, talent and Priest racial entries.
English Warlock, Priest and Hunter pages were cross-checked for transfer clauses
and Raptor Strike rank IDs. Sources describe base numbers before gear/talents:
they are **not runtime healing constants**. Only live public tooltips/manual data
provide amounts. No website requests happen in the installed addon.

| Class / source | Entries reviewed | Queued families | Scheduled player healing / finding |
|---|---:|---|---|
| [Warrior](https://foreverchanges.pro/de/spellbook/warrior) | 42 | Heroic Strike, Cleave | No finite HoT. Forever Bloodthirst lost Classic healing charges; Victory Rush is instant. |
| [Hunter](https://foreverchanges.pro/de/spellbook/hunter) | 59 | **Raptor Strike added** | Mend Pet is pet-only. Auto Shot is auto-repeat, not a next-melee queue. |
| [Mage](https://foreverchanges.pro/de/spellbook/mage) | 60 | None identified | Mana regeneration, barriers and conjured food are not timed player HoTs. |
| [Rogue](https://foreverchanges.pro/de/spellbook/rogue) | 57 | None identified | Instant strikes, poisons and procs are not queues or scheduled healing. |
| [Priest](https://foreverchanges.pro/de/spellbook/priest) | 57 | None identified | Renew; **Lightwell Renew effect IDs added**; **Devouring Plague rough estimate added**. Triggered wards, Penance recipient tracking and conditional heals remain deferred. |
| [Warlock](https://foreverchanges.pro/de/spellbook/warlock) | 56 | None identified | **Drain Life / Siphon Life rough estimates added**. Health Funnel is pet-only; passive regeneration and unidentified Demonic Sacrifice effect auras are not finite HoTs. |
| [Paladin](https://foreverchanges.pro/de/spellbook/paladin) | 56 | None identified | Holy Strike is explicitly instant. Light's Vigil and seals depend on future actions; direct heals stay native. |
| [Druid](https://foreverchanges.pro/de/spellbook/druid) | 60 | Maul | Rejuvenation, Regrowth, Wild Growth, Tranquility and Frenzied Regeneration already supported. Lifebloom/Germination general candidates are **not established** in these Forever books. |
| [Shaman](https://foreverchanges.pro/de/spellbook/shaman) | 56 | None identified | Riptide already supported. Healing Stream requires own totem lifetime/identity and range, not just a persistent buff. |
| **Total** | **503** | **Four known families** | All books examined; not all healing/attack effects are predictably scheduled. |

## Exact new IDs and runtime requirements

* **Raptor Strike:** `2973, 14260, 14261, 14262, 14263, 14264, 14265, 14266`.
  The site supplies ranks and unchanged Classic descriptions, not a universal
  queue API guarantee. The client must actually expose readable current-action/
  current-spell state. If a client makes any variant instant, no highlight is
  guessed from its press/cast-sent event.
* **Lightwell Renew:** `7001, 27873, 27874`. Description aliases map respectively
  to summon ranks `724, 27870, 27871`; the **summon itself is never predicted**.
  Applied aura must have readable `sourceUnit == "player"` and finite timing.
  Its cadence is not in the spellbook: manual/observed or explicit tick text is
  required. A secret/unknown/totem source is not assumed to be player-owned.
* **Drain Life:** `689, 699, 709, 7651, 11699, 11700`. Real readable channel timing,
  public transfer tooltip, approximate mode. Spellbook says 1-second transfers;
  channel interruption/end wins over any lingering aura.
* **Siphon Life:** `18265, 18879, 18880, 18881`. Owned current-target debuff,
  readable alive/hostile/exists/GUID facts, approximate mode. Tooltip specifies
  3-second transfers; no target = no estimate, no cast attempt fallback.
* **Devouring Plague:** `2944, 19276, 19277, 19278, 19279, 19280`. Same current-target
  gates. 3-second cadence is an explicit approximate assumption (the source gives
  a 24-second total, not an explicit tick interval); observed/manual cadence wins.
  Public damage total is used as an **unverified damage-dependent healing estimate**.

## Why some requests cannot safely be automatic

**Contingency Plan** `1277462, 1277634, 1277638, 1277639, 1277640` is a 30-second
ward which can trigger a different 15-second heal. The cast/ward is not proof of
activation; the source does not identify the triggered effect's exact aura ID.
**Penance** `402174, 1240720, 1240721, 1316995` can heal a friend or damage an enemy;
its channel name is not proof it is healing the player. **Prayer of Mending** and
**Vampiric Embrace** depend on future damage/procs, so no scheduled healing is invented.

**Demonic Sacrifice** `18788` has swapped demon benefits in Forever. Its cast ID
does not identify the active health-regeneration effect. **Demon Skin/Armor**
increase passive health regeneration for 30 minutes; forecasting that whole
duration would make the health bar look permanently fully healed. **Healing
Stream Totem** needs verifiable own-totem identity, lifetime and range; the summon
or aura duration alone does not establish the remaining in-range ticks.

This audit does not establish every hidden proc/aura, racial ability, consumable,
legacy effect or higher-level rank from other client eras. Existing later-era
next-swing rank candidates remain supported only when the client actually reports
them queued. Other players' HoTs, pet healing and multi-target tracking remain
outside the helper's player-frame scope. All new behavior is mock-tested and
needs in-game verification.
