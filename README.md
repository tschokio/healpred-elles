# EllesmereUI_HoTPrediction

A lightweight, standalone World of Warcraft addon that adds a **conservative
player self-cast HoT (heal-over-time) prediction segment** on top of the native
`EllesmereUIUnitFrames` incoming-heal prediction bars.

It can learn tick intervals and per-tick amounts from the combat log at runtime
**when the client actually exposes CLEU**, schedules the remaining ticks through
expiry, and appends only the part of that estimate that the native incoming
number does **not** already explain. On modern restricted clients the combat log
event is not accessible, so the supported path is explicit, persisted **manual
calibration** (`/euihot interval` + `/euihot amount`). It never modifies
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

### Updating (to v0.2.2)

Replace the `EllesmereUI_HoTPrediction/` folder in your AddOns directory with the
new one, then `/reload` (or restart). SavedVariables
(`EllesmereUI_HoTPredictionDB`) carry over; only the code changes. The fake test
value is never persisted, so update with no fake active. Verify with
`/euihot status` (version line) and, while previewing a fake, `/euihot
teststatus`.

## Quick start

1. Install `EllesmereUIUnitFrames`, **enable native heal prediction** for the
   player frame, then `/reload`.
2. While injured, verify rendering with `/euihot test 1000` (a fake `+1000`
   segment) and `/euihot teststatus` (one concise line). `/euihot test off`
   clears it. `/euihot status` reports what the addon actually sees.
3. Automatic prediction needs combat-log access. If `/euihot status` shows
   `delivered=0` (unverified) or `automatic tick learning unavailable`, this
   client does not expose CLEU. Calibrate by hand from numbers **you observe in
   the game** for the exact spell and stack count:

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

Automatic estimation may be unavailable on the supplied modern client. Static
calibration only works when the aura's duration/source and the native incoming
figures are readable; it cannot bypass secret-value restrictions.

## Commands

All commands are `/euihot ...` (alias `/hotpred ...`).

| Command | Effect |
| --- | --- |
| `test <value>` | Show a fake `+value` segment after the native chain (session only, finite non-negative). |
| `test off` | Clear the fake segment. |
| `teststatus` | One concise line for the fake render: unit/native readiness, requested amount, own overlay `IsShown`, range source (`native-range`/`UnitHealthMax`, public/restricted), last render reason, engine-clipped visible amount. Use this when chat scrollback is broken. |
| `status` | One concise report: settings, honest CLEU capability (`function`/`requested`/`registration`/`delivered`/gate), overlay structure, tracked HoTs (manual/approximate labels), prediction. |
| `debug [on\|off]` | Toggle on-demand diagnostics (prints status when turned on). Debug lines are emitted on change, not per tick. |
| `enable on\|off` | Enable/disable the overlay. |
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
| `reset` | Clear session learning and invalidate the aura cache. |

Settings persist in `EllesmereUI_HoTPredictionDB`. Manual interval/amount
calibration is persisted (it is user DPS/HPS data, not derived learning) and is
never erased by `/reset` or gear/spec events. A fake test value is **never**
persisted; a reload always starts with no fake active. `observe` is session-only
so a restricted client can never resurrect a forbidden registration.

---

## How it works

Modules (loaded in TOC order): `Core.lua` (namespace, settings, events, slash,
diagnostics), `Api.lua` (defensive client/EllesmereUI adapters + aura cache),
`Spells.lua` (candidate IDs), `Learner.lua` (combat-log learning), `Model.lua`
(tick math + overlap), `Overlay.lua` (our bar, anchoring, combat deferral).

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
startup. v0.2.1 adds: restricted retail/Forever builds never attempt forbidden
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
no raw secret is retained anywhere except our own widget.

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
