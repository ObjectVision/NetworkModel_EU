@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================================
REM run_oeso_pipeline.bat
REM ----------------------------------------------------------------------------
REM PURPOSE
REM   Batch-generate the per-country input artefacts that feed the school-
REM   network optimisation code in Julia (lp.jl and greedy.jl in this repository
REM   root). For every supported OESO/OECD country the script
REM     (1) builds the initial working road network         (LinkSet_Write),
REM     (2) builds the more-efficient (cleaned) network     (Generate),
REM     (3) exports the OD distance table + client + facility tables for the
REM         existing-school allocation                      (DistanceTableExport,
REM                                                          ClientExport,
REM                                                          FacilityExport).
REM
REM   The resulting .mmd / .arrow files are written to %LocalDataProjDir%
REM   (see cfg\main\Templates.dms and cfg\main\Analyses.dms for the exact
REM   StorageName expressions). Those files are the inputs that
REM   lp.jl / greedy.jl read to solve the LP / greedy
REM   facility-location problem.
REM
REM ----------------------------------------------------------------------------
REM PRE-REQUISITES
REM   1. GeoDms 20.0.0.m installed at:
REM        C:\Program Files\ObjectVision\GeoDms20.0.0.m\GeoDmsRun.exe
REM      (override with the GEODMS_EXE environment variable if installed
REM       elsewhere).
REM
REM   2. TomTom source data present under %NetworkModelDataDir%, with a
REM      per-country sub-folder matching the StudyArea name, e.g.
REM        %NetworkModelDataDir%\Infrastructure\TomTom\Netherlands\NW2021_SP_streets_subset.mmd
REM      The folder name must be identical (case-sensitive on some setups) to
REM      the country names in COUNTRIES below.
REM
REM   3. The GeoDms config-settings LocalDataDir, LocalDataProjDir and
REM      SourceDataDir must be set in your GeoDms registry (HKCU\Software\
REM      ObjectVision\DMS) -- the same settings the GeoDms GUI uses.
REM
REM   4. cfg\main\ModelParameters.dms picks up the StudyArea from the
REM      STUDY_AREA environment variable via:
REM          parameter<string> StudyArea_ext := Expand(., '%%env:STUDY_AREA%%');
REM      This script sets STUDY_AREA per iteration; ModelParameters.dms is
REM      NOT modified on disk.
REM
REM ----------------------------------------------------------------------------
REM USAGE
REM   From the repository root (E:\prj\JRC\NetworkModel_EU):
REM
REM     run_oeso_pipeline.bat                   ::  run all countries, all steps
REM     run_oeso_pipeline.bat Netherlands       ::  run a single country
REM     run_oeso_pipeline.bat Netherlands Finland Romania
REM                                             ::  run a custom country list
REM
REM   Optional environment variables (set before calling, or edit defaults
REM   below):
REM     GEODMS_EXE   full path to GeoDmsRun.exe
REM     CFG          path to the GeoDms config (defaults to cfg\main.dms)
REM     LOG_DIR      directory for per-country log files (defaults to .\logs)
REM     STEPS        space-separated subset of {network1 network2 alloc} to
REM                  run only certain steps (default: all three)
REM
REM   Exit codes:
REM     0   all countries / steps succeeded
REM     1   at least one GeoDmsRun call returned a non-zero exit code; check
REM         the corresponding .log file under %LOG_DIR%
REM     2   prerequisite check failed (missing GeoDmsRun or config)
REM ============================================================================

REM -------- 1. Configuration --------------------------------------------------
REM if "%GEODMS_EXE%"=="" set "GEODMS_EXE=C:\Program Files\ObjectVision\GeoDms20.0.3.m\GeoDmsRun.exe"
REM Use the INSTALLED GeoDms, NOT the engine build tree at C:\dev\GeoDMS_2026:
REM a run from there loads binaries that may be mid-relink, and holds a handle on
REM Dm*.dll which makes the next engine link silently skip.
if "%GEODMS_EXE%"=="" set "GEODMS_EXE=C:\Program Files\ObjectVision\GeoDms20.19.1.m\GeoDmsRun.exe"
if "%CFG%"=="" set "CFG=%~dp0cfg\main.dms"
if "%LOG_DIR%"=="" set "LOG_DIR=%~dp0logs"
if "%STEPS%"=="" set "STEPS=network1 network2 alloc"

REM Supported OESO/OECD countries. Must match the country sub-folders that
REM actually exist under %NetworkModelDataDir%\Infrastructure\TomTom\ AND the
REM English NUTS name used by CNTR_RG_01M_2020_3035.shp (see
REM cfg\main\SourceData\RegionalUnits.dms, attribute name_engl). At the time
REM of writing the source data dir contains:
REM   EU, Finland, France, Netherlands, Romania
REM EU is the all-countries meta-region and is not iterated here. Extend the
REM list as more per-country TomTom datasets become available.
REM --- first: all c
REM set "DEFAULT_COUNTRIES=Albania Austria Belgium Bulgaria Switzerland Denmark Spain Estonia Greece Cyprus Czechia Germany France Finland Croatia Hungary Ireland Iceland Italy Liechtenstein Lithuania Luxembourg Latvia Malta Netherlands Norway Romania Poland Portugal Sweden Slovenia Slovakia
set "DEFAULT_COUNTRIES=France Italy Netherlands Sweden


REM Items (GeoDms tree paths) to compute, grouped per step. Each item is a
REM separately-quoted token so GeoDmsRun receives them as distinct args
REM (semicolon-joining does NOT work -- GeoDmsRun would treat the whole
REM thing as a single -- and therefore unresolvable -- item path).
REM set ITEMS_NETWORK=ExistingSchool_Analysis
set ITEM_NETWORK=NewPharmacy_Analysis
set ITEMS_NETWORK1="/NetworkSetup/%ITEM_NETWORK%/NetwerkSpec/CreateInitialWorkingNetwork/LinkSet_Write"
set ITEMS_NETWORK2="/NetworkSetup/%ITEM_NETWORK%/NetwerkSpec/CreateMoreEfficientNetwork/Generate"

set ITEM_ANALYSIS=AllocateClientsToNewPharmacies
set ITEMS_ALLOC="/Analyses/%ITEM_ANALYSIS%/Allocation/DistanceTableExport" "/Analyses/%ITEM_ANALYSIS%/Allocation/ClientExport" "/Analyses/%ITEM_ANALYSIS%/Allocation/FacilityExport"

REM -------- 2. Pre-flight checks ----------------------------------------------
if not exist "%GEODMS_EXE%" (
    echo [ERROR] GeoDmsRun not found at "%GEODMS_EXE%".
    echo         Install GeoDms 20.19.1.m or set GEODMS_EXE to the correct path.
    exit /b 2
)
if not exist "%CFG%" (
    echo [ERROR] Config file not found at "%CFG%".
    exit /b 2
)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM -------- 3. Country list ---------------------------------------------------
if "%~1"=="" (
    set "COUNTRIES=%DEFAULT_COUNTRIES%"
) else (
    set "COUNTRIES=%*"
)

REM -------- 4. Main loop ------------------------------------------------------
REM STUDY_AREA is exported as an environment variable each iteration; GeoDmsRun
REM picks it up via Expand(., '%%env:STUDY_AREA%%') in cfg\main\ModelParameters.dms,
REM so the repository file is left untouched.

set "OVERALL_RC=0"
for %%C in (%COUNTRIES%) do (
    set "COUNTRY=%%C"
    set "STUDY_AREA=%%C"
    echo.
    echo ============================================================
    echo  Processing country: !COUNTRY!  (STUDY_AREA=!STUDY_AREA!)
    echo ============================================================

    for %%S in (%STEPS%) do (
        set "STEP=%%S"
        set "ITEMS="
        if /I "!STEP!"=="network1" set "ITEMS=%ITEMS_NETWORK1%"
        if /I "!STEP!"=="network2" set "ITEMS=%ITEMS_NETWORK2%"
        if /I "!STEP!"=="alloc"    set "ITEMS=%ITEMS_ALLOC%"

        if "!ITEMS!"=="" (
            echo [WARN] Unknown step "!STEP!" -- skipping.
        ) else (
            set "LOG_FILE=%LOG_DIR%\!COUNTRY!_!STEP!.log"
            echo  -- step !STEP!  ^(log: !LOG_FILE!^)
            "%GEODMS_EXE%" /L"!LOG_FILE!" "%CFG%" !ITEMS!
            if errorlevel 1 (
                echo [ERROR] GeoDmsRun failed for !COUNTRY! / !STEP! ^(see !LOG_FILE!^).
                set "OVERALL_RC=1"
            ) else (
                echo  -- step !STEP!  OK
            )
        )
    )
)

echo.
if "%OVERALL_RC%"=="0" (
    echo ============================================================
    echo  All countries / steps completed successfully.
    echo  Outputs are under %%LocalDataProjDir%%\^<ProjName^>\^<Country^>\
    echo  Feed those files to lp.jl / greedy.jl.
    echo ============================================================
) else (
    echo ============================================================
    echo  One or more runs FAILED. See logs under "%LOG_DIR%".
    echo ============================================================
)

endlocal & exit /b %OVERALL_RC%
