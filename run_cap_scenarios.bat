@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================================
REM run_cap_scenarios.bat  —  capacitated min-count ladder rungs (S1 + S2)
REM ----------------------------------------------------------------------------
REM Runs the cap scenarios (s1_cap.jl / s2_cap.jl, engine cap_scenario.jl) for
REM the Netherlands:
REM   S1 : minimise #pharmacies s.t. each catchment <= MAX_CAP residents.
REM   S2 : minimise #pharmacies s.t. MIN_CAP <= each catchment <= MAX_CAP.
REM Unlike the lambda sweep this is NOT a w-sweep — it answers "how few, capped"
REM directly. Output: one row per (min_cap,max_cap) combo on the console/log, plus
REM an open-set + per-client traveltime arrow under
REM   %LocalDataProjDir%\NewPharmacies\<country>\cap\<scenario>_min<>_max<>\
REM
REM USAGE (from the repo root E:\prj\JRC\NetworkModel_EU):
REM   run_cap_scenarios.bat                 :: NL, both S1 and S2
REM   run_cap_scenarios.bat France Italy    :: custom country list, both scenarios
REM
REM Tunable via environment (override before calling). Default caps come from NL's
REM observed combined cell-catchment distribution in doc\pharmacy_descriptives.csv
REM (cell_p10 ~ 4400, cell_p90 ~ 18000, cell_max ~ 35100) — RE-TUNE per country:
REM   COUNTRIES       default = the batch arg list, else Netherlands
REM   S1_MAX_CAP      S1 max catchment, residents (~ observed max)   (default 35000)
REM   S2_MIN_CAP      S2 min catchment, residents (~ observed p10)   (default 4000)
REM   S2_MAX_CAP      S2 max catchment, residents (~ observed max)   (default 35000)
REM   CANDIDATE_DIR   which pharmacies to optimise over     (default NewPharmacies):
REM                   point at a rural-only or one-per-cell export to switch
REM                   rung / scope WITHOUT touching the scripts.
REM   TRAVEL_FUNC     travel-cost function c(t)             (default LINEAR)
REM   JULIA_EXE       julia executable                      (default julia)
REM   LOG_DIR         per-scenario logs                     (default .\logs)
REM
REM   MIN_CAP / MAX_CAP may be space-separated lists for a small cap sweep, e.g.
REM     set "S2_MIN_CAP=1000 2000 4000"
REM ============================================================================

if "%JULIA_EXE%"==""  set "JULIA_EXE=julia"
if "%LOG_DIR%"==""    set "LOG_DIR=%~dp0logs"
if "%TRAVEL_FUNC%"=="" set "TRAVEL_FUNC=LINEAR"
if "%S1_MAX_CAP%"=="" set "S1_MAX_CAP=35000"
if "%S2_MIN_CAP%"=="" set "S2_MIN_CAP=4000"
if "%S2_MAX_CAP%"=="" set "S2_MAX_CAP=35000"

if "%~1"=="" ( set "COUNTRIES=Netherlands" ) else ( set "COUNTRIES=%*" )
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

set "OVERALL_RC=0"
set "TAG=%COUNTRIES: =_%"

echo.
echo ============================================================
echo  S1 (max cap=%S1_MAX_CAP%)  countries: %COUNTRIES%
echo ============================================================
set "LOG_S1=%LOG_DIR%\cap_%TAG%_S1.log"
set "MIN_CAP=0"
set "MAX_CAP=%S1_MAX_CAP%"
"%JULIA_EXE%" --startup-file=no "%~dp0s1_cap.jl" > "%LOG_S1%" 2>&1
if errorlevel 1 ( echo [ERROR] S1 failed ^(see %LOG_S1%^). & set "OVERALL_RC=1" ) else ( echo  S1 done. log: %LOG_S1% )
type "%LOG_S1%"

echo.
echo ============================================================
echo  S2 (min cap=%S2_MIN_CAP%, max cap=%S2_MAX_CAP%)  countries: %COUNTRIES%
echo ============================================================
set "LOG_S2=%LOG_DIR%\cap_%TAG%_S2.log"
set "MIN_CAP=%S2_MIN_CAP%"
set "MAX_CAP=%S2_MAX_CAP%"
"%JULIA_EXE%" --startup-file=no "%~dp0s2_cap.jl" > "%LOG_S2%" 2>&1
if errorlevel 1 ( echo [ERROR] S2 failed ^(see %LOG_S2%^). & set "OVERALL_RC=1" ) else ( echo  S2 done. log: %LOG_S2% )
type "%LOG_S2%"

echo.
if "%OVERALL_RC%"=="0" (
    echo ============================================================
    echo  Done. Logs: %LOG_S1%  and  %LOG_S2%
    echo ============================================================
) else (
    echo One or more scenarios FAILED. See logs under "%LOG_DIR%".
)
endlocal & exit /b %OVERALL_RC%
