@echo off
:: inflate.bat
:: Places qpd template files into an existing or new project directory.
:: Non-destructive: never overwrites files that already exist.
::
:: Usage:
::   inflate.bat <target_dir>

setlocal enabledelayedexpansion

set TARGET=%1
if "%TARGET%"=="" (
    echo Usage: inflate.bat ^<target_dir^>
    echo.
    echo Places qpd framework files into ^<target_dir^>.
    echo Existing files are never overwritten.
    exit /b 1
)

set SRC=%~dp0
if "%SRC:~-1%"=="\" set SRC=%SRC:~0,-1%

echo Inflating qpd into: %TARGET%

:: /e = all subdirs, /i = assume dir if ambiguous
:: No /y = do NOT overwrite existing files (xcopy will skip them silently with /d)
:: /d = only copy files newer than destination — combined with no /y gives non-destructive

if not exist "%TARGET%" mkdir "%TARGET%"
xcopy /e /i /d /q "%SRC%\template" "%TARGET%"

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
    if not exist "%TARGET%\qpd\%%I" (
        copy /y "%SRC%\%%I" "%TARGET%\qpd\%%I" >nul
    )
)

for %%D in (archive cells services templates widgets) do (
    xcopy /e /i /d /q "%SRC%\%%D" "%TARGET%\qpd\%%D"
)

echo.
echo Done. Existing files were not modified.
echo.
echo To run:
echo   cd %TARGET% ^&^& love .
