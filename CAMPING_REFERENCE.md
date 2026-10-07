# WoW Forever camping tooltip reference

DoHelper displays a compact, additive English reference on item tooltips for
the exact item IDs below. It does not inspect item names, claim that a benefit
is currently active, or replace the game's native tooltip. Scaled results are
labelled **At your level (N)** and use a fresh hover-time player-level read.
Unknown, secret, invalid, or out-of-range levels get a clearly labelled
**Level-60 reference** instead. These are item baseline values, not values
modified by talents, legacy perks, other effects, or current active buffs.

## Sources and scope

* Guide: [Camping Overview, WoW Forever](https://www.wowhead.com/forever/guide/camping-overview-unlock-rewards), updated 2026-09-22; reviewed 2026-10-07.
* Item expression cross-check: `https://nether.wowhead.com/forever/tooltip/item/ID`
  for first-tier IDs 279960, 279956, 279944, 279962, 279972, 279968,
  279976 and 279967. Upper First Aid tiers 279940 / 279951 and Cookie's
  Feast 279957 were also checked; Iron Oven 279982 was confirmed through
  `https://nether.wowhead.com/forever/tooltip/spell/1263067`.
* Source text was supplied in decoded form at research time. The data below is
  hand-transcribed and boundary-tested; **live WoW has not been
  verified**.

The guide says higher tiers inherit the first-tier buff, not a larger stat
amount. “Shared 1h cooldown” below refers to feature placement cooldown; the
guide does not establish buff duration. Most placed features require a nearby
campfire, and sitting or crafting nearby for one minute grants camp benefits.
Those common conditions are only shown with items that actually provide camp
benefits, not with standalone utility features.

## Catalog

| Profession / item IDs | Benefit shown | Additional utility / qualification | Exclusive with |
| --- | --- | --- | --- |
| Mining: 279960 Lodestone, 279948 Rock Garden, 279952 Molten Foundry | Melee AP by level (table below) | Rock Garden spawns a common mining node over time; Foundry enables recipes requiring it | Blessing of Might |
| Alchemy: 279956 Mana Well, 279970 Fermenter, 279990 Alchemy Laboratory | Mana per 5 sec by level | Fermenter creates certain reagents; Laboratory enables recipes requiring it | Blessing of Wisdom |
| Blacksmithing: 279944 Sharpening Wheel, 279988 Anvil, 279955 Master Forge | Strength by level | Usable anvil; Master Forge enables recipes requiring it | Strength of Earth Totem |
| Herbalism: 279962 Incense Candle, 279964 Greenhouse, 279947 Seed Hybridizer | Intellect by level | Greenhouse grows herbs over time from planted seeds; Hybridizer multiplies or combines seeds | Arcane Intellect |
| Tailoring: 279972 Faction Banner, 279943 Spinning Wheel, 279959 Loom | Spirit by level | Wheel creates certain reagents; Loom enables recipes. The inherited banner buff is Horde-only; no unverified variants are inferred. | Divine Spirit |
| First Aid: 279968 First Aid Kit, 279940 Toxin Study, 279951 Plague Doctor's Laboratory | Stamina by level | Toxin Study supports healing potions and anti-venom; Lab supports healing potions and poultices. Endpoint confirms upper tiers inherit the kit buff despite guide “TBD”. | Power Word: Fortitude |
| Enchanting: 279976 Enchanted Lute, 279985 Arcane Salvager, 279987 Arcane Forge | Armor and all stats by level | Salvager improves disenchanting; Arcane Forge enables recipes requiring it. Resistance amount is unverified. | Mark of the Wild |
| Skinning: 279979 Camp Chair, 279969 Field Guide, 279938 Trapper's Workbench | +2% critical strike chance with all spells and attacks | Field Guide grants Track Beasts; workbench contains one trap | Moonkin Aura |
| Fishing: 279967 Fish Bowl, 279965 Fishing Rack, 279966 Fishing Hut | +8% stats | Rack catches uncommon fish for 1h; Hut catches rare fish for 1h; both provide Fishing Skill lures | Blessing of Kings |
| Leatherworking: 279978 Camp Tent, 279941 Tanning Rack, 279945 Sewing Machine | Rested XP up to 5% of a level | No effect if Rested XP is already above that cap; Tanning Rack creates certain reagents; Sewing Machine enables recipes | — |
| Engineering: 279950 Reagent Bot, 279949 Repair Bot, 279989 Anarchist's Workbench | No numeric buff asserted | Reagent Bot sells reagents; Repair Bot sells reagents and repairs gear; Workbench enables recipes only | — |
| Cooking: 279981 Basic, 279961 Journeyman, 279974 Expert Campfire Kit | Cooking and up to 3 / 5 / 10 additional camp features | Camp kit cooldown 5 min; sit or craft nearby 1 min for benefits of other camp features | — |
| Cooking: 279957 Cookie's Feast | Stamina-boosting food; amount unverified | Does not borrow a camp kit's stamina or invent a value | — |
| Cooking: 279982 Iron Oven | No numeric buff asserted | Required for advanced cooking recipes | — |

All camp feature-placement cooldowns are shared at 1 hour per the guide.
Fishing Rack/Hut's 1-hour fish-catching benefit is explicitly timed by the
source; no duration is invented for other buffs.

## Verified baseline brackets

Each row gives inclusive level ranges; values apply identically to all listed
tiers of that profession's buff.

| Benefit | Level brackets |
| --- | --- |
| Melee Attack Power | 1–11: 12; 12–21: 20; 22–31: 32; 32–41: 49; 42–51: 67; 52–60: 90 |
| Mana / 5 sec | 1–23: 10; 24–33: 15; 34–43: 20; 44–53: 24; 54–60: 29 |
| Strength | 1–23: 6; 24–37: 11; 38–51: 20; 52–60: 34 |
| Intellect | 1–13: 2; 14–27: 6; 28–41: 12; 42–55: 18; 56–60: 25 |
| Spirit | 1–39: 14; 40–49: 19; 50–59: 27; 60: 32 |
| Stamina | 1–11: 3; 12–23: 8; 24–35: 21; 36–47: 34; 48–59: 45; 60: 56 |
| Enchanted Lute armor | 1–9: 28; 10–19: 71; 20–29: 114; 30–39: 163; 40–49: 211; 50–59: 260; 60: 308 |
| Enchanted Lute all stats | 1–9: none; 10–19: 2; 20–29: 4; 30–39: 7; 40–49: 9; 50–59: 12; 60: 13 |

The Lute endpoint's resistance expression is malformed (reversed/blank
branches). DoHelper therefore gives no resistance numbers, only the source's
qualitative “increases all resistances” at level 30 or above, marked amount
unverified. No values are extrapolated or interpolated.

## Other camping / Legacy details

Guide-level context: campsite features are usable by visitors irrespective of
their profession, though profession skill may be needed to place/craft items.
The guide's Legacy perks include Reagent Economy (removes vendor-purchasable
reagents from class abilities and Tier 1 camping recipes), Field Guide (three
ranks, reduces adding-feature cooldown by 8%), and Permanence (two ranks,
increases certain long-duration party/raid stat effects and camp-rest benefits
by 50%). These are intentionally **not applied** to tooltip numbers because
character-specific Legacy ranks and modified outputs are not known. Native
tooltip skill requirements remain untouched.

Exact-ID coverage is deliberately conservative. No name matching, network
requests, inferred faction variants, guessed bonus durations, numeric
resistances, engineering vendor inheritance, or unverified cooking/food stat
amounts are used.
