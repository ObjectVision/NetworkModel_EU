@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================================
REM run_cap_scenarios.bat  —  ladder rungs A/B/C WITHOUT a cost function
REM ----------------------------------------------------------------------------
REM Runs, for the Netherlands, the cost-function-free rungs of both scenarios
REM (engine cap_scenario.jl via s1_cap.jl / s2_cap.jl):
REM
REM   S1 "reduce travel, keep #pharmacies constant" (min travel at fixed count):
REM     A  multiple pharmacies per cell allowed       (max cap)
REM     B  at most one pharmacy per cell              (max cap)
REM     C  urban centres fixed, model the rest        (max cap)
REM   S2 "reduce #pharmacies, keep travel constant" (min count, min+max cap):
REM     A  reduce all facilities (global)
REM     B  reduce only outside urban centres (urban fixed)
REM   (S2 option C is the cost function -> use the lambda sweep, not this.)
REM
REM This is NOT a w-sweep; it answers "how few / how capped" directly. One row
REM per (rung, min_cap, max_cap) on the console/log, plus open-set + per-client
REM traveltime arrows under
REM   %LocalDataProjDir%\NewPharmacies\<country>\cap\<scen>_<rung>_min<>_max<>\
REM
REM USAGE (from the repo root E:\prj\JRC\NetworkModel_EU):
REM   run_cap_scenarios.bat                 :: NL, all rungs of S1 and S2
REM   run_cap_scenarios.bat France Italy    :: custom country list
REM
REM Tunable via environment. Default caps come from NL's observed combined
REM cell-catchment distribution in doc\pharmacy_descriptives.csv
REM (cell_p10 ~ 4400, cell_p90 ~ 18000, cell_max ~ 35100) — RE-TUNE per country:
REM   COUNTRIES       default = batch args, else Netherlands
REM   S1_RUNGS        which S1 rungs to run      (default "A B C")
REM   S2_RUNGS        which S2 rungs to run      (default "A B")
REM   S1_MAX_CAP      S1 max catchment, residents (~ observed max)   (default 35000)
REM   S1_TARGET       S1 fixed pharmacy count    (default = today's cells; for a
REM                   true rung-A packing test set the raw count, e.g. 1992 NL)
REM   S2_MIN_CAP      S2 min catchment, residents (~ observed p10)   (default 4000)
REM   S2_MAX_CAP      S2 max catchment, residents (~ observed max)   (default 35000)
REM   URBAN_POP       cell own-pop threshold for "urban" (S1-C, S2-B) (default 25000)
REM   CANDIDATE_DIR   which pharmacies to optimise over (default NewPharmacies);
REM                   point at a rural-only export to scope the analysis
REM   TRAVEL_FUNC     travel-cost function c(t)              (default LINEAR)
REM   JULIA_EXE       julia executable                       (default julia)
REM   LOG_DIR         per-run logs                           (default .\logs)
REM   (MIN_CAP / MAX_CAP / S1_TARGET may be space-separated lists for a sweep.)
REM ============================================================================

if "%JULIA_EXE%"==""  set "JULIA_EXE=julia"
if "%LOG_DIR%"==""    set "LOG_DIR=%~dp0logs"
if "%TRAVEL_FUNC%"=="" set "TRAVEL_FUNC=LINEAR"
if "%S1_RUNGS%"==""   set "S1_RUNGS=A B C"
if "%S2_RUNGS%"==""   set "S2_RUNGS=A B"
if "%S1_MAX_CAP%"=="" set "S1_MAX_CAP=35000"
if "%S2_MIN_CAP%"=="" set "S2_MIN_CAP=4000"
if "%S2_MAX_CAP%"=="" set "S2_MAX_CAP=35000"
if "%URBAN_POP%"==""  set "URBAN_POP=25000"

if "%~1"=="" ( set "COUNTRIES=Netherlands" ) else ( set "COUNTRIES=%*" )
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"
set "TAG=%COUNTRIES: =_%"
set "OVERALL_RC=0"

if not "%S1_TARGET%"=="" ( set "TARGET_COUNT=%S1_TARGET%" )

for %%R in (%S1_RUNGS%) do (
    set "RUNG=%%R"
    set "MIN_CAP=0"
    set "MAX_CAP=%S1_MAX_CAP%"
    set "LOG=%LOG_DIR%\cap_%TAG%_S1_%%R.log"
    echo.
    echo === S1 rung %%R  max cap=%S1_MAX_CAP%  urban_pop=%URBAN_POP%  countries: %COUNTRIES% ===
    "%JULIA_EXE%" --startup-file=no "%~dp0s1_cap.jl" > "!LOG!" 2>&1
    if errorlevel 1 ( echo [ERROR] S1-%%R failed ^(see !LOG!^). & set "OVERALL_RC=1" ) else ( echo  S1-%%R done. log: !LOG! )
    type "!LOG!"
)

set "TARGET_COUNT="
for %%R in (%S2_RUNGS%) do (
    set "RUNG=%%R"
    set "MIN_CAP=%S2_MIN_CAP%"
    set "MAX_CAP=%S2_MAX_CAP%"
    set "LOG=%LOG_DIR%\cap_%TAG%_S2_%%R.log"
    echo.
    echo === S2 rung %%R  min cap=%S2_MIN_CAP%  max cap=%S2_MAX_CAP%  urban_pop=%URBAN_POP%  countries: %COUNTRIES% ===
    "%JULIA_EXE%" --startup-file=no "%~dp0s2_cap.jl" > "!LOG!" 2>&1
    if errorlevel 1 ( echo [ERROR] S2-%%R failed ^(see !LOG!^). & set "OVERALL_RC=1" ) else ( echo  S2-%%R done. log: !LOG! )
    type "!LOG!"
)

echo.
if "%OVERALL_RC%"=="0" (
    echo ============================================================
    echo  Done. Logs under %LOG_DIR%\cap_%TAG%_S*_*.log
    echo ============================================================
) else (
    echo One or more runs FAILED. See logs under "%LOG_DIR%".
)
endlocal & exit /b %OVERALL_RC%
