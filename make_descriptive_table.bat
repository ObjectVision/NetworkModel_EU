@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================================
REM make_descriptive_table.bat
REM ----------------------------------------------------------------------------
REM Computes Lewis's (22-May) observed-pharmacy descriptive indicators for every
REM study area (Netherlands + the NUTS1 regions of France, Italy, Sweden) by
REM looping GeoDmsRun over /Analyses/Pharmacies/Descriptives/Table, which writes
REM one Arrow row per study area to
REM     %LocalDataProjDir%\Pharmacies_Descriptives\<StudyArea>.arrow
REM Then collect_descriptives.jl gathers them into one CSV table for the deck.
REM
REM Per study area (no network needed; runs in ~1s each):
REM   n_pharmacies, n_pharmacy_cells, n_residents, residents_per_pharmacy,
REM   n_cells_multi, avg/max pharmacies in multi-pharmacy cells, and the
REM   catchment-population distribution (min/p10/25/50/75/90/max/avg) both per
REM   pharmacy (metric 5) and with pharmacies combined per cell (metric 6).
REM ============================================================================

REM Use the INSTALLED GeoDms, NOT the engine build tree at C:\dev\GeoDMS_2026:
REM a run from there loads binaries that may be mid-relink, and holds a handle on
REM Dm*.dll which makes the next engine link silently skip.
if "%GEODMS_EXE%"=="" set "GEODMS_EXE=C:\Program Files\ObjectVision\GeoDms20.19.1.m\GeoDmsRun.exe"
if "%CFG%"==""        set "CFG=%~dp0cfg\main.dms"
if "%LOG_DIR%"==""    set "LOG_DIR=%~dp0logs"
if "%OUT_DIR%"==""    set "OUT_DIR=C:\LocalData\networkmodel_eu\Pharmacies_Descriptives"
set "ITEM=/Analyses/Pharmacies/Descriptives/Table"

REM Study areas: the 18 enum countries that now have a pharmacy parquet (Finland
REM excluded, issue #44) + the NUTS1 regions of FR / IT / SE for the within-country
REM breakdown. Country rows feed the country-level tables; NUTS1 rows the breakdowns.
if "%~1"=="" (
    REM Iceland dropped: no population grid / pharmacy OD (issue #44) — under the
    REM population-client config its failure mode is a HANG, not a fast error.
    set "STUDY_AREAS=Austria Belgium Czechia Denmark Estonia Finland France Hungary Ireland Italy Lithuania Luxembourg Latvia Netherlands Norway Poland Portugal Slovenia Sweden FR1 FRB FRC FRD FRE FRF FRG FRH FRI FRJ FRK FRL FRM ITC ITF ITG ITH ITI SE1 SE2 SE3 PL2 PL4 PL5 PL6 PL7 PL8 PL9"
) else (
    set "STUDY_AREAS=%*"
)

if not exist "%GEODMS_EXE%" ( echo [ERROR] GeoDmsRun not found at "%GEODMS_EXE%". & exit /b 2 )
if not exist "%CFG%"        ( echo [ERROR] Config not found at "%CFG%".        & exit /b 2 )
if not exist "%LOG_DIR%" mkdir "%LOG_DIR%"

set "OVERALL_RC=0"
for %%A in (%STUDY_AREAS%) do (
    set "STUDY_AREA=%%A"
    set "LOG_FILE=%LOG_DIR%\descr_%%A.log"
    echo  -- %%A  ^(log: !LOG_FILE!^)
    "%GEODMS_EXE%" /L"!LOG_FILE!" "%CFG%" "%ITEM%"
    if errorlevel 1 (
        echo [ERROR] GeoDmsRun failed for %%A ^(see !LOG_FILE!^).
        set "OVERALL_RC=1"
    )
)

echo.
echo Collecting per-study-area Arrow files into one table ...
julia "%~dp0collect_descriptives.jl" "%OUT_DIR%" "%~dp0doc\pharmacy_descriptives.csv"
if errorlevel 1 ( echo [ERROR] collect_descriptives.jl failed. & set "OVERALL_RC=1" )

echo.
if "%OVERALL_RC%"=="0" (
    echo ============================================================
    echo  Done. Table: %~dp0doc\pharmacy_descriptives.csv
    echo ============================================================
) else (
    echo One or more steps FAILED. See logs under "%LOG_DIR%".
)
endlocal & exit /b %OVERALL_RC%
