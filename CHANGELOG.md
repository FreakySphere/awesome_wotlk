# Changelog

## FreakySphere V2 — 2.0.0 (base: upstream v39)

Base moved from **Noname08662 v38** to **v39**. Everything FreakySphere added on top of v38 was re-applied
onto the new base, and every compatibility fix from V1 is preserved.

### Shipped defaults

The DLL registers each CVar with its initial value and `AwesomeCVar` mirrors it, so a fresh install and the
**Defaults** button agree. Changed in this build:

| CVar | Was | Now |
| --- | --- | --- |
| `cameraDistanceMax` | 15 | 50 |
| `cameraIndirectVisibility` | 0 | 1 |
| `uiHalfPixelFix` | 1 | 0 |
| `uiPixelSnap` | 1 | 0 |
| `uiTextureSampling` | 1 (box) | 0 (engine) |
| `portraitResolution` | 64 | 512 |
| `nameplateAlphaSpeed` | 0.25 | 1 |
| `nameplateClampMode` | 0 | 4 (bosses, all sides) |
| `nameplateClampViews` | 0 | 2 (top and sides) |
| `nameplateMouseFreezeGrace` | 0.15 | 1 |
| `nameplateMouseFreezeTime` | 0.3 | 1 |
| `nameplateHitboxWidthE` | 1 | 0.8 |
| `nameplateHitboxWidthF` | 1 | 0.65 |
| `tabTargetDistance` | 41 | 200 |
| `enableStancePatch` | 0 | 1 |

`MSDFOutlinePass` was the one CVar whose two defaults disagreed — the DLL shipped `0` (as upstream v39 does)
while the addon claimed `1`. The addon now says `0` as well, so the window, the Reset button and a fresh
client all match upstream.

`Flash` now ships with all five alerts on (party invite and ready check were off). `AwesomeCVar` hides its
minimap button by default. Both addons carry a `defaultsVersion` marker and move an install that still sits
on an old default onto the new one **once**; a value the user changed by hand is left alone.

### Added by the v39 base

- **LuaJIT** (`luaSwap`, default off, needs a restart) — replaces the Lua VM, 2.5–3× faster Lua.
- **World culling fixes** (`worldCullMode`) — doorway/window views and the terrain horizon, rewritten exactly;
  also stops the engine reading freed memory when many doorways are on screen.
- **Projected textures** (`projectedTextureMode`) and **ground-target clamp** (`groundTargetClamp`).
- **UI cooldown swipe fix** (`uiCooldownSwipeFix`) — swipes on nameplate-attached frames no longer vanish.
- **Tab-target distance** (`tabTargetDistance`, 41–200 yards).
- **Nameplate clamp views** (`nameplateClampViews`) — a clamped plate's unit stays alive and drawn off screen.
- **Clamp and freeze affiliations** (`nameplateClampModeAffiliation`, `nameplateMouseFreezeAffiliation`).
- **Two extra freeze modes** — "always, unless it is your target" and "in combat, unless it is your target".
- Internal: `WorldCull*`, `MiscGroundTargetClamp`, `MiscProjectedLayers`, `MiscInteraction`, `LuaSwap`,
  `ProjectedTexture`, `CMapChunk`/`CMapObjDef`/`MapObjData`, `CGSpellBook`, and a new call-site hook in
  `hookkit`.

### Kept from V1 (re-applied, not merged wholesale)

- Distance API — `GetDistanceForUnit/GUID/NamePlate`, `GetNamePlateForGUID`, `GetGUIDForNamePlate`,
  `GetNamePlatesDistance`, `GetNamePlatesDistanceList`.
- `enableStancePatch` CVar, default on.
- `NAME_PLATE_OWNER_CHANGED` event, now fired around v39's `bindEntry()`.
- `UnitIsFlagSilenced` + the argument-count `UnitIsSilenced` dispatcher. Upstream v39 still shadows the
  client's voice-chat query; this build keeps the dispatcher, so both call styles work.
- World queries — `UnitInLOS`, `UnitPosition`, `UnitFacing`, `AmBehind`, `UnitExistsGUID`,
  `TargetUnitByGUID`, `UnitGUIDByName`.
- `@focuslocation` / `@targetlocation`, re-expressed on v39's `CGWorldFrame::leftClickTerrain`.
- `C_NamePlate` carries the full KhalGH set as table members **and** globals, with the owner guard:
  a plate with no current owner reports `nil`, never `0x0000000000000000`.

### Fixed

- The plate-GUID contract from V1 is preserved on the new engine: `GetGUIDForNamePlate` and
  `GetDistanceForNamePlate` return nothing unless the entry is tracked and has an owner. This is the fix that
  stopped OPlates drawing "?" on neutral and hostile NPCs, and the one-frame "?" flash on camera moves.

### Changed

- `AwesomeWotlk` global **39 → 40**; `FreakySphere` global `"1.0.0"` → `"2.0.0"`. 39 now means "upstream v39".
- AwesomeCVar `MOD_VERSION` 39 → 40, toc version `3.1-freakysphere` → `4.0`; Flash toc version `2.0`.
- The patcher is unchanged: same three patch sites, same DLL name, so an already-patched `Wow.exe` keeps
  working and does not need to be patched again.

### Patcher

- **Two-button window.** Started without arguments it now shows *Patch client* / *Remove patch* instead of
  patching immediately. Titled **AwesomeWotLK Patcher**, centred on the work area, green Patch and red Remove
  (faded when the action is not available). Both rows span the full text width, and the window resizes to the
  status text and repaints the whole dialog after every layout change, so there is neither dead space nor a
  leftover strip where a button used to be. Command-line use (`AwesomeWotlkPatch.exe [--quiet] [--remove] [Wow.exe]`) is unchanged
  and still works for scripts and drag-and-drop.
- **`Wow.exe.bak`.** Patching saves a verified-clean copy first; *Remove patch* renames it back over `Wow.exe`,
  so an install can be undone. The backup is only ever taken from a client whose bytes are known-good — a
  patched file is never used as a backup, because the 32 bytes at `ScanDllStart` cannot be reconstructed.
- **"Use a clean Wow.exe…"** imports an untouched client as the backup, for installs patched by an older
  version that have no `.bak`.
- **Stale-backup guard.** If `Wow.exe.bak` comes from a different client build than the current `Wow.exe`
  (the game was updated in between), removal asks first instead of silently downgrading.
- **Guard bytes + atomic write**, from the audit: a foreign or already-modified executable is refused instead
  of overwritten, and the new file is written to a temporary sibling and renamed into place.

### Addons

- **AwesomeCVar** exposes all nine new v39 settings, each in the tab where it belongs, with the upstream
  translations for all nine locales.
- New **v39 tier**: on a v38 client the v39-only settings are visible but locked, with the reason shown —
  a control that silently does nothing is worse than one that says why.
- The two "no target" freeze modes are only offered on v39+; on v38 the radio is not created at all.
- Settings that need a restart (`luaSwap`) say so under the description.


## FreakySphere V1 — 1.0.0

Base: **Noname08662 awesome_wotlk v38**. Nothing from the older forks' nameplate code was merged.

### Added

- **Distance API** (ported from KhalGH, with Keoo888's data-table idea as background)
  - `GetDistanceForUnit(unitId)` → yards or nil
  - `GetDistanceForGUID(guid)` → yards or nil
  - `GetDistanceForNamePlate(frame)` → yards or nil
  - `GetNamePlateForGUID(guid)` → frame or nil
  - `GetGUIDForNamePlate(frame)` → guid string or nil
  - `C_NamePlate.GetNamePlatesDistance()` → `[frame] = yards`
  - `C_NamePlate.GetNamePlatesDistanceList()` → `{{nameplate=, distance=}, …}`, sorted nearest first
  - Unlike the KhalGH original these work for **any** unit in the object manager, not just nameplated ones.

- **`enableStancePatch` CVar** (ported from Hypopheria2k / CH33T4_test), default **1**
  - Writes `UNIT_FIELD_BYTES_2` byte 3 after a form spell lands, so `/cast Battle Stance` + `/cast Charge`
    works in one click.
  - Covers 14 forms: cat, travel, aquatic, bear, dire bear, tree of life, the three warrior stances,
    ghost wolf, moonkin, flight form, swift flight form, metamorphosis.
  - Exposed in `/awesome` → Other → Combat.

- **`NAME_PLATE_OWNER_CHANGED` event** (ported from the CH33T4_test family)
  - Fires when a plate keeps its token but is re-bound to another unit, after the token already resolves to
    the new owner. `UNIT_REMOVED` / `UNIT_ADDED` still fire as before.

- **`FreakySphere` global** = `"1.0.0"`.

- **World query API** (ported from srazdokunebil's fork — a Hypopheria2k descendant)
  - `UnitInLOS(unitId)` — is there a clear line of sight, eye to eye
  - `UnitPosition(unitId)` — world x, y, z
  - `UnitFacing(unitId)` — counter-clockwise radians in `[0, 2*pi)`
  - `AmBehind(unitId)` — are you in the target's rear hemisphere
  - `UnitExistsGUID(guid)` — exists by GUID (also accepts a unit token)
  - `TargetUnitByGUID(guid)` — target by GUID
  - `UnitGUIDByName(name)` — GUID from an exact unit name
  - Rebuilt on v38's typed wrappers (`math::trace`, `object_mgr::string2Guid`, `game_ui::target`) rather
    than the fork's raw address casts.

- **`@focuslocation` / `@targetlocation` macro conditionals** (ported from the same fork)
  - Cast a ground-targeted spell on your focus's or target's feet, alongside the existing `@cursor` and
    `@playerlocation`.

### Changed

- **`UnitIsSilenced` → `UnitIsFlagSilenced`.** 3.3.5a already has `UnitIsSilenced("name", "channel")` as a
  voice-chat query; every fork in this family overwrote it with a one-argument flag check, which broke the
  native function for real addons (Grid2's unit-popup mute menu among them). The flag check has its own name
  now and the client's `UnitIsSilenced` is untouched.
- `AwesomeWotlk` global bumped **38 → 39**, so an addon can test `AwesomeWotlk >= 39` for the new API.
- `AwesomeCVar` `MOD_VERSION` 38 → 39, toc version 3.0 → 3.1-freakysphere, title rebranded.
- Root CMake project renamed to `FreakySphereWotLK`. The DLL is still `AwesomeWotlkLib.dll` and the patcher
  is still `AwesomeWotlkPatch.exe`, so this is a drop-in replacement for a v38 install.

### Addons rebuilt

- **AwesomeCVar**
  - New **Features** tab listing every API group with an Available / Partial / Locked badge and the exact
    Lua names, so nothing the client exposes is invisible.
  - New **client-state banner** on the About and Features tabs plus a status pill in the title bar:
    green FreakySphere, amber another awesome_wotlk, red not patched.
  - Every control is now gated: locked ones are dimmed, disabled, and print the reason underneath
    ("Requires a patched client" / "Requires FreakySphere awesome_wotlk" / "This client does not provide it").
  - Red warning line naming the fix, shown whenever something is locked.
  - Unpatched clients show shipped defaults instead of blank rows, and `SetCVar` is refused outright so
    nothing is written into `Config.wtf` for a CVar the client does not implement.
  - New `Compat.lua` capability layer; feature probes read the API itself, so a future fork that ships the
    same functions keeps working without a new check.
  - `/awesome features` and `/awesome status`; the load message now prints the client state and how many
    groups are locked.
  - 46 new locale keys × 9 locales (299 keys total, all present).

- **Flash**
  - Rewritten from a 10-line event handler into a real addon with a settings window: master switch,
    combat start, whisper, party invite, ready check, a Test button and a Defaults button.
  - Same visual language and the same three-state banner as AwesomeCVar; locks itself when the client is
    unpatched and flashes nothing.
  - Localised into all 9 client locales via a single `Locales.lua` with English fallback.

### Cross-fork compatibility

Measured every Lua-visible symbol across all eleven forks (`_analysis/api_matrix.py`, namespace-aware) and
closed the gaps that matter to addons. The API surface is now a strict superset of every fork's.

- **`C_NamePlate.GetNamePlateForGUID`, `GetGUIDForNamePlate`, `GetDistanceForUnit`, `GetDistanceForGUID`,
  `GetDistanceForNamePlate` are now table members**, not globals only. KhalGH shipped them inside
  `C_NamePlate`; v38 kept only four table entries and this build had re-added the rest as globals, so an
  addon calling `C_NamePlate.GetGUIDForNamePlate(plate)` saw `nil`. That single missing name is what broke
  OPlates' automatic class icons. The globals stay as aliases.
- **`UnitIsSilenced` is now a dispatcher.** One argument runs the flag check every fork shipped; two
  arguments are forwarded verbatim to the client's own voice-chat query. This is why the rename to
  `UnitIsFlagSilenced` no longer costs compatibility: both spellings work, and Grid2 keeps working.
- **No gaps left in events** — all nine nameplate and TTS events were already registered.

Deliberately *not* done: the sixteen CVars belonging to the older CH33T4/Crum/somewirdhuman nameplate
engine (`nameplateXSpace`, `nameplateUpperBorder`, …), Hypopheria2k's `nameplateClampTop*` and
srazdokunebil's `nameplateShowITF`. Those configure an engine this build does not have; registering them
would produce settings that silently do nothing. They are absent rather than fake, and `SetCVar` on an
unknown name is harmless.

### Fixed

- **`GetGUIDForNamePlate` answered with the zero GUID for a plate that had no owner yet.** A plate slot is
  recycled: when it hides, its entry loses its owner and keeps `guid == 0` until the next track pass
  rebinds it. Both `GetGUIDForNamePlate` and `GetDistanceForNamePlate` returned that empty slot anyway.
  `"0x0000000000000000"` is not a harmless value — players are the only units whose GUID has a zero high
  half, so the usual `guid:sub(1, 6) == "0x0000"` player test reads an empty slot as a *player*. The visible
  effect, reported from OPlates: neutral and hostile **NPCs** flashed the "unknown player" question mark
  when a plate came into view, and a known player's class icon flickered to "?" for a few milliseconds on
  fast camera moves. Both functions now follow KhalGH's contract exactly (`Visible && entry.guid`): no
  answer unless the plate is tracked and has an owner.
- **AwesomeCVar crashed on every tab switch**: `UpdateDependencies` called `widget:Enable()` on every
  widget it tracked, but a `UIDropDownMenu` is a plain `Frame` in 3.3.5a and has no `Enable`/`Disable` at
  all. The Text to Speech voice dropdown was the first one hit, which aborted `selectTab` and left the
  window half-built. All widget state now goes through a guarded helper that uses the button API when it
  exists, `UIDropDownMenu_EnableDropDown` / `_DisableDropDown` for dropdowns, and falls back to
  `EnableMouse` for anything else.
- `UpdateAllUI` now wraps the state pass in `pcall` and reports a failure once in chat, so a single bad
  control can no longer take the whole window down.

### Unchanged (deliberately)

- v38's nameplate engine — physics stacking, five clamp modes, occlusion, mouse-freeze, hitbox anchoring.
- The pointer-range patch at `0x00D415B8` / `0x00D415BC`, and the `TOSAccepted` / `EULAAccepted` writes.
  Keoo888's fork reports the former as a session-break risk on Warmane; see README for the trade-off.
- `Spell.cpp`'s `GetSpellBaseCooldown` behaviour.

### Reviewed but not ported

From srazdokunebil's fork, examined and rejected:

- **`nameplateShowITF`** — keeps plate frames alive at alpha 0 so `C_NamePlate` works with nameplates hidden.
  The feature is sound, but its implementation drives `m_isShown` and suppresses `UNIT_REMOVED` inside that
  fork's older nameplate engine. v38 replaced that engine, so the port is not mechanical and would touch
  removal detection, draw order and mouse picking. Not worth the risk before the first in-game test;
  say the word and it goes in behind a default-off CVar.
- **`objectHighlightMode`** — v38 already has it, implemented with typed per-mode detours. Nothing to gain.
- **FT_Load_Glyph mono handling** — v38's version (`kLoadFlagsMono` + `renderMonoBitmap` + bearing
  re-anchor) is more complete than the fork's.
- **`nameplateClampTop` / `nameplateClampTopOffset`** — renames of v38's `nameplateClampMode` /
  `ClampModeVOffset`, which has five modes instead of three.
- **`UnitIsSilenced`** — the fork still carries the collision this build fixes.

### Verified

- All 823 hard-coded addresses resolve inside a stock 3.3.5a build-12340 `Wow.exe` (443 of them inside `.text`).
- No API name collides with a native 3.3.5a function any more (`UnitIsSilenced` was the only one).
- No symbol belongs to a later client version.
