# EllesmereUI_HoTPrediction

A lightweight, standalone World of Warcraft addon that adds a **conservative
player self-cast HoT (heal-over-time) prediction segment** on top of the native
`EllesmereUIUnitFrames` incoming-heal prediction bars.

It can learn tick intervals and per-tick amounts from the combat log at runtime
**when the client actually exposes CLEU**, schedules the remaining ticks through
expiry, and appends only the part of that estimate that the native incoming
number does **not** already explain. Manual calibration (`/euihot interval` +
`/euihot amount`) can replace combat-log learning, **but cannot replace readable
aura timing/ownership or native incoming-heal values**. On the user's restricted
client, the fake overlay has been confirmed working; conservative HoT prediction
is blocked by missing combat-log access and secret native values. Version 0.3.0
adds an **opt-in rough estimate** from public tooltips or manual
amounts, ignoring heal absorbs and accepting unverified native overlap. It never modifies
EllesmereUI files, frames, textures or functions — it creates one small
StatusBar of its own and secure-hooks native callbacks read-only.

> Runtime status: this addon was developed and tested in a deterministic mocked
> environment. It has **not** been run inside a live WoW client here. Treat the
> behavior described as the implementation's intent; verify in game. There is no
> guarantee it is correct for every client/era.

---

## Install

1. Copy the folder `EllesmereUI_HoTPrediction/` into your client's AddOns
   directory, e.g.
   `World of Warcraft/_retail_/Interface/AddOns/EllesmereUI_HoTPrediction/`.
2. `EllesmereUIUnitFrames` must be installed and enabled — it is a hard TOC
   dependency.
3. **Native heal prediction must be enabled** for the player frame. Without it
   (or without both native prediction bars) the addon stays hidden and says so
   in `/euihot status`.
4. `/reload` or restart. Startup is silent. If the native prediction frame is
   not found you get exactly one message:
   `EllesmereUIUnitFrames prediction frame not found; overlay idle.`

The installed folder is the deliverable; there is no separate zip/binary.

### Updating (to v0.7.0)

Replace the `EllesmereUI_HoTPrediction/` folder in your AddOns directory with the
new one, then `/reload` (or restart). SavedVariables
(`EllesmereUI_HoTPredictionDB`) carry over; only the code changes. The fake test
value is never persisted, so update with no fake active. Verify with
`/euihot status` (version line), and, while previewing a fake, `/euihot
teststatus` or the copyable `/euihot window`.

## Quick start

### Queued next-swing action borders (v0.5.0)

With `EllesmereUIActionBars` installed, the existing helper now draws a thick,
opaque **cyan border** around buttons whose Maul, Heroic Strike, Cleave or Raptor Strike is
actually queued. Enabled by default; no separate addon or vendor edits required.
This feature does **not** require native healing prediction to be enabled.

* `/euihot queue on|off` toggles the feature independently of healing prediction.
* `/euihot queue color <r> <g> <b>` sets its persisted RGB (0–1 each), independently
  of the healing overlay's appearance. `/euihot queue status` reports candidates,
  highlighted buttons and queue-readability status; full status/window includes it.
* The existing options menu has a next-swing checkbox. `/euihot enable off`
  disables both features immediately and stops their background work.

**Appearance GUI (v0.5.1):** open `/euihot options` (or left-click the minimap
icon), then **Next-swing appearance...**. Edit border thickness (1–12 pixels),
border size/spacing (−12 to 24 pixels per side), opacity (0–1), and RGB color
(0–1 each), then click **Apply appearance**. Positive spacing enlarges the border
around the button; negative spacing places it inside the icon. This does not
resize the actual action button. **Restore defaults** restores the original
3-pixel cyan border, 3-pixel spacing and full opacity. All values persist;
invalid entries change nothing. Geometry edits during combat apply after combat,
while color/opacity apply immediately. Appearance edits never fake a queued spell.

Only exact known next-swing spell/rank IDs are eligible. Direct spell buttons use
public `IsCurrentAction(liveSlot)` (or `IsCurrentSpell` if the action API is absent).
Macro buttons require the client's effective `GetMacroSpell` ID and a public
`IsCurrentSpell` result; ambiguous macros are not guessed from text or tooltips.
Readable false is authoritative. Missing, erroring or secret state fails closed.
No press/cast-sent flag, Rage/range/usability inference, combat log, cooldown or
proc glow is treated as queue evidence. A failed attempt therefore cannot start
a border, nor does a failed attempt clear an already genuinely queued ability.

Queue events update borders immediately. A 50 ms local safety poll runs only when
eligible buttons exist and catches queue termination even without an event.
Existing helper timer discovery checks for new/replaced EllesmereUI buttons once
per second. Live action attributes are re-read to handle paging/forms and macros;
duplicate eligible buttons can all show the border. Auto Attack, auto-repeat,
stance/pet buttons and ordinary spells are excluded. Only addon-owned decoration
frames are changed, not vendor checked textures, proc glows, attributes or scripts.
Borders are prepared outside combat. A new button first discovered in combat
waits until combat ends for its border; prepared borders update during combat.

Mock-tested, **not live-verified**. Client APIs must expose the real current/queued
flag for these abilities; an instant-cast version or unavailable/restricted flag
does not receive a guessed highlight. In game, verify sufficient-Rage queue →
border, next swing/cancel → no border, insufficient-Rage failed press → no border,
and repeat with Cleave, Maul, forms/pages and any macros you use.

### Settings menu and minimap button (v0.4.0)

### Simple notes (v0.7.0)

A lightweight notepad for anything you want on screen while playing (flask
countdowns, pulls, loot rules, your own reminders).

* **Notes tab:** open `/euihot options` → **Notes**. Type into the multi-line box;
  the text is saved to `EllesmereUI_HoTPredictionDB` as you type.
* **Floating window:** click **Show floating notes**, run `/euihot notes`, or set
  the **Toggle notes window** key binding (Key Bindings → AddOns → EllesmereUI HoT
  Prediction). The window can be dragged by its title bar and is independent of the
  settings window.
* **Collapse / close:** **Collapse** rolls the window up to its title bar (click
  **Expand** to restore); **Close** hides it. Visibility and the collapsed state
  persist, so a note you leave open comes back after `/reload`.
* **Edit only out of combat:** the note is editable whenever you are out of combat
  and becomes read-only during combat, so it never swallows your keys. It unlocks
  automatically when combat ends.
* **Styling:** in the Notes tab set window **width/height** (180-900 × 80-800),
  **font size** (8-32), **text RGB**, and **background RGB + opacity** (0-1 each),
  then **Apply style**. **Reset style** restores the defaults. Size is set by the
  width/height fields (not by edge-dragging), so it is deterministic and safe in
  combat.

Notes are plain player data: no healing math, no vendor files and no idle timers.
Only the floating window's own drag creates a transient `OnUpdate` that the client
removes on release.

### Throw and custom spell editor (v0.6.1)

**Throw (`2764`)** now gets the same configurable action highlight when the
client reports a readable current-action/current-spell state. Throw is normally
a ranged attack, **not a melee next-swing queue**; its catalog card says so.
No readable state means no highlight. Auto-repeat actions are excluded.

Open `/euihot options` → **Manage spells...** (available from either tab):

* **Action highlight:** enter an exact spell ID and optional name, then **Add / update**.
  This registers eligibility only; actual readable current-action state is still
  required. Failed presses never light it. Auto Attack, Auto Shot and Shoot cannot
  be registered. Custom entries appear under **General / custom** in **All**.
* **Player HoT:** enter the actual applied aura ID, optional name, tick interval
  and full per-tick healing amount. This is manual calibration, not automatic
  discovery or evidence that the spell is a HoT. Requires readable owned player
  aura timing; another player's aura or a cast attempt is never enough.
* **Remove** disables that exact ID in the selected mode. **Reset ID** removes
  that ID's custom settings and restores its built-in definition, if one exists.
  For HoTs, reset also clears manual amount/interval calibration.

All registrations persist in SavedVariables. Exact ranks must be added separately;
changes do not affect the other registration mode. Slash equivalents:

```text
/euihot queue add 2764 Throw
/euihot queue remove 2764
/euihot queue reset 2764
/euihot spell add <auraID> <name>
/euihot interval <auraID> <seconds>
/euihot amount <auraID> <healingPerTick>
/euihot spell remove <auraID>
/euihot spell reset <auraID>
```

Mock-tested; in-game rendering/current-action availability still needs verification.

### All-class spellbook audit and icon catalog (v0.6.0)

Reviewed **503 entries across all nine ForeverChanges spellbooks** on 2026-10-04,
including Shaman in addition to the eight requested classes. The source build is
**1.60.1.70205**; see [SPELLBOOK_AUDIT.md](SPELLBOOK_AUDIT.md) for counts, URLs,
new IDs, classifications and limits. This is coverage of the listed class
spellbooks, not a claim of every racial, item, legacy-perk or server-triggered effect.

* **Raptor Strike:** all eight Forever ranks now use the existing real queued-state
  detector. Together with Maul, Heroic Strike and Cleave, these cover the known
  next-swing families in the reviewed books. Instant strikes, auto-shot, seals,
  weapon procs and triggered retaliation are not treated as queues.
* **Lightwell Renew:** actual applied aura IDs `7001, 27873, 27874`, not the summon.
  Requires readable player ownership/timing. Prefer the active aura tooltip;
  matching summon-rank descriptions are explicit fallback aliases. No cadence
  is invented: supply an observed `/euihot interval <activeID> <seconds>` or an
  explicit live per-tick tooltip. Removal/expiry stops prediction. Other players'
  Lightwells or an unidentifiable summon-owner remain excluded.
* **Drain Life:** all six Forever ranks, only during the player's actual readable
  channel. **Approximate mode only**; interrupt/end clears immediately on refresh.
* **Siphon Life / Devouring Plague:** all four/six ranks, only from an owned,
  readable harmful aura on the **current living hostile target**, not a player
  buff or cast attempt. **Approximate mode only**; cancellation/removal, death,
  target switch or restricted/missing target identity hides the estimate. Switching
  away intentionally drops off-screen drains; there is no multi-target forecast.
  Rank tooltip amounts already contain public displayed bonuses; no extra scaling.
  Damage resistance, absorption and future target death can reduce real healing,
  so these are explicitly unverified damage-dependent estimates, not guaranteed heals.
* All previously implemented Renew, Riptide and Druid healing remains supported.
  No new fixed healing magnitudes are baked in. Missing tooltip/cadence/ownership
  still withholds an estimate instead of guessing. English/German transfer clauses
  are supported; other locales need manual amounts/cadence.

The **Implemented spells** tab now uses **class icons, class-colored headings,
spell icon cards, support badges and short notes**. Filter by class using the icon
row; **All** includes custom candidates. Click **Rank IDs** on any implemented
card to expand exact enabled/disabled IDs. Unsupported/conditional cases are
separate, clearly labelled cards. It is a support catalog, not your known spells.
Cards are reused; there are no background catalog refreshes or new timers.

Only `UNIT_AURA` adds a target subscription; scans are event-invalidated and cached
by public target GUID, with a cheap validity/identity check during model reads.
The addon still paints **only the player frame**. Other players' healing,
pet frames, multi-target drains, ward trigger guessing and passive regeneration
are outside scope. All additions are mock-tested, not live-verified.

**Appearance window stacking fix (v0.5.5):** the next-swing appearance editor
uses `FULLSCREEN_DIALOG`, above the main settings window's `DIALOG` layer and
below tooltips. Its controls and preview inherit the higher layer so main-window
controls/borders cannot interleave into it, even when both windows are shown or
reopened in a different order. This changes only GUI layering, not settings or
real queue/healing logic. Mock-tested; in-game visual confirmation is still needed.

**GUI label visibility fix (v0.5.4):** decorative backgrounds now use the parent
frame's BACKGROUND textures instead of opaque child frames. This restores labels,
help text and status messages hidden by v0.5.3's redesign in the settings and
appearance views, and keeps the spell catalog readable. Buttons, preview behavior,
saved settings and real queue detection are unchanged. Regression tests cover
frame/draw-layer ordering; live in-game visual confirmation is still needed.

**Redesigned GUI and button preview (v0.5.3):** the dark-panel settings window
and next-swing appearance editor now include an isolated sample action button.
Choose Maul, Strike, Cleave or Raptor and click the sample to toggle its queued border.
The appearance editor previews valid size/thickness/opacity/RGB drafts as you type;
only **Apply appearance** saves them. Invalid drafts retain the last valid sample,
and closing/reopening reloads your saved values. The preview shares the real border's
geometry routine, but uses a 48px example icon rather than copying vendor frames.
It never casts spells, changes real queued state, or starts a fake healing preview.
No preview timers or animation loops are added. Live-game visual verification is
still needed; the GUI and preview interactions are mock-tested.

**Implemented spells tab:** open `/euihot options` and select **Implemented spells**.
Class-grouped cards are built from actual runtime spell registries when opened,
not your spellbook or active auras. Limitations and exclusions (including other
players' HoTs) are shown explicitly. Browsing does not change settings or start a preview.

* **Left-click the minimap icon** or use `/euihot options` (alias: `/euihot menu`).
  Also available under Blizzard's **Settings → AddOns → EllesmereUI HoT Prediction**
  when the client's settings API is available.
* **Right-click** the icon for copyable diagnostics. **Drag** it around the minimap;
  the angle is saved. The button follows the minimap's size with a circular path.
* Configure overlay enable/disable, approximate mode, native style or custom RGB,
  opacity, minimap visibility, debug logging, and the advanced native-excludes-HoTs
  assumption. Numeric appearance edits require **Apply appearance**; toggles save
  immediately. RGB is used only when native styling is unchecked.
* **Preview +1000** explicitly starts fake healing; **Stop preview** returns to real
  healing. Opening/closing settings does not start a preview or change predictions.
* Hide/show the icon with `/euihot minimap off|on`; the menu remains accessible
  through `/euihot options` even with the icon hidden or the overlay disabled.

The window is movable and closes with Escape. No extra libraries or background
timers are installed; cursor updates run only while dragging the minimap button.
Manual spell/rank calibration remains in slash commands. Approximate mode still
ignores healing absorbs and may double-count native incoming healing. Keep the
advanced overlap assumption off unless verified for your client.

### Shapeshift refresh (v0.4.1)

The helper now listens for player form and power-type changes. It refreshes aura
data and its own native-derived layout, then does two bounded follow-up refreshes
after 0.25/0.75 seconds to catch delayed client updates. Maximum-health scaling
is reapplied when rendering. `SPELLS_CHANGED` now requests a repaint after clearing
cached magnitudes, instead of leaving a previously blocked prediction idle.
Form changes do not restart HoT duration or discard manual calibration.

These fixes are mock-tested, not live-verified. They do not retain removed HoTs,
bypass restricted aura timing/ownership, or reparent replaced native frames in
combat. At full health the prediction may legitimately be clipped away. If an
active HoT still vanishes while injured, copy `/euihot window` snapshots before
and after shifting so we can identify the remaining suppression/attachment issue.

### Prediction setup

1. Install `EllesmereUIUnitFrames`, **enable native heal prediction** for the
   player frame, then `/reload`.
2. While injured, verify rendering with `/euihot test 1000` (a fake `+1000`
   segment) and `/euihot teststatus` (one concise line). `/euihot test off`
   clears it. `/euihot status` reports what the addon actually sees.
3. Automatic learning needs combat-log access. `delivered=0` alone means
   **unverified**, not necessarily unavailable. If access is unavailable, manual
   calibration is only useful when aura timing/ownership and native incoming
   values are readable. Secret native values still block real prediction, even
   with calibration. Otherwise calibrate from numbers **you observe in the game**
   for the exact spell and stack count:

   ```
   /euihot interval <actualSpellID> <seconds>
   /euihot amount   <actualSpellID> <tickTotal> [stacks]
   ```

   EXAMPLE ONLY (these are not game-mechanics constants, just a made-up
   illustration): if your own tick logged `200` and ticks arrive every `3s`,
   `/euihot interval 774 3` and `/euihot amount 774 200` describe a 4-tick
   remainder of `800`.
4. `/euihot test off`, then `/euihot status` to confirm the tracked HoTs and the
   manual/approximate labels.
5. Recalibrate `/euihot amount` after any gear or spell-rank change — manual
   values are user-authoritative and are **not** re-derived for you.

Automatic estimation may be unavailable on the supplied modern client. In
conservative mode, static calibration only works when aura duration/source and native incoming
figures are readable; it cannot bypass secret-value restrictions.

## Rough prediction on Forever

After installing the updated addon and `/reload`, run:

```text
/euihot enable on
/euihot test off
/euihot approximate on
```

This is a real-aura estimate, **not a fake test**. Cast Rejuvenation/Regrowth on
yourself while injured. Remaining ticks are counted from their readable duration
and expiration; the overlay shrinks as ticks pass and disappears at expiry.
Only self-cast auras count, with exact active spell IDs (ranks are not mixed).
The mode is persisted and defaults off. `/euihot approximate off` restores all
conservative gates.

* Public active-aura tooltip text is tried first, then
  `C_Spell.GetSpellDescription(actualSpellID)`. Only supported English/German
  periodic-healing clauses are parsed. Unknown/ambiguous/restricted text is
  withheld, never interpreted as zero. Regrowth's initial heal is excluded.
* On Forever, Rejuvenation and Regrowth use an **assumed 3-second cadence** unless
  an observed/manual interval or explicit per-tick tooltip provides another.
  A total of 48 over 12 seconds therefore estimates four 12-point ticks.
  v0.3.1 also uses a one-second assumption for Forever Wild Growth, explicit
  tooltip intervals for Tranquility, and per-second rage conversion for Frenzied
  Regeneration. Manual/observed intervals always take precedence.
* Tooltip amounts are cached for five seconds and refreshed for new applications,
  gear/spec changes, or reset. Unavailable descriptions retry at that cadence,
  not every paint. Status includes the amount/interval source and parsing errors.
* Tooltip values are used **as displayed**. The user confirmed their tooltips
  already include healing power. No additional healing-power/coefficient bonus
  is added, so it is not double-counted and Classic coefficients are not assumed.
* Healing absorbs are ignored even when present. If native incoming values are
  secret, the whole estimated remainder is appended after the native chain:
  **overlap is unverified and may double-count**. Readable native values still use
  the selected overlap policy. Secret health is handled by native missing-health
  clipping, not Lua arithmetic. Actual visible healing can be smaller than the
  requested amount. Critical ticks, talents, haste, and tick phase can differ.

If parsing fails, use your actual active ID from `/euihot window`. For example,
**only if spell 1058 really ticks for 12 on your character**:

```text
/euihot amount 1058 12
/euihot interval 1058 3
```

The previously reported aura was **1058**, not 774. A manual amount is the final
per-tick heal and wins over observed/tooltip amounts; recalibrate after upgrades.

The user confirmed v0.3.0's Rejuvenation/Regrowth tooltip prediction working in
Forever. The higher-level v0.3.1 additions are **mock-tested only**, not live-verified.

### Druid spellbook coverage (v0.3.1)

Reviewed [ForeverChanges' Druid spellbook](https://foreverchanges.pro/de/spellbook/druid)
and its English counterpart on 2026-10-03, for beta **1.60.1.70205**. That site
lists base numbers before equipment/talents/level scaling: they are used only as
test fixtures, **not baked into runtime healing amounts**. Live public tooltip
values remain authoritative. No website calls or downloaded databases run in game.

| Effect | Coverage | Important limitation |
| --- | --- | --- |
| Rejuvenation | All 11 listed ranks: 774 through 25299 | Remaining self-cast ticks; assumed 3s cadence. |
| Regrowth | All 9 listed ranks: 8936 through 9858 | HoT portion only, not the initial direct heal. |
| Wild Growth | Forever ranks 408120, 1238214, 1238215 (levels 40/50/60) | Per-player total is divided over assumed 1s ticks; the front-loaded taper is **not modelled**, so the tail may be overestimated. Never multiply by party size. |
| Tranquility | 740, 8918, 9862, 9863 (levels 30/40/50/60) | Estimates only healing to the player during their own active readable channel; cancellation/end clears it even if an aura lingers. Channel timing must be public. |
| Frenzied Regeneration | 22842 and candidate effect 22845 | Reads the tooltip's rage conversion. Budgets **only current readable rage**, capped by remaining per-second conversions; no future rage is invented. Rage **and maximum health** must be public, otherwise withheld with a diagnostic. A manual final tick amount is an alternative rough assumption. |
| Healing Touch / Swiftmend | Left to native direct-heal display | Not additional persistent HoTs. No duplicate instant-heal forecast. |
| Revive / Rebirth | Excluded | Resurrection is not remaining self-healing. |
| Innervate, Nature's Swiftness, dispels, buffs, forms, attacks | Excluded | Mana, utility, mitigation, or damage rather than scheduled healing. |

Frenzied Regeneration's listed effect 22845 has no description on the site; when
the live aura tooltip is unavailable, its metadata explicitly permits the listed
22842 description as an effect alias. This mapping needs live testing. A secret
rage/health value is never compared, multiplied, formatted or treated as zero.
Its tooltip conversion is percentages of maximum health, **not healing power**.
No old Classic flat 10-health-per-rage formula is used.

The former Retail/general candidates (Lifebloom 33763, Germination 155777,
Wild Growth 48438) remain manual/observation-only; this site does **not establish
their availability in Forever**. The newly verified Forever Wild Growth IDs are
separate. Other players' HoTs and predictions on party frames remain outside scope.

### Priest, Shaman and Paladin review (v0.3.2)

Reviewed the English and German ForeverChanges spellbooks for
[Priest](https://foreverchanges.pro/de/spellbook/priest),
[Shaman](https://foreverchanges.pro/de/spellbook/shaman) and
[Paladin](https://foreverchanges.pro/de/spellbook/paladin), same date/build as above.

* **Priest Renew:** all 10 listed ranks (139, 6074–6078, 10927–10929, 25315).
  Live tooltip total over 15 seconds, assumed 3-second ticks. Only your own Renew
  on yourself counts; removed/expired effects disappear normally.
* **Shaman Riptide:** all 3 Forever ranks (408521, 1239242, 1239243), levels
  40/50/60. Only the periodic 15-second portion counts, assumed 3-second ticks;
  the initial direct heal and Chain Heal bonus are excluded.
* **Paladin:** no scheduled health HoT found in this spellbook. Direct heals,
  absorb shields, Light's Vigil, Seal/Judgement of Light procs and mana
  restoration are not added as timed healing.

This is **not complete coverage of every healing effect**. Priest Contingency
Plan is a conditional ward followed by a separate triggered heal: the ward is
not counted before activation, and the triggered aura IDs/cadence still need
verification. v0.6.0 now registers Lightwell Renew's actual applied IDs; readable
ownership and a verified/manual/explicit-tooltip cadence are still required,
not the summoned object's three-minute duration. Penance needs verified
channel recipient tracking (unlike Tranquility, it does not necessarily heal the
caster). Prayer of Mending and Vampiric Embrace remain conditional. v0.6.0 adds
Devouring Plague as a rough current-target estimate in Approximate mode only.
Shaman Healing Stream Totem needs verified totem lifetime/rank/ownership and
player range tracking; its summon is not treated as a five-minute player HoT.
The other deferred effects are not automatically registered or predicted.

Renew/Riptide are mock-tested in English and German but **not live-verified**.
Character-specific public tooltip amounts include displayed bonuses without any
additional healing-power coefficient calculation. All these integrations still
require EllesmereUIUnitFrames and `/euihot approximate on` on restricted Forever.

## Commands

All commands are `/euihot ...` (alias `/hotpred ...`).

| Command | Effect |
| --- | --- |
| `test <value>` | Show a fake `+value` segment after the native chain (session only, finite non-negative). |
| `test off` | Clear the fake segment. |
| `teststatus` | One concise line for the fake render: unit/native readiness, requested amount, own overlay `IsShown`, range source (`native-range`/`UnitHealthMax`, public/restricted), last render reason, engine-clipped visible amount. Use this when chat scrollback is broken. |
| `status` | One concise report: settings, honest CLEU capability (`function`/`requested`/`registration`/`delivered`/gate), overlay structure, tracked HoTs (manual/approximate labels), prediction. |
| `window` | Open the copyable debug snapshot window (alias `debug window`). Lazy-created on first use; a titled, movable, clamped dialog with a selectable scrollable text box and Refresh / Select All / Close. |
| `debug window` | Same as `window`. |
| `approximate on\|off` | Opt into public tooltip/manual rough prediction; ignores absorbs and accepts unverified secret-native overlap. Default off. |
| `debug [on\|off]` | Toggle diagnostics (prints status when turned on). Automatic tick lines are change-detected and limited to one per second. |
| `enable on\|off` | Enable/disable the helper. Off immediately hides the overlay, clears fake tests, cancels the timer, and unregisters gameplay events. |
| `alpha <0..1>` | Overlay opacity (composited with the inherited native alpha). |
| `color <r> <g> <b>` | Set the custom overlay colour (0..1) and stop inheriting native style. |
| `color overlay <r> <g> <b>` | Same as above (explicit spelling). |
| `color native` | Restore the default: inherit native texture/colour. |
| `interval <spellID> <seconds>` | Manual tick-interval calibration (persisted). Positive id, seconds in (0, 300]. |
| `interval <spellID> off` | Clear the manual interval for one spell. |
| `amount <spellID> <tickTotal> [stacks]` | Manual per-tick total for an exact stack count (persisted, user-authoritative). Positive finite value, exact total — never multiplied by stacks. Stacks only meaningful for stacking families (Lifebloom). |
| `amount <spellID> off [stacks]` | Clear the manual amount for one spell (or one stack count). |
| `observe on\|off` | Session-only CLEU override. `on` requests guarded registration even on a restricted engine; `off` unregisters it. Never persisted. |
| `spell add\|remove <spellID> [name]` | Register/remove a modified spell/rank ID at runtime. |
| `amountmode total\|effective` | CLEU adapter assumption (see below); resets learned magnitudes. |
| `excludehots on\|off` | Explicit excludes-HoTs overlap opt-in (see below). |
| `notes [show\|hide\|toggle\|collapse\|expand]` | Show/hide/toggle the floating notes window, or collapse/expand it. With no argument it opens (shows) the window. |
| `reset` | Clear session learning and invalidate the aura cache. |

Settings persist in `EllesmereUI_HoTPredictionDB`. Manual interval/amount
calibration is persisted (it is user DPS/HPS data, not derived learning) and is
never erased by `/reset` or gear/spec events. A fake test value is **never**
persisted; a reload always starts with no fake active. `observe` is session-only
so a restricted client can never resurrect a forbidden registration.

### Performance and lag troubleshooting

There is no network traffic or continuous debug-window refresh. While enabled,
one 150ms timer coalesces player updates. Visible real estimates recalculate on
that timer; idle/blocked predictions only evaluate after owning events or
structure changes. A stationary fake is not repainted every tick. Frame identity
is checked every second while idle, and every tick while visible. Missing-frame
attachment retries are limited to once per second. Aura scans use an
event-invalidated cache, unit subscriptions are player-only except `UNIT_AURA`
(also current target for the opt-in life drains),
and native hooks ignore other frames. Pathological tick schedules exceeding
10,000 iterations are withheld rather than running an unbounded loop.

`/euihot enable off` now cancels the ticker (or removes the fallback OnUpdate),
unregisters gameplay/CLEU events, and makes existing secure hooks return before
reading frames. Secure hooks cannot be removed until reload. Enabling again
refreshes auras and clears learned samples that may have become stale while
disabled; persisted manual settings remain. Status/window commands remain usable
as explicit snapshots while paused.

To isolate reported lag, disable **only this helper** in the AddOns list and
`/reload`, then compare the same location/activity. This also works with older
versions whose slash disable did not stop the timer. Improvement is evidence of
a helper-related issue, not proof of which code path caused it. No live CPU/FPS
measurement was available during development, so the changes are not a claim
that the reported severe lag has been reproduced or eliminated.

v0.2.4's `/euihot window` includes session work counters for timer callbacks,
model evaluations, attachment resolves, render calls, and aura scans. Open or
Refresh twice several seconds apart to compare them; they are **not CPU timings**.
Snapshot collection itself can perform a one-off aura scan after invalidation.

---

## How it works

Modules (loaded in TOC order): `Core.lua` (namespace, settings, events, slash,
diagnostics), `Api.lua` (defensive client/EllesmereUI adapters + aura cache),
`Spells.lua` (candidate IDs), `Learner.lua` (combat-log learning), `Model.lua`
(tick math + overlap), `Overlay.lua` (our bar, anchoring, combat deferral),
`DebugWindow.lua` (lazy copyable snapshot window; no timers or frame scans).
`Estimates.lua` supplies the optional public-tooltip estimates.
`QueuedSwing.lua` supplies real-state action-button borders, using the same
namespace, saved database, runtime enable switch, timer discovery and diagnostics.

### CLEU (combat log) access and the engine gate
Modern clients deliver **no varargs** to `COMBAT_LOG_EVENT_UNFILTERED`; the
current event tuple is fetched with `CombatLogGetCurrentEventInfo()` and carried
as an explicit pack so nil holes and trailing `false` survive. A client that
instead delivers explicit varargs is handled by a documented legacy fallback. A
missing function, a `nil` tuple or an erroring getter is handled gracefully and
never raises.

Known restricted "Midnight" engines (current retail, interface/`toc` >= 120000,
i.e. 12.0.0/12.0.1, and Forever interface 16000..19999) **forbid** this event. On
those engines the addon does **not even attempt** registration by default, and it
also never registers when the API is missing. `/euihot observe on` requests a
guarded registration for a user who knows a modified client exposes the event;
`/euihot observe off` unregisters it. The override is session-only and is not
written to SavedVariables.

`/euihot status` reports honest capability rather than implying success:
`function=` (is the API present), `requested=` (did we ask), `registration=`
(did the client accept), `delivered=` (how many `COMBAT_LOG_EVENT_UNFILTERED`
events were **actually observed** — `0` means unverified), plus the gating
reason. A successful `pcall` / registration is **not** treated as proof the event
is accessible; only an observed delivery is. **When delivery is still 0,
automatic tick learning is unverified** (it may simply not have triggered yet) —
the addon loads quietly (no startup error), and `/euihot status` prints the
manual calibration instruction once, on demand. `/euihot reset` preserves
registration/delivery capability facts; it only clears learned data.

### Auras (strict self-cast only)
Reads `C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL|PLAYER")` (with a
guarded `"HELPFUL"` fallback). Every field read is pcall-wrapped because the
container itself may be a secret table; secret/non-numeric spell IDs, instance
IDs, stacks and timings are refused and never retained. An aura is counted only
when its explicit, readable `sourceUnit == "player"` — nil, secret and foreign
casters are withheld (recorded as a reason). Identity uses `auraInstanceID`;
stacks use `applications` (count 0 normalised to 1 for non-stacking auras).

**Aura cache.** The aura list is cached and rebuilt only when an owning event
invalidates it: `UNIT_AURA` for the player, entering world / login, `/reset`, and
`amountmode` changes. Tick calculations and learning reuse the cache. The paint
timer never rescans by itself, so idle ticks make no aura API calls.

### Learning from the combat log
Listens for `SPELL_PERIODIC_HEAL` where `sourceGUID == destGUID == player`, the
spell ID is a candidate, and a **positively owned current aura** exists.

* **Timing** is observed for *every* valid owned periodic event, including crit
  and absorbed ticks. A delta is only accepted for the **same aura instance and
  the same application/expiration signature**, so an in-place refresh resets the
  phase and never contributes a cross-refresh interval. A **non-nil readable
  `auraInstanceID` is required** for a learned interval: without one the addon
  conservatively declines to time the aura rather than risk mixing two
  applications. The interval is a robust estimate over a bounded recent window
  (haste changes adapt; dropped ticks do not inflate the cadence).
* **Magnitude** is learned only from readable, valid, **non-crit, non-absorbed**
  ticks.
* **Stacking families** (e.g. Lifebloom) are **not** modelled as
  `base * stacks`. The exact total observed at each stack count is stored, and
  the estimate is **withheld until that exact stack count has been observed**
  once. This avoids assuming linear stack mechanics for every family.
* **Strength-varying HoTs** (e.g. Wild Growth) use the conservative minimum of
  recent valid samples, so a declining tail is not overestimated. They are
  flagged `approximate`.
* **Adapter assumption**: by default the CLEU `amount` is taken as the total
  including overheal. `amountmode effective` uses `amount + overheal` for
  modified clients. There is no proof which the installed client reports, so this
  is an explicit, switchable assumption.
* Learning is **session only** (avoids stale gear values) and is invalidated on
  gear/spec changes (`PLAYER_EQUIPMENT_CHANGED`, `SPELLS_CHANGED`,
  `ACTIVE_TALENT_GROUP_CHANGED`). Form changes do not destroy data. Explicit
  `/euihot interval` and `/euihot amount` calibration **persists** and is never
  erased by `/reset`, gear or spec events.

### Manual calibration (the supported path when CLEU is unavailable)
On a restricted client there is no automatic learning; you calibrate from numbers
you observe yourself. Values are persisted separately from learned data and are
**user-authoritative** — they win over any learned value in both `GetSpellData`
and `AmountForStack`. They are labelled `(manual)` / `(manual interval)` in
`/euihot status`; the addon never pretends they were learned.

* `/euihot interval <spellID> <seconds>` sets the tick interval (0 < s <= 300).
  `/euihot interval <spellID> off` clears it.
* `/euihot amount <spellID> <tickTotal> [stacks]` sets the **exact total per
  tick** at a given stack count (positive, bounded). It is used as-is, never
  multiplied by the stack count. `/euihot amount <spellID> off [stacks]` clears
  one stack count or the whole spell. Non-stacking families are always keyed at
  stack 1 (the `[stacks]` argument is ignored for them); stacking families
  (Lifebloom) are keyed per exact stack count.
* A calibrated remainder still needs a **readable, player-owned active aura**
  (`sourceUnit == "player"`, readable duration/expiration). Foreign, nil, secret
  or expired auras are withheld; calibration never bypasses these gates.
* A freshly applied aura is timed on the **application grid**
  (`expirationTime - duration`) until a phase is actually observed; that is a
  documented approximation, not a measurement. If CLEU is explicitly enabled and
  actually delivered, a matching observed tick improves the phase.
* **Gear and spell-rank changes require recalibration.** Manual values are not
  re-derived; a rank/gear change can silently change the true tick size.
* `/euihot test` remains an unrelated fake overlay and never feeds calibration.
  It is a pure rendering exercise: it still requires the native structure
  (player unit, prediction on, both bars) but it never consults the real HoT
  estimate, so a missing self HoT is never reported as its reason. `/euihot
  teststatus` prints one concise line for it.

**What `/euihot test` can and cannot show (v0.2.2).** The fake segment sets our
own bar's `SetMinMaxValues(0, max)` and `SetValue(requested)`. The `max` comes
from the native prediction range (`_predMy:GetMinMaxValues`) or, failing that,
`UnitHealthMax` — exactly the restricted values the native EllesmereUI frame
consumes. If a value is **secret**, it is passed verbatim to the setter and never
inspected, compared, formatted or stored by us (only our widget holds it); the
settle is pcall-protected and a refusal hides the segment with a short reason.
Because the native clip still bounds the bar, and the current health may itself
be secret, the requested amount is not guaranteed to be fully visible: the
status calls it `unknown (engine-clipped)` rather than claiming a number. The
fake path also never calls the health-combining `GetHealthNumbers` adapter for
scaling, so a secret current health cannot block a perfectly usable max.

### Ticks
Ticks are placed on the application grid (`expirationTime - duration`) or on the
last observed tick when it belongs to the current aura instance **and signature**.
Only future ticks at or before expiry are counted; the tick exactly at expiry is
included (tolerance 1e-6). For non-stacking HoTs the per-tick amount is the
manual override if present, else the learned total; for stacking HoTs it is the
exact manual/learned total at the current stack count (never `base * stacks`).
Missing interval or amount => the estimate is withheld with a reason.

### Overlap / double-counting (conservative by default)
The native aggregate alone cannot prove whether it includes HoTs, so the default
is conservative:

```
added = max(0, hotEstimate - nativeTotal)
```

`nativeTotal` = native "mine" + "others" read from the native bars. A numeric
native total is required in **both** modes; there is no bypass of a
secret/unavailable native total via `excludehots`. The result is clamped so
native + added never exceeds missing health (`maxHealth - health - nativeTotal`),
floored at 0. If the native incoming number is secret/unavailable, or a heal
absorb is positive **or unknown** (API missing/error/non-numeric), the real
overlay is **suppressed** rather than doing unsafe arithmetic.

For users who have verified their runtime reports direct and HoT healing
additively, `excludehots on` appends the full HoT estimate:

```
added = hotEstimate      -- 600 direct + 800 hot => 1400 total
```

### Model / safety
`_predOn` must be true and both native prediction bars must be present for the
real overlay **and** the fake test, so no stale hidden anchor is ever used. The
player-frame unit must be a readable `"player"`; a vehicle or a secret/missing
unit hides the overlay (real and fake). Own event-driven painting is deferred
until the native prediction has settled (`UF_PaintHealPred` and apply/layout
hooks only queue a deferred paint). On full health the segment is clipped to
zero by the missing-health extent.

### Overlay rendering
Our own `StatusBar` with its **own texture** is parented to the native
`_missClip` (required; there is no unbounded fallback parent), anchored after the
last shown native prediction bar, and shares native orientation/reverse handling.
It copies the native texture **path**, colour RGBA, frame level and strata, plus
texture rotation where supported; our HoT segment is distinguished from native
direct healing by a subtly reduced alpha (`/euihot alpha`). The native bounds
masks (`_absorbMask`, and `hp._blizzMask` when `_blizzMaskOn`) are added to **our
own** fill texture and removed safely on change — the vendor textures are never
altered. Texture/colour/mask/layout are applied only on structural resolve or
when a native hook queues a style refresh, not every tick.

**Range / restricted values (v0.2.2).** The bar range is resolved by our own
`ApplyRange` adapter: it reads the native prediction range under `pcall` and
tests `issecretvalue` **before** any numeric check. A secret max is handed
verbatim to our own `SetMinMaxValues(0, max)` (pcall; boolean result only) and
never compared, calculated, stringified or branched on. A public max must be a
finite number `> 0`. If the native range is unavailable or the setter refuses it
(for example an engine that will not accept a restricted range from us), the
fallback is `UnitHealthMax` — deliberately **not** the current-health-combining
`GetHealthNumbers` adapter, so a secret current health cannot block a usable max.
The failure reason is a short public label of the source and whether it was
`restricted`; the range value itself is never placed in chat or session state
(only our widget stores it). The real overlap path is unchanged and still
refuses a secret native incoming: this range fix enables safe rendering, it does
not claim automatic prediction works.

Native apply/layout/mask hooks only queue deferred work, and are **filtered to
the current player frame**: a callback carrying a different frame/unit (target,
focus, …) is ignored instead of forcing a player rescan. The native painter hook
only ever requests a repaint. A callback with no identifying argument is treated
conservatively (it may mark the player), which is what the deterministic tests
exercise.

First attach and later frame replacement are detected automatically by a cheap
periodic identity probe and applied out of combat; there is no need to call any
resolve function manually. Reparent/create/hook installation happen out of
combat. During combat a fixed, already-attached bar may update its own safe
size/orientation/anchors; a structural replacement is deferred and the overlay is
hidden until regen rather than painted against stale handles. The overlay is
never created for the first time in combat.

---

## Candidate spell IDs (facts vs uncertainty)

From the verified Forever presets (`EllesmereUI_BuffPresets.lua`):

* Rejuvenation ranks: `774, 1058, 1430, 2090, 2091, 3627, 8910, 9839, 9840, 9841, 25299`
* Regrowth ranks: `8936, 8938, 8939, 8940, 8941, 9750, 9856, 9857, 9858`

Candidate IDs seen in retail/general buff managers, **not proof they exist on
the installed client**: Lifebloom `33763` (stacking), Germination `155777`,
Wild Growth `48438` (approximate). Availability is decided at runtime by
observed auras/combat log. Use `/euihot spell add <id>` for modified IDs.

No tick magnitudes or intervals are hard-coded anywhere. Lifebloom's bloom is
excluded automatically because only `SPELL_PERIODIC_HEAL` is observed. Wild
Growth's target-count-dependent tick strength is conservatively approximated per
self tick and flagged `approximate` in status/debug.

---

## Diagnostics

`/euihot status` reports: settings; **honest CLEU capability** (`function=`,
`requested=`, `registration=`, `delivered=` with the gate reason) and, when no
delivery has been observed, the explicit manual-calibration instruction; whether
the overlay frame exists with its real frame/hp names and references; the client
build from `GetBuildInfo`; each tracked active owned HoT with spell name, stacks,
expiry/duration, interval, remaining ticks and amount, labelled `(manual)` /
`(approximate)` where applicable; the total vs visible (clamped) prediction and
the suppress reason. `/euihot debug on` adds rich internals including manual
calibration counts. Status formatting is pcall-protected and only printed on
demand. There are no automatic chat prints except one useful startup failure
line.

`/euihot teststatus` (v0.2.2) is a compact one-line alternative to the long
`/status` dump, intended for a broken chat scrollback. It reports the player unit
and native readiness, the fake requested amount, whether our own overlay is
shown, the last range source and whether it was `public` or `restricted`, the
last render reason, and calls the visible amount `unknown (engine-clipped)`.
When a fake is active, full `/status` labels it as a fake test and no longer
reports an unrelated real-model "no active self HoT estimate" or a bogus numeric
`visible=0`; a secret range/value is never formatted.

### Copyable debug window (`/euihot window`)

For chat scrollback that is broken or too small to select, `/euihot window`
(alias `/euihot debug window`) opens an addon-owned, titled, movable and
screen-clamped dialog containing a plain-text **snapshot** of the diagnostics.
The window is created lazily on the first open and reused thereafter (hidden,
never deleted, so its position sticks for the session); Escape closes it via the
standard `UISpecialFrames` registry.

* The text lives in a scrollable, multiline `EditBox` that is automatically
  **not** focused when the window merely opens. To copy: click **Select All**,
  then press **Ctrl+C**. The operating system performs the copy — the addon does
  not claim any clipboard API, it only selects the text.
* **Refresh** captures a new snapshot. A snapshot is *not* a live log: it
  contains a public `GetTime` capture timestamp plus a compact `teststatus` line
  and the full status with rich internals **forced on** for that capture,
  irrespective of the persisted `debug` setting (which is never changed). No
  character name or other private data is included.
* There are no timers, `OnUpdate` handlers, network calls or frame scans, so a
  live overlay tick can never steal a selection you are copying. Refresh clears
  the old selection/focus, writes the whole report and resets the scroll to the
  top.
* Typing in the box edits the on-screen copy only; it can never mutate addon
  settings, learned data or the fake test. The text is plain (no `|c`/`|r`
  artifacts) and never contains a raw secret value.
* The shared builders `ns.BuildStatusReport(includeDebug)` and
  `ns.BuildTestStatusReport()` return the same text as strings without printing;
  `/status` and `/teststatus` print them unchanged. On a build failure the
  window shows useful fallback text rather than a repeated Lua error. If the
  client cannot create frames or is missing an optional widget API, opening the
  window degrades gracefully (one clear chat line) and the report builders still
  return copyable text.

---

## Tests

Deterministic Lua tests with a mocked WoW environment (frames, textures and
their mask APIs, auras, modern no-vararg CLEU with explicit-pack tuples,
secret-value sentinel that raises on arithmetic/comparison/indexing, combat
lockdown, timers).

Run the whole suite from the repository root:

```sh
bash tests/run_tests.sh
```

The script prefers any native `lua5.4/5.3/5.1/lua/luajit`, and otherwise runs
`tests/luarun.js` with the pure-JS Lua VM **fengari**, fetching it into a local
cache (`~/.cache/ai-coding-v2/tmp/luatools`) if needed — never into the repo.
You can also run directly:

```sh
lua tests/run.lua
# or, with fengari available on NODE_PATH:
HOT_LUA_NODE_PATH=/path/to/fengari node tests/luarun.js
```

Success ends with `RESULT pass=<n> fail=0 total=<n>` and exit code 0.

Coverage includes: modern CLEU fetch and explicit-pack tuple handling (nil holes
and trailing false); nil/secret ownership and source filtering; aura cache reuse
on idle ticks and invalidation on player-only `UNIT_AURA`; interval cadence for
crit/absorbed ticks without magnitude; same-instance refresh phase reset; bounded
haste-aware intervals; stack-specific totals withheld until observed; approximate
(declining) amounts; secret GUID/instance/container/stacks/timing with no secret
retained; unknown/missing heal absorb suppression; numeric-native requirement in
both overlap modes; excludes clamp including native; vehicle and nil-unit hiding
(real and fake); native off even for fake; overlay masks, retexture and texture
rotation with vendor textures untouched; deferred hook work and automatic timer
replacement; combat deferral; commands, validation, session-only fake, quiet
startup. The mocked environment also provides EditBox/ScrollFrame/button
widgets, FontStrings, real focus/highlight/selection state and a per-environment
`UISpecialFrames` table with named-global cleanup. v0.2.1 adds: restricted retail/Forever builds never attempt forbidden
CLEU registration; a missing CLEU function never registers; `/observe off`
unregisters and `/observe on` re-requests; an accepted registration is shown as
`delivered=0` until a real event arrives; `/reset` preserves registration and
delivery capability; `RegisterEvent` returning `false` is treated as rejection;
manual `interval`+`amount` estimate works with no CLEU at all (identical
`800`/clamp/expiry/foreign-source behaviour); stack-specific exact Lifebloom
amounts; calibration validation and `off` clearing; overrides survive reset and
gear changes and beat learned values; status reports the calibration instruction;
target/focus hook callbacks are ignored while player/argless callbacks mark the
player; the native painter only requests a paint. v0.2.2 adds: the fake `+20000`
segment renders while the native ranges, current/max health and native incoming
are all secret and CLEU is unavailable; a restricted native range is passed
through to our setter untouched; `UnitHealthMax` fallback is tried independently
when the native getter is gone or the setter refuses a secret; a secret current
health never blocks a public max; a missing/invalid range or an erroring setter
stays hidden with the actual reason and a bool return; `/test off` hides on the
next tick; `EvaluateFake` still honours native-off/vehicle gates; `/teststatus`
is one concise line and neither it nor `/status` claims a real HoT or a numeric
visible zero for a fake; a real manual HoT stays suppressed on secret incoming;
no raw secret is retained anywhere except our own widget. v0.2.3 adds: the
debug snapshot window is created lazily and reused as one named frame; repeated
opens/refreshes print no chat; a forced-internals report is produced while the
persisted `debug` setting stays off; Refresh reflects a changed fake amount;
Select All focuses and selects the whole report; a live overlay tick does not
disturb the text or selection; Close/Escape hide it and clear focus; manual
editing cannot mutate addon data; the window adds no ticker, event, `OnUpdate`
or vendor-frame change; and missing Ellesmere/CLEU/secret-range inputs still
yield copyable text instead of errors. v0.7.0 adds: the Notes tab switches pages
without side effects; edits persist and mirror between the options editor and the
floating window; the note is read-only in combat and unlocks on
`PLAYER_REGEN_ENABLED`; collapse/close/restore and the drag-saved position
persist; style apply is validated atomically and resets to defaults; text is
capped and refuses secret/non-string input; the floating window keeps no idle
`OnUpdate` and its title is not occluded by its own editor; and the key-binding
entry point toggles the window.

---

## Limitations

* Not verified in a live client; CLEU payload shape, `C_UnitAuras` filter support,
  native bar secrecy and the internal hook names vary by client/era.
* Requires native heal prediction enabled; v1 does not draw its own offset bars.
* **First tick(s) are delayed**: nothing is appended until an interval (and, for
  stacking families, the current stack count's magnitude) has been observed or
  calibrated.
* Automatic estimation may be **unavailable on the supplied modern client**: the
  restricted Midnight engines forbid CLEU and the addon deliberately does not
  attempt registration there. Static manual calibration works only when the
  aura's duration/source and the native incoming fields are readable — it cannot
  bypass secret-value restrictions.
* Manual calibration is **user data, not learning**: it must be recalibrated
  after gear or spell-rank changes and is never silently adjusted.
* Default overlap is conservative and may under-predict during direct casts.
* Strength-varying HoTs are conservatively approximated.
* Secret/unavailable incoming, unknown/positive heal absorbs, a non-player/secret
  frame unit, or unreadable bar scaling suppress the overlay rather than guess.
  v0.2.2 fixes only the **rendering** path (`SetMinMaxValues`/`UnitHealthMax` range
  handling); it does not make automatic prediction work where CLEU is
  unavailable, and the real overlap still refuses a secret native incoming.
  The real CLEU/native restrictions on the supplied restricted client remain
  unresolved and are not worked around.
* Haste-curve phase drift is approximated by the recent-window learned interval.
* Automatic learning is per session; only explicit manual interval/amount
  calibration persists.
