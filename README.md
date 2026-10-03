# EllesmereUI_HoTPrediction

A lightweight, standalone World of Warcraft addon that adds a **conservative
player self-cast HoT (heal-over-time) prediction segment** on top of the native
`EllesmereUIUnitFrames` incoming-heal prediction bars.

It learns tick intervals and per-tick amounts from the combat log at runtime,
schedules the remaining ticks through expiry, and appends only the part of that
estimate that the native incoming number does **not** already explain. It never
modifies EllesmereUI files, frames, textures or functions — it creates one small
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

## Commands

All commands are `/euihot ...` (alias `/hotpred ...`).

| Command | Effect |
| --- | --- |
| `test <value>` | Show a fake `+value` segment after the native chain (session only, finite non-negative). |
| `test off` | Clear the fake segment. |
| `status` | One concise report: settings, CLEU access/registration, overlay structure, tracked HoTs, prediction. |
| `debug [on\|off]` | Toggle on-demand diagnostics (prints status when turned on). Debug lines are emitted on change, not per tick. |
| `enable on\|off` | Enable/disable the overlay. |
| `alpha <0..1>` | Overlay opacity (composited with the inherited native alpha). |
| `color <r> <g> <b>` | Set the custom overlay colour (0..1) and stop inheriting native style. |
| `color overlay <r> <g> <b>` | Same as above (explicit spelling). |
| `color native` | Restore the default: inherit native texture/colour. |
| `interval <spellID> <seconds>` | Manual interval calibration (persisted). Positive id, seconds in (0, 300]. |
| `spell add\|remove <spellID> [name]` | Register/remove a modified spell/rank ID at runtime. |
| `amountmode total\|effective` | CLEU adapter assumption (see below); resets learned magnitudes. |
| `excludehots on\|off` | Explicit excludes-HoTs overlap opt-in (see below). |
| `reset` | Clear session learning and invalidate the aura cache. |

Settings persist in `EllesmereUI_HoTPredictionDB`. A fake test value is **never**
persisted; a reload always starts with no fake active.

---

## How it works

Modules (loaded in TOC order): `Core.lua` (namespace, settings, events, slash,
diagnostics), `Api.lua` (defensive client/EllesmereUI adapters + aura cache),
`Spells.lua` (candidate IDs), `Learner.lua` (combat-log learning), `Model.lua`
(tick math + overlap), `Overlay.lua` (our bar, anchoring, combat deferral).

### CLEU (combat log) access
Modern clients deliver **no varargs** to `COMBAT_LOG_EVENT_UNFILTERED`; the
current event tuple is fetched with `CombatLogGetCurrentEventInfo()` and carried
as an explicit pack so nil holes and trailing `false` survive. A client that
instead delivers explicit varargs is handled by a documented legacy fallback.
The function's presence and the event registration result are recorded and shown
by `/status`. **If CLEU is unavailable, automatic tick learning is unavailable**
— the prototype still loads, but intervals/amounts must come from
`/euihot interval` or estimates are withheld.

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
  phase and never contributes a cross-refresh interval. The interval is a robust
  estimate over a bounded recent window (haste changes adapt; dropped ticks do
  not inflate the cadence).
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
  `ACTIVE_TALENT_GROUP_CHANGED`). Form changes do not destroy data. Only explicit
  `/euihot interval` calibrations persist.

### Ticks
Ticks are placed on the application grid (`expirationTime - duration`) or on the
last observed tick when it belongs to the current aura instance **and signature**.
Only future ticks at or before expiry are counted; the tick exactly at expiry is
included (tolerance 1e-6). For non-stacking HoTs the per-tick amount is the
learned total. Missing interval or amount => the estimate is withheld with a
reason.

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

`/euihot status` reports: settings; CLEU function and event-registration access
(with an explicit warning when automatic learning is unavailable); whether the
overlay frame exists with its real frame/hp names and references; the client
build from `GetBuildInfo`; each tracked active owned HoT with spell name, stacks,
expiry/duration, learned interval, remaining ticks and learned amount; the total
vs visible (clamped) prediction and the suppress reason. `/euihot debug on` adds
rich internals. Status formatting is pcall-protected. There are no automatic
chat prints except one useful startup failure line.

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
startup.

---

## Limitations

* Not verified in a live client; CLEU payload shape, `C_UnitAuras` filter support,
  native bar secrecy and the internal hook names vary by client/era.
* Requires native heal prediction enabled; v1 does not draw its own offset bars.
* **First tick(s) are delayed**: nothing is appended until an interval (and, for
  stacking families, the current stack count's magnitude) has been observed or
  calibrated.
* If CLEU is unavailable/forbidden, automatic estimation is unavailable; only
  explicit `/euihot interval` calibrations (with no learned magnitudes) apply.
* Default overlap is conservative and may under-predict during direct casts.
* Strength-varying HoTs are conservatively approximated.
* Secret/unavailable incoming, unknown/positive heal absorbs, a non-player/secret
  frame unit, or unreadable bar scaling suppress the overlay rather than guess.
* Haste-curve phase drift is approximated by the recent-window learned interval.
* Learning is per session (no persisted gear-dependent amounts).
