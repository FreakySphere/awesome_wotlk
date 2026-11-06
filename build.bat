@echo off
setlocal enabledelayedexpansion
title FreakySphere awesome_wotlk - build

echo.
echo  ============================================================
echo   FreakySphere awesome_wotlk - build
echo  ============================================================
echo.

rem ---------------------------------------------------------------- locate Visual Studio
set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo  [!] Visual Studio Installer not found.
    echo.
    echo      Install "Visual Studio 2022 Build Tools" with the
    echo      "Desktop development with C++" workload, then run this again.
    echo      https://visualstudio.microsoft.com/downloads/
    goto :fail
)

set "VSPATH="
for /f "usebackq tokens=*" %%i in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSPATH=%%i"

if not defined VSPATH (
    echo  [!] Visual Studio is installed but the C++ toolset is missing.
    echo      Open the Visual Studio Installer, click Modify, and tick
    echo      "Desktop development with C++".
    goto :fail
)
echo  [ok] Visual Studio: !VSPATH!

rem ---------------------------------------------------------------- locate CMake
set "CMAKE="
where cmake >nul 2>&1 && set "CMAKE=cmake"
if not defined CMAKE (
    if exist "%ProgramFiles%\CMake\bin\cmake.exe" set "CMAKE=%ProgramFiles%\CMake\bin\cmake.exe"
)
if not defined CMAKE (
    for /d %%d in ("%ProgramFiles%\Microsoft Visual Studio\2022\*") do (
        if exist "%%d\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" (
            set "CMAKE=%%d\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
        )
    )
)
if not defined CMAKE (
    echo  [!] CMake not found. Install it from https://cmake.org/download/
    echo      or let the Visual Studio Installer add "C++ CMake tools for Windows".
    goto :fail
)
echo  [ok] CMake: !CMAKE!

rem ---------------------------------------------------------------- configure
echo.
echo  [..] configuring (32-bit Release)
"%CMAKE%" -S "%~dp0." -B "%~dp0build" -G "Visual Studio 17 2022" -A Win32 -DCMAKE_BUILD_TYPE=Release
if errorlevel 1 goto :fail

rem ---------------------------------------------------------------- build
echo.
echo  [..] compiling
"%CMAKE%" --build "%~dp0build" --config Release --parallel
if errorlevel 1 goto :fail

echo.
echo  ============================================================
echo   Build finished
echo  ============================================================
echo.
echo   AwesomeWotlkLib.dll    build\bin\Release\AwesomeWotlkLib.dll
echo   AwesomeWotlkPatch.exe  build\bin\Release\AwesomeWotlkPatch.exe
echo.
echo   Copy both next to Wow.exe, then run AwesomeWotlkPatch.exe once.
echo.
goto :end

:fail
echo.
echo  Build failed. Scroll up for the first "error" line.
echo.
pause
exit /b 1

:end
pause
endlocal
