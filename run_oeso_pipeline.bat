@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================================
REM run_oeso_pipeline.bat
REM ----------------------------------------------------------------------------
REM PURPOSE
REM   Batch-generate the per-country input artefacts that feed the school-
REM   network optimisation code in Julia (lp-greedy*.jl in this repository
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
REM   lp-greedy-merge.jl / lp-greedy.jl read to solve the LP / greedy
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
REM   4. The script TEMPORARILY rewrites cfg\main\ModelParameters.dms to set
REM      /ModelParameters/StudyArea per iteration. It saves a backup at
REM      cfg\main\ModelParameters.dms.bak and restores it on completion or
REM      when interrupted. If a previous run was killed and you see
REM      ModelParameters.dms.bak lying around, restore manually:
REM        copy /Y cfg\main\ModelParameters.dms.bak cfg\main\ModelParameters.dms
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
REM     2   prerequisite check failed (missing GeoDmsRun / config / dms file)
REM ============================================================================

REM -------- 1. Configuration --------------------------------------------------
if "%GEODMS_EXE%"=="" set "GEODMS_EXE=C:\Program Files\ObjectVision\GeoDms20.0.0.m\GeoDmsRun.exe"
if "%CFG%"=="" set "CFG=%~dp0cfg\main.dms"
if "%LOG_DIR%"=="" set "LOG_DIR=%~dp0logs"
if "%STEPS%"=="" set "STEPS=network1 network2 alloc"

set "MODEL_PARAMS=%~dp0cfg\main\ModelParameters.dms"
set "MODEL_PARAMS_BAK=%MODEL_PARAMS%.bak"

REM Supported OESO/OECD countries. Must match the country sub-folders that
REM actually exist under %NetworkModelDataDir%\Infrastructure\TomTom\ AND the
REM English NUTS name used by CNTR_RG_01M_2020_3035.shp (see
REM cfg\main\SourceData\RegionalUnits.dms, attribute name_engl). At the time
REM of writing the source data dir contains:
REM   EU, Finland, France, Netherlands, Romania
REM EU is the all-countries meta-region and is not iterated here. Extend the
REM list as more per-country TomTom datasets become available.
set "DEFAULT_COUNTRIES=Finland France Netherlands Romania"

REM Items (GeoDms tree paths) to compute, grouped per step. Each item is a
REM separately-quoted token so GeoDmsRun receives them as distinct args
REM (semicolon-joining does NOT work -- GeoDmsRun would treat the whole
REM thing as a single -- and therefore unresolvable -- item path).
set ITEMS_NETWORK1="/NetworkSetup/ExistingSchool_Analysis/NetwerkSpec/CreateInitialWorkingNetwork/LinkSet_Write"
set ITEMS_NETWORK2="/NetworkSetup/ExistingSchool_Analysis/NetwerkSpec/CreateMoreEfficientNetwork/Generate"
set ITEMS_ALLOC="/Analyses/AllocateKidsToExistingSchools/Allocation/DistanceTableExport" "/Analyses/AllocateKidsToExistingSchools/Allocation/ClientExport" "/Analyses/AllocateKidsToExistingSchools/Allocation/FacilityExport"

REM -------- 2. Pre-flight checks ----------------------------------------------
if not exist "%GEODMS_EXE%" (
    echo [ERROR] GeoDmsRun not found at "%GEODMS_EXE%".
    echo         Install GeoDms 20.0.0.m or set GEODMS_EXE to the correct path.
    exit /b 2
)
if not exist "%CFG%" (
    echo [ERROR] Config file not found at "%CFG%".
    exit /b 2
)
if not exist "%MODEL_PARAMS%" (
    echo [ERROR] ModelParameters.dms not found at "%MODEL_PARAMS%".
    exit /b 2
)
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

REM -------- 3. Country list ---------------------------------------------------
if "%~1"=="" (
    set "COUNTRIES=%DEFAULT_COUNTRIES%"
) else (
    set "COUNTRIES=%*"
)

REM -------- 4. Backup ModelParameters.dms (so we can restore on exit/CTRL-C) --
if exist "%MODEL_PARAMS_BAK%" (
    echo [WARN] Stale backup %MODEL_PARAMS_BAK% exists. Refusing to overwrite.
    echo        If the original is intact, delete the backup and rerun.
    echo        Otherwise restore manually:
    echo          copy /Y "%MODEL_PARAMS_BAK%" "%MODEL_PARAMS%"
    exit /b 2
)
copy /Y "%MODEL_PARAMS%" "%MODEL_PARAMS_BAK%" > nul

REM -------- 5. Main loop ------------------------------------------------------
REM We pass paths + country to PowerShell via environment variables so the
REM PS command line itself contains no literal quotes that cmd.exe could mangle.
set "MP_BAK=%MODEL_PARAMS_BAK%"
set "MP_DST=%MODEL_PARAMS%"

set "OVERALL_RC=0"
for %%C in (%COUNTRIES%) do (
    set "COUNTRY=%%C"
    set "STUDY_AREA=%%C"
    echo.
    echo ============================================================
    echo  Processing country: !COUNTRY!
    echo ============================================================

    REM Rewrite ModelParameters.dms from the pristine backup, replacing the
    REM whole 'parameter<string>   StudyArea := '...';' assignment with the
    REM current country. The regex matches whichever default value was
    REM committed. [char]39 is used in place of literal single quotes so the
    REM PowerShell command line stays quote-free.
    powershell -NoProfile -ExecutionPolicy Bypass -Command "$q=[char]39; $rx=New-Object System.Text.RegularExpressions.Regex('(parameter<string>\s+StudyArea\s+:=\s+)' + $q + '[^' + $q + ']*' + $q); $c = Get-Content -Raw -LiteralPath $env:MP_BAK; $c = $rx.Replace($c, '${1}' + $q + $env:STUDY_AREA + $q); Set-Content -LiteralPath $env:MP_DST -Value $c -Encoding ASCII"
    if errorlevel 1 (
        echo [ERROR] Failed to rewrite StudyArea for !COUNTRY!.
        set "OVERALL_RC=1"
        goto :cleanup
    )

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

:cleanup
REM -------- 6. Always restore ModelParameters.dms -----------------------------
if exist "%MODEL_PARAMS_BAK%" (
    copy /Y "%MODEL_PARAMS_BAK%" "%MODEL_PARAMS%" > nul
    del /Q "%MODEL_PARAMS_BAK%"
)

echo.
if "%OVERALL_RC%"=="0" (
    echo ============================================================
    echo  All countries / steps completed successfully.
    echo  Outputs are under %%LocalDataProjDir%%\^<ProjName^>\^<Country^>\
    echo  Feed those files to lp-greedy-merge.jl / lp-greedy.jl.
    echo ============================================================
) else (
    echo ============================================================
    echo  One or more runs FAILED. See logs under "%LOG_DIR%".
    echo ============================================================
)

endlocal & exit /b %OVERALL_RC%
