<div align="center">

# awesome_wotlk — FreakySphere

**A superset build of [awesome_wotlk](https://github.com/noname08662/awesome_wotlk) for World of Warcraft 3.3.5a (build 12340).**

![Client](https://img.shields.io/badge/client-3.3.5a%20%C2%B7%2012340-4a90d9?style=flat-square)
![API level](https://img.shields.io/badge/API%20level-40-2ea44f?style=flat-square)
![Licence](https://img.shields.io/badge/licence-GPL--3.0-blue?style=flat-square)

[![Addon developer reference](https://img.shields.io/badge/%F0%9F%93%96_ADDON_DEVELOPER_REFERENCE-OPEN_EVERY_API,_CVAR_%26_EVENT-2ea44f?style=for-the-badge)](docs/api_reference.md)

</div>

---

## Why this build exists

`awesome_wotlk` patches the 3.3.5a client so addons can do things the stock client never allowed: address
nameplates, measure distance, ask for line of sight, render vector text. It started with **FrostAtom** and was
forked a dozen times since, each fork adding something — and each one drifting from the others.

**None of them is a superset of the rest.** The biggest (Noname08662) is missing the distance API and the
stance fix. The most nameplate-focused (KhalGH) has no stacking, no MSDF, no TTS. So an addon written for one
fork breaks on another, and players have to pick which features they want to live without.

This build takes the strongest base and **ports back the handful of features that only exist elsewhere**,
without merging anyone's nameplate engine. The result is a client that runs an addon written for *any* fork.

## How it was built

1. **Base:** Noname08662 **v39** — the from-scratch C++20 rewrite with the modern nameplate engine, MSDF fonts,
   frame capture and the v39 culling/targeting fixes.
2. **Audit:** every `.cpp`/`.h` in twelve other repositories was parsed, and every contested symbol was grepped
   in the *shipped* DLL — source can lie, the binary cannot. Each symbol was then checked against the native
   3.3.5a API to separate "missing feature" from "already exists" from "retail-only".
3. **Port, never merge:** only the genuine gaps were re-implemented on top of v39. The older forks' nameplate
   code is strictly weaker; dropping it in would have replaced a working engine with a worse one.
4. **Verify:** every hard-coded address was tested against the PE sections of a real `Wow.exe`, and the addons
   were run in a headless Lua 5.1 harness across four client shapes.

| Ported feature | Came from |
|---|---|
| Distance API (7 functions) | KhalGH, Keoo888 |
| `enableStancePatch` — one-click stance macros | Hypopheria2k, CH33T4 |
| `NAME_PLATE_OWNER_CHANGED` event | CH33T4, Crumdidlyumshis, somewirdhuman |
| World queries — LOS, position, facing, behind | srazdokunebil |
| `@focuslocation` / `@targetlocation` | srazdokunebil |
| `UnitIsSilenced` argument-count dispatcher | fixed here — every fork inherited the collision |
| `C_NamePlate` table parity | KhalGH |

## The thirteen trees this was assembled from

Twelve repositories — thirteen trees, because Noname08662 was used twice: **v38** as the first base, then
**v39** when it landed.

| Repository | Contributed |
|---|---|
| [FrostAtom/awesome_wotlk](https://github.com/FrostAtom/awesome_wotlk) | the original: nameplate addressing, taskbar, clipboard |
| [KhalGH/awesome_wotlk](https://github.com/KhalGH/awesome_wotlk) | **distance API**, `GetGUIDForNamePlate`, `C_NamePlate` table shape |
| [noname08662/awesome_wotlk](https://github.com/noname08662/awesome_wotlk) | **the base** (v38 → v39): nameplate engine, MSDF, capture |
| [Andyk10/awesome_wotlk](https://github.com/Andyk10/awesome_wotlk) | an earlier snapshot of the v38 lineage |
| [hypopheria2k/awesome_wotlk](https://github.com/hypopheria2k/awesome_wotlk) | **stance/form fix**, clamp renames |
| [CH33T4/awesome_wotlk](https://github.com/CH33T4/awesome_wotlk) | the FrostAtom-lineage baseline |
| [CH33T4/awesome_wotlk_test](https://github.com/CH33T4/awesome_wotlk_test) | TTS, interact keybind, **stance fix**, owner-changed event |
| [someweirdhuman/awesome_wotlk](https://github.com/someweirdhuman/awesome_wotlk) | same family as CH33T4_test, plus font work |
| [Crumdidlyumshis/awesome_wotlk](https://github.com/Crumdidlyumshis/awesome_wotlk) | same family as CH33T4_test |
| [Keoo888/awesome_wotlk](https://github.com/Keoo888/awesome_wotlk) | independent rewrite, Warmane-safety analysis, distances |
| [NoM0Re/awesome_wotlk](https://github.com/NoM0Re/awesome_wotlk) | TTS only |
| [srazdokunebil/awesome_wotlk](https://github.com/srazdokunebil/awesome_wotlk) | **world queries**, `@focuslocation` / `@targetlocation` |

## What you get

| Area | Highlights |
|---|---|
| **Nameplates** | physics stacking (5 modes), screen clamping (5 modes + off-screen views), line-of-sight occlusion, mouse-freeze, per-plate overrides, resizable hitboxes |
| **Fonts** | MSDF vector text at any scale, with a persistent glyph cache and `/msdfpregen` |
| **Camera** | FOV, extended distance, fade-through-trees instead of zooming in |
| **UI** | half-pixel fix, pixel snapping, texture sampling, cooldown-swipe fix |
| **Engine** | exact world culling, projected textures on slopes, ground-target clamp, 200-yard tab targeting |
| **Queries** | distance, line of sight, world position, facing, "am I behind it" |
| **Voice** | `C_VoiceChat` / `C_TTSSettings` text-to-speech, backed by Windows SAPI |
| **Speed** | optional LuaJIT VM (2.5–3× faster Lua, off by default) |

Two addons ship with it:

- **`/awesome` — AwesomeCVar** — a settings window for every CVar this client adds, with a Features tab that
  probes what the client can actually do and locks anything it cannot.
- **`/flash` — Flash** — flashes the taskbar on combat, whisper, party invite and ready check.

## Install

Everything is in **[`release/`](release/)** — copy it into your game folder next to `Wow.exe`.

1. Run **`AwesomeWotlkPatch.exe`** → **Patch client**. It backs up `Wow.exe`, patches it, and places
   `AwesomeWotlkLib.dll` + `skia.dll` beside it.
2. Copy `Interface/AddOns/AwesomeCVar` and `Interface/AddOns/Flash` into your game's `Interface\AddOns`.
3. Start the game, type `/awesome`.

Removing it is the same window → **Remove patch**; `Wow.exe.bak` is restored and the client is stock again.
Full instructions, including upgrades and troubleshooting, are in **[`release/INSTALL.txt`](release/INSTALL.txt)**.

## For addon developers

<div align="center">

[![Addon developer reference](https://img.shields.io/badge/%F0%9F%93%96_OPEN_THE_API_REFERENCE-EVERY_API,_CVAR,_EVENT_%2B_EXAMPLES-2ea44f?style=for-the-badge)](docs/api_reference.md)

</div>

[`docs/api_reference.md`](docs/api_reference.md) documents every function, table method, event, CVar and macro
conditional this client adds — with arguments, return values, contracts and a runnable example for each.

A taste of what it enables — class and distance for a player whose nameplate just appeared, with no mouseover:

```lua
local f = CreateFrame("Frame")
f:RegisterEvent("NAME_PLATE_UNIT_ADDED")
f:SetScript("OnEvent", function(_, _, unit)
    if not UnitIsPlayer(unit) then return end
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    local guid  = C_NamePlate.GetGUIDForNamePlate(plate)   -- nil for a recycled slot
    if not guid then return end

    local _, class = UnitClass(unit)
    print(class, GetDistanceForNamePlate(plate), "yd")
end)
```

Gate on capability, not on the fork:

```lua
AwesomeWotlk   -- 40   (39 = upstream v39, 40 = this build)
FreakySphere   -- "2.0.0", nil on any other build
```

## Compatibility

| | |
|---|---|
| Client | World of Warcraft 3.3.5a, build **12340**, 32-bit |
| Interface | 30300 |
| Servers | any 3.3.5a server; addresses verified against a stock 12340 `Wow.exe` |
| Addons | written for any awesome_wotlk fork run unchanged |
| Unpatched client | everything degrades safely — the addons lock themselves and say why |

<details>
<summary><b>A note about the pointer-range patch</b></summary>

Like every fork in this family, this build widens the range of function pointers the client accepts, because
the Lua C functions live in `AwesomeWotlkLib.dll`, outside the exe image. Keoo888's fork reports that this
correlates with session drops on Warmane and avoids it by publishing data tables instead. That is a
single-user measurement and thousands of players run v38 without noticing — but if you ever see unexplained
disconnects, that is the first thing to test.

</details>

## Build from source

Requirements: **Visual Studio 2022** (or Build Tools) with *Desktop development with C++*, **CMake 3.28+**,
32-bit target.

```bat
build.bat
```

Output: `build\bin\Release\AwesomeWotlkLib.dll` and `AwesomeWotlkPatch.exe`. See [BUILD.md](BUILD.md) for
troubleshooting.

## Credits & licence

Built on the work of **FrostAtom**, **Noname08662**, **KhalGH**, **Keoo888**, **Hypopheria2k**, **CH33T4**,
**Crumdidlyumshis**, **somewirdhuman**, **NoM0Re**, **Andyk10**, **srazdokunebil** — and **Widget** and
**Crum** for the original AwesomeCVar.

GPL-3.0, inherited from upstream. Third-party notices are in [`licenses/`](licenses/).

## 💛 Support Project

I rebuilt awesome_wotlk to give back to the lovely WotLK 3.3.5a community, and especially to support Warmane players and keep the spirit of this server alive. It took many long hours of work to make every feature and mechanism fixed and stable.

This project is completely free, and it always will be. But if it has made your games a little easier or a little more fun, a small donation is deeply appreciated to help keep this project growing and fuel my passion to create even more insane tools and addons like this.

Whether you donate or just share my AwesomeWotLK with a friend, your support means the world to me. Thank you for being part of this community.

With love, **FreakySphere**

<div align="center">

[![Support on ReyMit](https://img.shields.io/badge/Support%20on-ReyMit-7B3FE4?style=for-the-badge&logo=heart&logoColor=white)](https://reymit.ir/FreakySphere)

**USDT · TRC20** — scan the code or copy the address below

<img src="docs/images/usdt-trc20-qr.png" alt="USDT TRC20 wallet QR code" width="160">

</div>

**Three addresses, three networks.** Hover a block and click the copy icon. Each one accepts a single network — anything else sent to it is lost permanently.

**USDT** · TRC20 — TRON network
```text
TFoVYvxDwCvyxWmsQXxEVwLgZhPkJFwzyk
```

**BNB** · BEP-20 — BNB Smart Chain
```text
0xfAcc945FB11975B17eAF82131558913574856133
```

**BTC** · native — Bitcoin
```text
bc1qqvl3edwwna38gh2xg9jhu9tz675g000x47mnwz
```

---

<div align="center">

Made with care for the **WotLK 3.3.5a** community by **FreakySphere**.

</div>
