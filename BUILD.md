# Building FreakySphere awesome_wotlk

The short version: double-click **`build.bat`**. It finds Visual Studio, configures, compiles, and tells you
where the two files are.

If you would rather do it by hand, or `build.bat` fails, this page has the details.

---

## Requirements

| Tool | Version | Notes |
|---|---|---|
| Visual Studio 2022 | any edition, or **Build Tools 2022** | must include **Desktop development with C++** |
| CMake | **3.28 or newer** | the VS installer can add it ("C++ CMake tools for Windows") |
| Windows SDK | 10.0.19041 or newer | comes with the C++ workload |

The project **must** be built as **32-bit (x86)**. WoW 3.3.5a is a 32-bit process; a 64-bit DLL will not load.
`CMakeLists.txt` refuses to configure otherwise.

The toolset must be **MSVC** (or `clang-cl`). MinGW will not work: `deps/skia/skia.lib` is a prebuilt MSVC
static library.

---

## Manual build

Open **x86 Native Tools Command Prompt for VS 2022** (not the plain one — it must be the x86 variant), then:

```bat
cd /d "F:\all awesome_wotlk patches\FreakySphere awesome_wotlk"

cmake -S . -B build -G "Visual Studio 17 2022" -A Win32
cmake --build build --config Release --parallel
```

`-A Win32` is what selects 32-bit. Do not drop it.

### Output

```
build\bin\Release\AwesomeWotlkLib.dll
build\bin\Release\AwesomeWotlkPatch.exe
```

Copy both next to `Wow.exe`, then run `AwesomeWotlkPatch.exe` **once** to patch the client.

---

## Why `build.bat` asks for the C++ workload

`vswhere.exe` will happily report a Visual Studio installation that has no compiler in it. The script filters
with `-requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64`, so it only accepts an install that can
actually build this.

---

## Common errors

**`CMake Error: could not find any instance of Visual Studio`**
You have the IDE but not the C++ workload. Open the Visual Studio Installer → Modify → tick
*Desktop development with C++*.

**`FATAL_ERROR: FreakySphere awesome_wotlk targets 32-bit WoW`**
You forgot `-A Win32`.

**`FATAL_ERROR: Unsupported toolset`**
You are building with MinGW or a non-MSVC clang. Use the MSVC toolchain.

**`cannot open input file 'skia.lib'`**
`deps/skia/skia.lib` is missing — the download was incomplete. Re-extract the repository.

**`LNK1112: module machine type 'x86' conflicts with target machine type 'x64'`**
Some object files were configured for 64-bit. Delete the `build` folder and configure again with `-A Win32`.

**The game crashes immediately on launch after installing the DLL**
Almost always a 64-bit build, or the DLL is next to the wrong `Wow.exe`. Check that the file is exactly
`AwesomeWotlkLib.dll` (not `AwesomeWotlkLib (2).dll`).

---

## What gets compiled

```
src/AwesomeWotlkLib/     -> AwesomeWotlkLib.dll   (the mod)
src/AwesomeWotlkPatch/   -> AwesomeWotlkPatch.exe (patches Wow.exe to load the DLL)
deps/freetype-2.14.3     -> static lib (font rasteriser for MSDF)
deps/msdfgen             -> static lib (signed distance field generation)
deps/skia/skia.lib       -> prebuilt static lib (font shaping)
deps/unordered_dense     -> header only
tools/hookkit            -> static lib (detour framework + MinHook)
tools/blpcodec           -> static lib (BLP texture decoding)
```

Nothing outside this folder is required, and no network access is needed at build time.
