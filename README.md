# EllesmereUI_HoTPrediction

A lightweight, standalone World of Warcraft addon that adds a **conservative
player self-cast HoT (heal-over-time) prediction segment** on top of the native
`EllesmereUIUnitFrames` incoming-heal prediction bars.

It learns tick intervals and per-tick amounts from the combat log at runtime,
schedules the remaining ticks through expiry, and appends only the part of that
estimate that the native incoming number does **not** already explain. It never
modifies EllesmereUI files, frames, or functions — it creates one small
StatusBar of its own and secure-hooks native callbacks read-only.

> Runtime status: this addon was developed and tested in a deterministic mocked
> environment. It has **not** been run inside a live WoW client here. Treat the
> behavior described as the implementation's intent; verify in game.

---

## Install

1. Copy the folder `EllesmereUI_HoTPrediction/` into your client's AddOns
   directory, e.g.
   `World of Warcraft/_retail_/Interface/AddOns/EllesmereUI_HoTPrediction/`
   (or the equivalent AddOns path for the Forever client).
2. `EllesmereUIUnitFrames` must be installed and enabled — it is a hard TOC
   dependency. Native heal prediction must be enabled for the target's player
   frame.
3. `/reload` or restart. Startup is silent. If the native prediction frame is
   not found you get exactly one message:
   `EllesmereUIUnitFrames prediction frame not found; overlay idle.`

The installed folder is the deliverable; there is no separate zip/binary.

## Commands

All commands are `/euihot ...` (alias `/hotpred ...`).

| Command | Effect |
| --- | --- |
| `test <value>` | Show a fake `+value` segment appended after the native chain (session only). |
| `test off` | Clear the fake segment. |
| `test3 <direct> <hot>` | Enable the explicit **excludes-HoTs** opt-in and fake `direct`/`hot`. Verifies `600 800 -> 1400`. |
| `status` | One concise report: settings, native refs, learned spells, last suppression reason. |
| `debug [on\|off]` | Toggle rich on-demand diagnostics (also prints status when turned on). |
| `alpha <0..1>` | Overlay opacity. |
| `color <my\|other\|overlay> <r> <g> <b>` | Colors in 0..1. `overlay` controls our appended segment. |
| `interval <spellID> <seconds>` | Manual interval calibration (persisted). Only use when you know the mechanic. |
| `spell add\|remove <spellID> [name]` | Register/remove a modified spell/rank ID at runtime. |
| `amountmode total\|effective` | CLEU adapter assumption (see below). |
| `excludehots on\|off` | Toggle the explicit excludes-HoTs overlap mode. |
| `reset` | Clear session learning (intervals/amounts). |

Settings persist in `EllesmereUI_HoTPredictionDB`. A fake test value is **never**
persisted; a reload always starts with no fake active.

---

## How it works

Modules (loaded in TOC order): `Core.lua` (namespace, settings, events, slash),
`Api.lua` (defensive client/EllesmereUI adapters), `Spells.lua` (candidate
IDs), `Learner.lua` (combat-log learning), `Model.lua` (tick math + overlap),
`Overlay.lua` (our bar, anchoring, combat deferral).

### Auras (self-cast only)
Reads `C_UnitAuras.GetAuraDataByIndex("player", i, "HELPFUL|PLAYER")` with a
fallback to `"HELPFUL"`, and a guarded legacy `UnitAura` adapter. An aura is
tracked only if its `spellId` is a known candidate and its `sourceUnit` is
`player`. Identity uses `auraInstanceID` (legacy uses spell ID); stacks use
`applications`; timing uses `expirationTime`/`duration`.

### Learning from the combat log
Listens for `SPELL_PERIODIC_HEAL` where `sourceGUID == destGUID == player` and
the spell ID is a candidate.

* **Interval**: inferred from consecutive ticks of the *same aura instance*
  only. Refresh (instance change) and gaps above 30s are ignored, and the most
  common delta bucket wins. No interval is ever invented.
* **Amount**: the recent average per-stack non-crit sample. `critical` samples
  and samples with `absorbed > 0` are skipped.
* **Adapter assumption**: by default the CLEU `amount` is taken as the **total
  including overheal**. `amountmode effective` uses `amount + overheal` for
  modified clients. There is no proof which the installed client reports, so
  this is an explicit, switchable assumption. Documented, not hidden.
* Learning is **session only** (avoids stale gear values). Only explicit
  `/euihot interval` calibrations persist.

### Ticks
Ticks are placed on the application grid (`expirationTime - duration`) or on the
last observed tick when it belongs to the current aura instance. Only future
ticks at or before expiry are counted; the tick exactly at expiry is included
(tolerance 1e-6). Per-tick amount is `perStackAverage * currentStacks`, so a
stack-inclusive observed amount is never multiplied by stacks a second time.
Missing interval or amount => the estimate is withheld with a reason.

### Overlap / double-counting (conservative by default)
The native API aggregate alone cannot prove whether it already includes HoTs, so
the default is deliberately conservative:

```
added = max(0, hotEstimate - nativeTotal)
```

`nativeTotal` = native "mine" + "others" when both are readable plain numbers.
This can under-predict during direct casts; that is accepted and documented.
The result is then clamped so native + added never exceeds missing health
(`maxHealth - health - nativeTotal`), floored at 0. If the native incoming
number is secret/unavailable, the real overlay is **suppressed** rather than
doing unsafe arithmetic. A positive/unknown heal absorb also suppresses.

For users who have verified their runtime reports direct and HoT healing
additively, `excludehots on` (or `test3`) appends the full HoT estimate:

```
added = hotEstimate      -- 600 direct + 800 hot => 1400 total
```

### Overlay rendering
Our own `StatusBar` is parented to the native `_missClip` (so it is clipped to
the health bar), anchored to the leading edge of the last shown native
prediction bar, and shares native orientation/reverse handling. It copies the
native texture and (optionally) color; `shareNativeStyle = false` uses
`overlayColor`. It uses the native bar's max for scaling. Frame replacement and
reloads are detected idempotently: one overlay, re-anchored, never duplicated.
All structural work (reparent, hook installation) is deferred out of combat and
applied on `PLAYER_REGEN_ENABLED`. Native elements are only read, and native
apply/layout functions are observed with `hooksecurefunc` — never replaced.

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
Growth's target-count-dependent tick strength is approximated per self tick and
flagged `approximate` in debug details.

---

## Tests

Deterministic Lua tests with a mocked WoW environment (frames, auras, CLEU,
secret-value sentinel that raises on any arithmetic, combat lockdown).

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

Success ends with `RESULT pass=.. fail=0 total=49` and exit code 0.

Coverage includes: no heals; `200x4=800`; `600+800=1400` excludes mode;
conservative subtract; clamp `4500/5000 incoming 300 => 200`; expiry; refresh
without duplicate ticks; foreign-caster filtering; full-health suppress and
display after damage; health-not-power; crit/absorbed/overheal semantics; stack
normalization; exact tick boundaries (including a tick at expiry); secret
timing/stacks/incoming; missing CLEU; native prediction off; frame replacement,
style, horizontal and vertical-reversed axes; command handling; combat-deferred
attach; session-only fake; quiet startup.

---

## Limitations

* Not verified in a live client; CLEU payload, `C_UnitAuras` filter support, and
  native bar secrecy vary by client/era.
* Requires native prediction enabled; v1 does not draw its own offset bars.
* Default overlap is conservative and may under-predict during direct casts.
* Intervals/amounts are only known after observing ticks; newly applied HoTs use
  previously learned data or wait.
* Learning is per session (no persisted gear-dependent amounts).
* Wild Growth (and other strength-varying HoTs) are approximated.
* Secret/unavailable incoming, positive heal absorbs, or unreadable bar scaling
  suppress the overlay rather than guess.
* Haste-curve phase drift is approximated by the learned interval.
