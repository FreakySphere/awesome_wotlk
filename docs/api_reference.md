[C_NamePlates](#c_nameplates) - [Distance](#distance-freakysphere) - [C_VoiceChat](#c_voicechat) - [Unit](#unit) - [World queries](#world-queries-freakysphere) - [Inventory](#inventory) - [Spell](#spell) - [Item](#item) - [UI](#ui) - [Misc](#misc)

# C_NamePlates
Backported C-Lua interfaces from retail  
All nameplates come with a `unit` field holding their `nameplateN` token string

## C_NamePlate.GetNamePlateForUnit `API`
**Arguments:** `unitId` (string)  
**Returns:** `namePlate` (frame)

Get nameplate by unitId.

```lua
frame = C_NamePlate.GetNamePlateForUnit("target")
```

## C_NamePlate.GetNamePlates `API`
**Arguments:** none  
**Returns:** `namePlateList` (table)

Get all visible nameplates.

```lua
for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
  -- something
end
```

## C_NamePlate.GetNamePlateByGUID `API`
**Arguments:** `guid` (string)  
**Returns:** `namePlate` (frame)

Get nameplate from UnitGUID, for example from combat log.

```lua
local nameplate = C_NamePlate.GetNamePlateByGUID(destGUID)
```

## C_NamePlate.GetNamePlateTokenByGUID `API`
**Arguments:** `guid` (string)  
**Returns:** `token` (string)

Get nameplate token from UnitGUID, for example from combat log.

```lua
local token = C_NamePlate.GetNamePlateTokenByGUID(destGUID)
local frame = C_NamePlate.GetNamePlateForUnit(token)
```

## C_NamePlate.GetNamePlateForGUID `API` `KhalGH`
**Arguments:** `guid` (string)  
**Returns:** `namePlate` (frame or nil)

Same as `C_NamePlate.GetNamePlateByGUID`. Both names exist so an addon written against either fork works.

```lua
local nameplate = C_NamePlate.GetNamePlateForGUID(destGUID)
```

## C_NamePlate.GetGUIDForNamePlate `API` `KhalGH`
**Arguments:** `nameplate` (frame)  
**Returns:** `guid` (string or nil)

A plate frame back to its GUID, formatted like `UnitGUID`. This is the only way to learn a plate's GUID
before you have ever hovered it, so it is what makes "show the class icon immediately" addons work.

```lua
local guid = C_NamePlate.GetGUIDForNamePlate(C_NamePlate.GetNamePlateForUnit("target"))
```

## C_NamePlate.GetNamePlatesDistance `API` `FreakySphere`
**Arguments:** none  
**Returns:** `distances` (table)

Every visible nameplate mapped to its distance from you in yards: `distances[plateFrame] = yards`.
Plates whose unit is not in the object manager are skipped.

```lua
for plate, yards in pairs(C_NamePlate.GetNamePlatesDistance()) do
  print(plate.unit, string.format("%.1f yd", yards))
end
```

## C_NamePlate.GetNamePlatesDistanceList `API` `FreakySphere`
**Arguments:** none  
**Returns:** `list` (table)

The same data as an array of `{nameplate = frame, distance = yards}`, **already sorted nearest first**.
Use this one when you just want "the closest mob".

```lua
local closest = C_NamePlate.GetNamePlatesDistanceList()[1]
if closest and closest.distance <= 8 then
  -- something is in melee range
end
```

## GetStackingEnabled `Method`
**Arguments:** none  
**Returns:** `enabled` (boolean)

Returns whether this nameplate currently takes part in stacking. True for every nameplate included by `nameplateStacking`, unless disabled with `SetStackingEnabled`.

```lua
print(string.format("Target nameplate is %s", C_NamePlate.GetNamePlateForUnit('target'):GetStackingEnabled() and "stacking" or "not stacking"))
```

## SetStackingEnabled `Method`
**Arguments:** `enabled` (boolean)  
**Returns:** none

Sets a per-nameplate stacking override. Call it from `NAME_PLATE_UNIT_ADDED`; `NAME_PLATE_CREATED` is too early.

```lua
for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
  nameplate:SetStackingEnabled(UnitName(nameplate.unit) == "Thatguy")
end
```

## GetOcclusionEnabled `Method`
**Arguments:** none  
**Returns:** `enabled` (boolean)

Returns whether line-of-sight occlusion alpha handling is enabled for this specific nameplate.

```lua
local isOccludedAlphaEnabled = C_NamePlate.GetNamePlateForUnit("target"):GetOcclusionEnabled()
```

## SetOcclusionEnabled `Method`
**Arguments:** `enabled` (boolean)  
**Returns:** none

Sets an override to enable or disable line-of-sight occlusion alpha handling on a per-nameplate basis.

```lua
for _, nameplate in pairs(C_NamePlate.GetNamePlates()) do
  nameplate:SetOcclusionEnabled(false)
end
```

## NAME_PLATE_CREATED `Event`
**Parameters:** `namePlateBase` (frame)

Fires when a nameplate object is initially created.

## NAME_PLATE_UNIT_ADDED `Event`
**Parameters:** `unitId` (string)

Fires when a nameplate becomes active and is attached to a unit.

## NAME_PLATE_UNIT_REMOVED `Event`
**Parameters:** `unitId` (string)

Fires when a nameplate is detached from a unit and is about to be hidden.

## NAME_PLATE_OWNER_CHANGED `Event` `FreakySphere`
**Parameters:** `unitId` (string)

Fires when a nameplate keeps its token but is re-bound to a **different unit** — the engine recycles plate
frames, so `nameplate7` can stop being one mob and become another. By the time this fires the token already
resolves to the new owner, so `UnitName(unitId)` and `UnitGUID(unitId)` return the new unit.

`NAME_PLATE_UNIT_REMOVED` still fires first and `NAME_PLATE_UNIT_ADDED` still follows, so addons written for
the old two-event behaviour keep working. This event exists so a display addon can refresh a plate *without*
tearing down and rebuilding its state.

```lua
local f = CreateFrame("Frame")
f:RegisterEvent("NAME_PLATE_OWNER_CHANGED")
f:SetScript("OnEvent", function(_, _, unit)
  print(unit, "now belongs to", UnitName(unit))
end)
```

## nameplateDistance `CVar`
**Arguments:** `distance` (number)  
**Default:** 41

Sets the display distance of nameplates in yards, up to **200**.

## nameplateStacking `CVar`
**Arguments:** `mode` (number)  
**Default:** 0

Defines the nameplate stacking behavior. 'Smart' mode allows nameplates to bypass the stacking push if there is sufficient space below, resulting in a tighter layout at the cost of more frequent rearrangements.
- **-3** = Friendly Only (Smart)
- **-2** = Enemy Only (Smart)
- **-1** = Enable All (Smart)
- **0** = Disabled (Overlapping)
- **1** = Enable All (Standard)
- **2** = Enemy Only (Standard)
- **3** = Friendly Only (Standard)

## nameplateMouseMode `CVar`
**Arguments:** `mode` (number)  
**Default:** 0

Defines nameplate mouse interaction and draw order. Click-through nameplates ignore the mouse. Raising draws the moused-over nameplate above all others except the target's; a raised nameplate that is frozen by `nameplateMouseFreeze` is drawn above the target's as well.
- **0** = Default
- **1** = Click-through enemies
- **2** = Click-through enemies; raise friendly plates on mouseover
- **3** = Click-through enemies; raise friendly plates on mouseover (in combat only)
- **4** = Click-through friendlies
- **5** = Click-through friendlies; raise enemy plates on mouseover
- **6** = Click-through friendlies; raise enemy plates on mouseover (in combat only)
- **7** = Raise any plate on mouseover
- **8** = Raise any plate on mouseover (in combat only)

## nameplateBandX `CVar`
**Arguments:** `width` (number)  
**Default:** 0.7

Horizontal stacking threshold, as a fraction of the nameplates' width: nameplates closer than this stack. Lower values allow more sideways overlap.

## nameplateBandY `CVar`
**Arguments:** `height` (number)  
**Default:** 1

Vertical spacing between stacked nameplates, as a fraction of their height.

## nameplateInertia `CVar`
**Arguments:** `mult` (number)  
**Default:** 1

Controls the physical weight of nameplate movement. Higher values increase responsiveness during stacking, while lower values make movement feel heavier and more damped.

## nameplatePlacement `CVar`
**Arguments:** `offset` (number)  
**Default:** 0

Raises or lowers nameplates relative to their unit, in yards (world units), in range **-1**-**2**.

## nameplateRaiseSpeed `CVar`
**Arguments:** `speed` (number)  
**Default:** 100

The velocity at which nameplates shift **upward** to resolve stacking conflicts.

## nameplateLowerSpeed `CVar`
**Arguments:** `speed` (number)  
**Default:** 100

The velocity at which nameplates shift **downward** to resolve stacking conflicts.

## nameplatePullSpeed `CVar`
**Arguments:** `speed` (number)  
**Default:** 50

The velocity at which nameplates shift **horizontally** to resolve stacking conflicts.

## nameplateHitboxAnchor `CVar`
**Arguments:** `anchor` (number)  
**Default:** 1

Sets where the clickable area sits within the nameplate when `nameplateHitboxHeightE`/`nameplateHitboxHeightF` is below 1; the width is always centered. Match it to where your nameplate addon draws the health bar (e.g. ElvUI anchors it by its top or bottom edge).
- **0** = Top  
- **1** = Center
- **2** = Bottom

## nameplateHitboxHeightF / nameplateHitboxWidthF `CVar`
**Arguments:** `scale` (number)  
**Default:** 1 (height), 0.65 (width)

Multipliers for the clickable hitbox dimensions of **friendly** nameplates.

## nameplateHitboxHeightE / nameplateHitboxWidthE `CVar`
**Arguments:** `scale` (number)  
**Default:** 1 (height), 0.8 (width)

Multipliers for the clickable hitbox dimensions of **enemy** nameplates.

## nameplateHysteresisDecay `CVar`
**Arguments:** `rate` (number)  
**Default:** 1

Controls how quickly stacking pairs dissolve once nameplates are no longer overlapping. Higher values cause faster separation; lower values keep pairs committed longer.

## nameplateRaiseDistance `CVar`
**Arguments:** `distance` (number)  
**Default:** 8

Sets the maximum vertical distance (as a ratio of plate height) a nameplate can be pushed from its origin.

## nameplatePullDistance `CVar`
**Arguments:** `distance` (number)  
**Default:** 0.25

Sets the maximum horizontal distance (as a ratio of plate width) a nameplate can be pulled from its origin.

## nameplateClampMode `CVar`
**Arguments:** `mode` (number)  
**Default:** 4

Restricts nameplates from moving beyond the screen boundaries.
- **0** = Disabled  
- **1** = Clamp All (Top Only)
- **2** = Clamp Bosses Only (Top Only)
- **3** = Clamp All (All Sides)
- **4** = Clamp Bosses Only (All Sides)

## nameplateClampModeVOffset `CVar`
**Arguments:** `offset` (number)  
**Default:** 0.01

Sets the margin from the top screen edge, and from the bottom edge in the all-sides modes (3 or 4), in range **0**-**0.05** (0.0 is the strict edge). Requires `nameplateClampMode` to be non-zero.

## nameplateClampModeHOffset `CVar`
**Arguments:** `offset` (number)  
**Default:** 0.01

Sets the margin from the left and right screen edges, in range **0**-**0.1** (0.0 is the strict edge). Requires `nameplateClampMode` to be set to a mode that includes all edges (3 or 4).

## nameplateClampModeFilter `CVar`
**Arguments:** `filter` (number)  
**Default:** 0

Restricts which nameplates `nameplateClampMode` applies to. Restrictions stack: a plate is clamped only when all of them hold. Plates that fail the filter behave as if clamping were disabled. Requires `nameplateClampMode` to be non-zero.
- **0** = No Restriction
- **1** = Target Only
- **2** = In Combat Only (player in combat)
- **3** = Target Only, In Combat Only

## nameplateClampModeAffiliation `CVar`
**Arguments:** `affiliation` (number)  
**Default:** 0

Restricts `nameplateClampMode` to enemy or friendly nameplates. A unit counts as friendly when its reaction to you is friendly, or neutral and you can't attack it; everything else counts as an enemy. Combines with the mode's boss restriction and with `nameplateClampModeFilter`: a plate is clamped only when all of them hold. Requires `nameplateClampMode` to be non-zero.
- **0** = All
- **1** = Enemies Only
- **2** = Friends Only

## nameplateClampViews `CVar`
**Arguments:** `mode` (number)  
**Default:** 2

Keeps a clamped plate alive after its unit's model leaves the screen past the chosen edges, as long as the unit is in front of the camera. The world cull drops a unit once its model is off screen, and the plate goes with it, so clamping alone only holds until then. This cvar runs extra world culls for the directions outside the screen, and a plate stays while its unit would be visible from one of them. Past any other edge and behind the camera nothing changes. Requires `nameplateClampMode` to be non-zero and `worldCullMode` to be on.
- **0** = Disabled
- **1** = Top Only
- **2** = Top and Sides

Mode 1 uses one extra direction, mode 2 three. A direction only costs anything while it holds a clamped, off-screen unit in range.

## nameplateMouseFreeze `CVar`
**Arguments:** `mode` (number)  
**Default:** 0

Pins the nameplate under the cursor at its current screen position. With `nameplateStacking` enabled, every other nameplate, bosses included, yields and stacks around it for as long as it stays frozen. Clicking keeps it frozen; dragging the camera or hovering another nameplate releases it immediately. `nameplateMouseFreezeAffiliation` limits it to enemy or friendly nameplates.
- **0** = Disabled
- **1** = Always
- **2** = In Combat Only (player in combat)
- **3** = Always, Except Target
- **4** = In Combat Only, Except Target

The Except Target modes never freeze your target's nameplate; clicking a frozen nameplate to target it releases it.

## nameplateMouseFreezeAffiliation `CVar`
**Arguments:** `affiliation` (number)  
**Default:** 0

Restricts `nameplateMouseFreeze` to enemy or friendly nameplates. A unit counts as friendly when its reaction to you is friendly, or neutral and you can't attack it; everything else counts as an enemy. Hovering a nameplate it skips still releases a frozen one, as hovering any other nameplate does. Requires `nameplateMouseFreeze` to be non-zero.
- **0** = All
- **1** = Enemies Only
- **2** = Friends Only

## nameplateMouseFreezeGrace `CVar`
**Arguments:** `seconds` (number)  
**Default:** 1

How long a frozen nameplate stays pinned after the cursor leaves it, in range **0**-**1**. Returning within this time keeps it frozen.

## nameplateMouseFreezeTime `CVar`
**Arguments:** `seconds` (number)  
**Default:** 1

Duration of the eased slide from the frozen position back to the stacked position, in range **0**-**2**, independent of the stacking speeds. **0** snaps back instantly. Below 50 FPS the slide takes proportionally longer.

## nameplateOcclusionMode `CVar`
**Arguments:** `mode` (number)  
**Default:** 0

Controls when `nameplateOcclusionAlpha` applies. Has no effect while `nameplateOcclusionAlpha` is 1 or -1.
- **0** = Always
- **1** = Only out of combat (also skips the line-of-sight checks in combat)

## nameplateOcclusionAlpha `CVar`
**Arguments:** `alpha` (number)  
**Default:** 1.00

Sets the opacity of nameplates whose unit is out of line of sight (blocked by objects or terrain), in range **-1.0**-**1.0**. Your target's nameplate is never affected. **1** or **-1** turns occlusion off.
- **Positive values:** multiply the nameplate's normal opacity.
- **Negative values:** cap the opacity at the absolute value (e.g. -0.3 = at most 30%).

## nameplateNonTargetAlpha `CVar`
**Arguments:** `alpha` (number)  
**Default:** 0.50

Sets the opacity of all nameplates except the target's. Applies only while you have a target.

## nameplateAlphaSpeed `CVar`
**Arguments:** `speed` (number)  
**Default:** 1

How quickly nameplates fade to a new opacity (from `nameplateOcclusionAlpha` or `nameplateNonTargetAlpha`), in range **0.01**-**1**, where **1** is instant.

---

# Distance `FreakySphere`

Straight-line distance in yards between you and a unit. One world unit is one yard, so the numbers match what
a range addon would otherwise have to guess from spell ranges.

Unlike the KhalGH original these do **not** require the target to have a nameplate — any unit the object
manager knows answers, which is what makes them usable for target, focus, party and raid frames too.

All of them return `nil` when the unit does not exist or is out of the client's object range.

## GetDistanceForUnit `API`
**Arguments:** `unitId` (string)  
**Returns:** `yards` (number or nil)

```lua
local d = GetDistanceForUnit("target")
if d and d < 8 then print("melee range") end
```

## GetDistanceForGUID `API`
**Arguments:** `guid` (string)  
**Returns:** `yards` (number or nil)

Same as above, but by GUID — useful for a unit you only know from the combat log.

```lua
local yards = GetDistanceForGUID(destGUID)
```

## GetDistanceForNamePlate `API`
**Arguments:** `nameplate` (frame)  
**Returns:** `yards` (number or nil)

Same, but takes a nameplate frame (the `self` you get in a nameplate method).

Returns nothing unless the plate is currently tracked and its owner is resolved — the same contract as
KhalGH's fork. A recycled plate slot has no owner for a frame or two; a number for it would be the
*previous* occupant's distance.

```lua
local yards = GetDistanceForNamePlate(C_NamePlate.GetNamePlateForUnit("target"))
```

## GetNamePlateForGUID `API`
**Arguments:** `guid` (string)  
**Returns:** `namePlate` (frame or nil)

Global alias of `C_NamePlate.GetNamePlateForGUID`. Both the table member and the global exist, because
KhalGH put them in the table while later forks exposed only the global form.

## GetGUIDForNamePlate `API`
**Arguments:** `nameplate` (frame)  
**Returns:** `guid` (string or nil)

The reverse direction: a plate frame back to its GUID, formatted like `UnitGUID`. Also available as
`C_NamePlate.GetGUIDForNamePlate`.

Returns **nothing** unless the plate is currently tracked and has an owner. That is KhalGH's contract,
and it matters: a plate slot is recycled, and between two occupants it has no GUID at all. Answering
`"0x0000000000000000"` in that window is not harmless — players are the only units whose GUID has a zero
high half, so `guid:sub(1, 6) == "0x0000"` (the usual player test) reads the empty slot as a *player*, and
an addon draws its "unknown player" icon on whatever NPC just took the slot.

```lua
local guid = GetGUIDForNamePlate(C_NamePlate.GetNamePlateForUnit("target"))
```

---

# C_VoiceChat
Windows SAPI-backed Text-to-Speech backport from retail

## C_VoiceChat.GetTtsVoices `API`
**Arguments:** none  
**Returns:** `voiceList` (table) → `{ { voiceID = number, name = string }, ... }`

Returns all locally available TTS voices.

```lua
for _, v in ipairs(C_VoiceChat.GetTtsVoices()) do
  print(v.voiceID, v.name)
end
```

## C_VoiceChat.GetRemoteTtsVoices `API`
**Arguments:** none  
**Returns:** `voiceList` (table)

Same as `GetTtsVoices()`.

## C_VoiceChat.SpeakText `API`
**Arguments:**
- `voiceID` (number)
- `text` (string)
- `destination` (number, optional, default=1)
- `rate` (number, optional)
- `volume` (number, optional)

**Returns:** none

Speaks text asynchronously. Utterances are queued and played in order (FIFO); their `utteranceID` is reported through the playback events.
- `destination = 1` → local playback
- `destination = 4` → accepted, played the same way; any other value is treated as 1

```lua
C_VoiceChat.SpeakText(1, "Hello World", 1, 0, 100)
```

## C_VoiceChat.StopSpeakingText `API`
**Arguments:** none  
**Returns:** none

Stops all queued or currently playing utterances.

## C_TTSSettings.GetSpeechRate `API`
**Arguments:** none  
**Returns:** `rate` (number) [-10..10]

## C_TTSSettings.GetSpeechVolume `API`
**Arguments:** none  
**Returns:** `volume` (number) [0..100]

## C_TTSSettings.GetSpeechVoiceID `API`
**Arguments:** none  
**Returns:** `voiceID` (number)

## C_TTSSettings.GetVoiceOptionName `API`
**Arguments:** none  
**Returns:** `voiceName` (string)

## C_TTSSettings.SetDefaultSettings `API`
**Arguments:** none  
**Returns:** none

Resets to defaults: voice=1 (if available), rate=0, volume=100.

## C_TTSSettings.SetSpeechRate `API`
**Arguments:** `rate` (number) [-10..10]  
**Returns:** none

## C_TTSSettings.SetSpeechVolume `API`
**Arguments:** `volume` (number) [0..100]  
**Returns:** none

## C_TTSSettings.SetVoiceOption `API`
**Arguments:** `voiceID` (number)  
**Returns:** none

## C_TTSSettings.SetVoiceOptionByName `API`
**Arguments:** `voiceName` (string)  
**Returns:** none

## C_TTSSettings.RefreshVoices `API`
**Arguments:** none  
**Returns:** none

Refreshes the voice list.  
Fires `VOICE_CHAT_TTS_VOICES_UPDATE` if the list has changed.

## VOICE_CHAT_TTS_PLAYBACK_STARTED `Event`
**Parameters:** `numConsumers` (number), `utteranceID` (number), `durationMS` (number), `destination` (number)

Fired when SAPI starts playback.  
`durationMS` is always **0**.

## VOICE_CHAT_TTS_PLAYBACK_FINISHED `Event`
**Parameters:** `numConsumers` (number), `utteranceID` (number), `destination` (number)

Fired when SAPI finishes playback.

## VOICE_CHAT_TTS_PLAYBACK_FAILED `Event`
**Parameters:** `status` (string), `utteranceID` (number), `destination` (number)

Fired if `SpeakText()` or setup fails (e.g., no voice/device available).

## VOICE_CHAT_TTS_SPEAK_TEXT_UPDATE `Event`
**Parameters:** `status` (string), `utteranceID` (number)

Unused placeholder.

## VOICE_CHAT_TTS_VOICES_UPDATE `Event`
**Parameters:** none

Fired when the enumerated voice list changes.

## ttsVoice `CVar`
**Arguments:** `voiceID` (number)  
**Default:** 1

Sets the active voice.

## ttsSpeed `CVar`
**Arguments:** `rate` (number) [-10..10]  
**Default:** 0

Controls the speech rate.

## ttsVolume `CVar`
**Arguments:** `volume` (number) [0..100]  
**Default:** 100

Controls the speech volume.

---

# Unit

## UnitIsControlled `API`
**Arguments:** `unitId` (string)  
**Returns:** `isControlled` (boolean)

Returns true if the unit is under hard crowd control.

## UnitIsDisarmed `API`
**Arguments:** `unitId` (string)  
**Returns:** `isDisarmed` (boolean)

Returns true if the unit is disarmed.

## UnitIsFlagSilenced `API`
**Arguments:** `unitId` (string)  
**Returns:** `isSilenced` (boolean)

Returns true if the unit carries the `UNIT_FLAG_SILENCED` flag (a school lockout such as a kicked cast).

## UnitIsSilenced `API` `compat`
**Arguments:** `unitId` (string) — or — `name` (string), `channel` (string)  
**Returns:** `isSilenced` (boolean) — or — whatever the client's voice-chat query returns

3.3.5a already has `UnitIsSilenced("name", "channel")` as a voice-chat query. Every fork in this family
overwrote it with a one-argument silence check, which broke Grid2's unit-popup mute menu. FreakySphere
installs a dispatcher that honours both contracts by argument count:

```lua
UnitIsSilenced("target")             -- flag check, the behaviour the old forks shipped
UnitIsSilenced("player", "party")    -- forwarded to the client's own voice-chat query
```

The original is captured on first install and forwarded verbatim, so nothing that called the native form
changes behaviour. `UnitIsFlagSilenced` remains the unambiguous name for the flag check.

## UnitOccupations `API`
**Arguments:** `unitID` (string)  
**Returns:** `npcFlags` (number)

Returns the NPC occupation flags bitmask for the specified unit. Returns nothing if `unitID` is invalid or cannot be resolved.

`npcFlags` is a combination of these flags:
- `0x00000001` — Gossip
- `0x00000002` — Questgiver
- `0x00000004` — Unknown flag
- `0x00000008` — Unknown flag
- `0x00000010` — Trainer
- `0x00000020` — Class trainer
- `0x00000040` — Profession trainer
- `0x00000080` — Vendor
- `0x00000100` — Ammo vendor
- `0x00000200` — Food vendor
- `0x00000400` — Poison vendor
- `0x00000800` — Reagent vendor
- `0x00001000` — Repairer
- `0x00002000` — Flight master
- `0x00004000` — Spirit healer
- `0x00008000` — Spirit guide
- `0x00010000` — Innkeeper
- `0x00020000` — Banker
- `0x00040000` — Petitioner
- `0x00080000` — Tabard designer
- `0x00100000` — Battlemaster
- `0x00200000` — Auctioneer
- `0x00400000` — Stable master
- `0x00800000` — Guild banker
- `0x01000000` — Spell click
- `0x02000000` — Player vehicle
- `0x04000000` — Mailbox

## UnitOwner `API`
**Arguments:** `unitID` (string)  
**Returns:** `ownerName` (string), `ownerGuid` (string)

Returns owner name and GUID if passed a valid unitID, otherwise returns nothing.

## UnitTokenFromGUID `API`
**Arguments:** `GUID` (string)  
**Returns:** `UnitToken` (string)

Returns unit token if passed a valid GUID, otherwise returns nothing.

---

# World queries `FreakySphere`

Geometry the client already knows but never exposed: line of sight, position, facing, and who is behind
whom. All of these read the object manager directly and return nothing when the unit is not in range.

## UnitInLOS `API`
**Arguments:** `unitId` (string)  
**Returns:** `visible` (1 or nothing)

Returns `1` when nothing solid stands between you and the unit, measured roughly eye to eye. Returns
nothing when the line is blocked, so `if UnitInLOS("target") then … end` reads naturally.

```lua
if not UnitInLOS("target") then print("no line of sight") end
```

## UnitPosition `API`
**Arguments:** `unitId` (string)  
**Returns:** `x` (number), `y` (number), `z` (number)

World coordinates. Useful for range and geometry addons that want more than "yards away".

```lua
local x, y, z = UnitPosition("target")
```

## UnitFacing `API`
**Arguments:** `unitId` (string)  
**Returns:** `facing` (number)

Counter-clockwise radians, normalised to `[0, 2*pi)` — the same contract as the retail function.

## AmBehind `API`
**Arguments:** `unitId` (string)  
**Returns:** `behind` (boolean)

True when you stand in the rear hemisphere of the unit. **Only answers for your current target** — any
other token returns `false`. That restriction is deliberate and comes from the original implementation;
in practice you always call it as `AmBehind("target")`.

```lua
if AmBehind("target") then
  -- backstab is usable
end
```

## UnitExistsGUID `API`
**Arguments:** `GUID` (string)  
**Returns:** `exists` (1 or nothing)

Like `UnitExists`, but by GUID. Also accepts a unit token, since the same resolver handles both.

```lua
if UnitExistsGUID(destGUID) then print("still in range") end
```

## TargetUnitByGUID `API`
**Arguments:** `GUID` (string)  
**Returns:** nothing

Targets the unit behind a GUID. This is the same engine call `TargetUnit()` makes — it does not bypass
anything, it just saves you the `UnitTokenFromGUID` round trip. Accepts a unit token too.

```lua
TargetUnitByGUID(destGUID)
```

## UnitGUIDByName `API`
**Arguments:** `name` (string)  
**Returns:** `guid` (string or nothing)

Scans the object manager for a unit with that exact name and returns its GUID. Useful when you have a
name from chat or a combat log line and nothing else.

```lua
local guid = UnitGUIDByName("Ragnaros")
```

---

# Inventory

## GetInventoryItemTransmog `API`
**Arguments:** `unitId` (string), `slot` (number)  
**Returns:** `itemId` (number), `enchantId` (number)

Returns information about item transmogrification.

---

# Spell

## GetSpellBaseCooldown `API`
**Arguments:** `spellId` (number or string)  
**Returns:** `cdMs` (number), `gcdMs` (number)

Returns cooldown and global cooldown in milliseconds if passed a valid spellId, otherwise returns nothing.

---

# Item

## GetItemInfoInstant `API`
**Arguments:** `itemId/itemName/itemHyperlink` (string or number)  
**Returns:** `itemID` (number), `itemType` (string), `itemSubType` (string), `itemEquipLoc` (string), `icon` (string), `classID` (number), `subclassID` (number)

Returns ID, type, subtype, equipment slot, icon, class ID, and subclass ID. Raises an error if the item is not in the client's item cache.

---

# UI

## uiHalfPixelFix `CVar`
**Arguments:** `enabled` (boolean)  
**Default:** 0

Fixes the engine's half-pixel offset, which shifts the whole UI off the pixel grid and slightly blurs textures drawn at their native size.

## uiTextureSampling `CVar`
**Arguments:** `mode` (number)  
**Default:** 0

Improves sampling of UI textures drawn smaller than their native size, so thin borders and fine details no longer flicker or get swallowed. With multisampling at 1x (`gxMultisample` 1), `uiPixelSnap` should be enabled as well.
- **0** = Default client behavior
- **1** = Box (sharper)
- **2** = Tent (smoother)

## uiPixelSnap `CVar`
**Arguments:** `enabled` (boolean)  
**Default:** 0

Snaps UI elements to whole pixels, keeping edges crisp at any UI scale.

## uiCooldownSwipeFix `CVar`
**Arguments:** `enabled` (boolean)  
**Default:** 1

Cooldown swipes on frames attached to a nameplate, such as aura icons from a nameplate addon, no longer disappear while the nameplate moves.

---

# Misc

## cameraFov `CVar`
**Arguments:** `value` (number)  
**Default:** 100

Changes the camera field of view (fisheye effect), in range **90**-**150**.

## cameraIndirectVisibility `CVar`
**Arguments:** `enabled` (number)  
**Default:** 1

Toggles camera behavior when doodads such as trees or props block the view.
- **0** = Default client behavior (the camera zooms in)
- **1** = The camera passes through them and fades them out to `cameraIndirectAlpha`. Buildings and terrain still block the camera.

## cameraIndirectAlpha `CVar`
**Arguments:** `alpha` (number)  
**Default:** 0.6

Opacity that obstructing objects fade to when `cameraIndirectVisibility` is enabled (1 = fully opaque), in range **0.6**-**1**.

## showPlayer `CVar`
**Arguments:** `show` (boolean)  
**Default:** 1

Toggles rendering of your own character model.

## interactionMode `CVar`
**Arguments:** `mode` (number)  
**Default:** 1

Selects which target the interaction keybind and `/interact` pick.  
- **1** = Interaction is limited to entities in front of the player within the angle defined by `interactionAngle` and within 20 yards  
- **0** = Interaction occurs with the nearest entity within 20 yards, regardless of direction

In both modes, interaction cycles through nearby lootable targets when triggered repeatedly. NPCs and gathering nodes are not cycled among themselves, but the closest NPC or gathering node is included in the cycle alongside lootable targets.

## interactionAngle `CVar`
**Arguments:** `angle` (number)  
**Default:** 60

The size of the cone-shaped area in front of the player (in degrees, **15**-**160**) within which a mob or entity must be located to be eligible for interaction.  
Only used if `interactionMode` is set to 1 (default).

## interactionHighlight `CVar`
**Arguments:** `highlight` (boolean)  
**Default:** 1

Toggles the highlight on the object or unit the interaction keybind would currently interact with.

## MSDFMode `CVar`
**Arguments:** `mode` (number)  
**Default:** 1

MSDF-based font rendering uses vector distance data instead of rasterized textures, allowing crisp, high-quality text at any scale with minimal blurring or aliasing. Applies to all in-game text, except fonts set with the `MONOCHROME` flag, which keep the default rendering by design. Requires a client restart.

- **0** = Disabled
- **1** = Enabled
- **2** = Enabled, including unsafe fonts: fonts that fail the compatibility check (self-intersecting contours, e.g. 'diediedie') are converted too and may render incorrectly. Mode 1 leaves them on the default rendering.

Each character is generated the first time it appears in a font, which can cause a brief stutter, and is then saved to a disk cache in `Cache_AwesomeWotLK\Fonts\<locale>\` that is kept across game launches, so each character is generated only once. Every font, and every style of it (such as Bold), has its own cache folder, kept separately for each game locale.

Type `/msdfpregen` (available while MSDF is enabled) to fill the cache in advance. It opens a console window that lists the fonts loaded by the game and every font under `Interface\AddOns`; choose fonts, a range (option 1 = the standard range for your locale, option 2 = a custom range) and a CPU limit, and their glyphs are generated and written to the cache. On Chinese and Korean clients (zhCN, zhTW, koKR) this is mandatory: a font is rendered with MSDF only after at least its standard range (option 1) has been pre-generated; until then, it keeps the default rendering.

## MSDFOutlinePass `CVar`
**Arguments:** `enabled` (number)  
**Default:** 0

Draws MSDF font outlines in a separate pass so they don't overlap neighboring characters. Disabling it draws text and outline in one pass, which halves the vertex count but can leave outline artifacts between tightly packed characters.

## objectHighlightMode `CVar`
**Arguments:** `mode` (number)  
**Default:** 0

Forces the loot sparkle on interactive world objects (containers, gathering nodes, quest objects, bounty boards, etc.).

- **0** = Disabled
- **1** = Everything
- **2** = Tracked — containers and other usable objects; gathering nodes only while they are tracked on the minimap; quest-giver objects (bounty boards, wanted posters) only while they show a quest marker. Low-level quests show their marker only while the minimap's *Low Level Quests* tracking is on

## portraitResolution `CVar`
**Arguments:** `resolution` (number)  
**Default:** 512

Sets the texture resolution used to render 3D unit portraits. Accepts values between **64** and **2048** (rounded up to the nearest power of two). Each portrait uses its own texture of this size.

## projectedTextureMode `CVar`
**Arguments:** `mode` (number)  
**Default:** 1

Stops selection circles, AoE targeting circles and M2 ground decals from being cut off on steep terrain. The engine paints these onto the ground only within a fixed height range above and below their center, so on a slope the parts that fall outside it are cut off; this mode grows that range.

- **0** = Default client behavior
- **1** = Enabled

## groundTargetClamp `CVar`
**Arguments:** `enabled` (number)  
**Default:** 1

Hovering past a ground-targeted spell's maximum range keeps the targeting circle at the edge of that range, on the cursor's line, and a click casts there. Hovers far past the range and the sky keep the default out-of-range behavior. Below a spell's minimum range the circle is pushed out to it the same way. Based on the retail client.

## tabTargetDistance `CVar`
**Arguments:** `distance` (number)  
**Default:** 200

Sets the tab-targeting range in yards, between **41** and **200**.

## worldCullMode `CVar`
**Arguments:** `mode` (number)  
**Default:** 1

Replaces two parts of the engine's world culling, which decides what gets drawn, with exact reimplementations that fix their bugs: the portal walk (the view through the doorways and windows of buildings) and the terrain horizon test (what lies behind hills). Creatures and objects just behind a ridge are no longer hidden or shown by mistake, and the walk no longer reads freed memory when many doorways are on screen. A few smaller engine fixes come with it: WMO groups whose box grew while their doodads loaded are bucketed again on the grown box, invisible carriers (missiles, effects) no longer keep last frame's visibility, and an overflowing distance bucket no longer drops the groups after it. The replacements also run slightly faster than the engine's own culling.

- **0** = Default client behavior
- **1** = Enabled

## luaSwap `CVar`
**Arguments:** `enabled` (number)  
**Default:** 0

Replaces the game's Lua VM, which runs every addon and the default UI, with LuaJIT 1.1.8, a just-in-time compiler. Lua code runs 2.5-3 times faster than on the stock VM. Read once at client start, so changing it requires a client restart.

Addons run unchanged, and taint and secure execution behave as on the stock VM. Only the main thread is compiled, and coroutines stay interpreted. While the in-game profiler (`scriptProfile`) is on, the JIT compiler doesn't start at all: every function runs interpreted, so there is no speedup, `/console scriptProfile 0`, then `/reload` turns in-game profiler off. The VM is based on Lua 5.1.5 instead of the client's 5.1.1, so some error message texts and the iteration order of `pairs` over number keys can differ.

**Risk:** the swap hooks the game's Lua functions. A server whose Warden anti-cheat checks those functions could detect it, so use it at your own risk.

## chatLogSessionKey / combatLogSessionKey `CVar`
**Arguments:** `enabled` (boolean)  
**Default:** 1

Prefixes the chat/combat log file name with the client launch time (e.g. `Logs\2026-10-05-18.30.00 WoWCombatLog.txt`), so every launch is logged to a new file. Disable if a log uploader expects the default file name.

## cursor `macro`

Backported `cursor` macro conditional for quick-casting AoE spells at cursor position.

```
/cast [@cursor] Blizzard
/cast [target=cursor] Flare
```

## playerlocation `macro`

Implemented `playerlocation` macro conditional for quick-casting AoE spells at player location.

```
/cast [@playerlocation] Blizzard
/cast [target=playerlocation] Flare
```

## focuslocation `macro` `FreakySphere`
## targetlocation `macro` `FreakySphere`

The same trick aimed at another unit's feet: cast a ground-targeted spell on your focus or your target
instead of on yourself or the cursor. Ported from srazdokunebil's fork.

```
/cast [@focuslocation] Blizzard
/cast [@targetlocation] Flare
```

The click happens at the unit's current position, so if it moves during the cast the spell still lands
where it stood when you pressed the button.

## enableStancePatch `CVar` `FreakySphere`
**Arguments:** `enabled` (boolean)  
**Default:** 1

3.3.5a does not refresh `UNIT_FIELD_BYTES_2` byte 3 — the active shapeshift form — after a form spell lands,
so the next line of the same macro is still evaluated against the form you just left:

```
/cast Battle Stance
/cast Charge          -- "you are in the wrong stance"
```

With this on, the form the cast just switched to is written immediately, so the macro works in one click.
Covers cat / travel / aquatic / bear / dire bear / tree of life, the three warrior stances, ghost wolf,
moonkin, flight form, swift flight form and metamorphosis.

It is a descriptor write, so it ships **on** in FreakySphere; turn it off with `/console enableStancePatch 0`
or from the Combat section of `/awesome`.

## FlashWindow `API`
**Arguments:** none  
**Returns:** none

Starts flashing the game window icon in the taskbar.

## IsWindowFocused `API`
**Arguments:** none  
**Returns:** `focused` (boolean)

Returns 1 if the game window is focused, otherwise returns nil.

## FocusWindow `API`
**Arguments:** none  
**Returns:** none

Brings the game window to the foreground.

## CopyToClipboard `API`
**Arguments:** `text` (string)  
**Returns:** none

Copies text to the clipboard.

## CaptureFrame `API`
**Arguments:** `frame` (Frame), `size` (number or string, optional)  
**Returns:** none

Renders `frame` and everything parented to it (child frames, textures, text, 3D models, cooldowns, scroll children) off-screen and saves it as a PNG with a transparent background, cropped to the pixels actually drawn, to `Screenshots\FrameCapture_<Name>_<YYYYMMDD>_<HHMMSS>_<ms>.png`. The name keeps only letters, digits and `_`; unnamed frames are saved as `Anonymous`.

`size` sets how large the frame is rendered:
- a number, or a string of digits (`2048`) = target length of the longer side in pixels (approximate: it is measured from the frames' rectangles, while the image is cropped to what is drawn). A bare `2` means 2 pixels, not twice the size; use `2x` for that
- a string ending in `x` (`"2x"`, `"0.5x"`) = multiple of the frame's on-screen size
- omitted = on-screen size (`1x`)

The scale is clamped to at least **0.25x** and to what the GPU and memory allow; the chat message mentions it when it was reduced. The upper limit applies to the whole game window, which is rendered at that scale, so it doesn't depend on the frame's size: about **4x** at 1920×1080 and **2x** at 3840×2160. Only what lies inside the game window is captured; parts of the frame off-screen are cut off. Edges are antialiased with up to 8x MSAA. Text enlarged past 1x stays sharp only with `MSDFMode` enabled; default font rendering is upscaled and looks blurry.

The capture is asynchronous: it is taken on the next rendered frame and its result (file name, image size, scale, MSAA level, or the reason it failed) is printed to chat. Calling it again before then replaces the pending capture, and a pending capture is dropped on logout. `WorldFrame` can't be captured, and a hidden or zero-size frame fails with a message.

The slash command `/fcapture` (or `/framecapture`) `[FrameName] [size]` calls it, with the arguments in any order. Without a name it captures the mouse-enabled frame under the cursor; frames that ignore the mouse, such as `ChatFrame1`, have to be named (`/fstack` shows frame names).

```lua
CaptureFrame(PlayerFrame)          -- on-screen size
CaptureFrame(PlayerFrame, "2x")    -- twice the on-screen size
CaptureFrame(ChatFrame1, 2048)     -- longer side about 2048 pixels, if the scale limit allows it
```
```
/fcapture
/fcapture PlayerFrame 2x
/fcapture ChatFrame1 2048
```

## AwesomeWotlk `Global`
**Type:** number

The mod's version, or `nil` if the mod is not loaded. AwesomeCVar compares it with the version it was made for and suggests updating whichever is older.

```lua
if AwesomeWotlk then print("Awesome WotLK version", AwesomeWotlk) end
```

## QueueInteract `API`
**Arguments:** `unitId` (string, optional)  
**Returns:** none

Interacts with the current interaction target, or with `unitId` if given. This is what the interaction keybind and `/interact` call.
