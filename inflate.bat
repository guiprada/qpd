@echo off
:: inflate.bat
:: Creates a new LÖVE2D project from the qpd template.
::
:: Usage:
::   inflate.bat <target_dir>

setlocal enabledelayedexpansion

set TARGET=%1
if "%TARGET%"=="" (
    echo Usage: inflate.bat ^<target_dir^>
    echo.
    echo Creates a new LOVE2D / qpd project at ^<target_dir^>.
    exit /b 1
)

set SRC=%~dp0
:: Remove trailing backslash
if "%SRC:~-1%"=="\" set SRC=%SRC:~0,-1%

echo Inflating qpd project to: %TARGET%

:: Copy template scaffolding
if not exist "%TARGET%" mkdir "%TARGET%"
xcopy /e /i /y "%SRC%\template" "%TARGET%" >nul

:: Copy qpd library into project\qpd\
if not exist "%TARGET%\qpd" mkdir "%TARGET%\qpd"

for %%I in (
    ann.lua
    ann_activation_functions.lua
    ann_neat.lua
    array.lua
    camera.lua
    collision.lua
    color.lua
    gamestate.lua
    grid.lua
    logger.lua
    love_utils.lua
    matrix.lua
    point.lua
    population_io.lua
    qpd.lua
    random.lua
    table.lua
    tilemap.lua
    tilemap_view.lua
    timer.lua
    value.lua
) do (
    copy /y "%SRC%\%%I" "%TARGET%\qpd\%%I" >nul
)

for %%D in (archive cells services templates widgets) do (
    xcopy /e /i /y "%SRC%\%%D" "%TARGET%\qpd\%%D" >nul
)

echo.
echo Done! Your new project is at: %TARGET%
echo.
echo To run:
echo   cd %TARGET%
echo   love .
echo.
echo Tip: to use qpd as a git submodule instead of a copy:
echo   git init %TARGET%
echo   cd %TARGET%
echo   git submodule add https://github.com/guiprada/qpd qpd
