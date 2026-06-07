#!/usr/bin/env bash
# One sweep instance: run_one_sweep.sh <REGION> <FUNC>
# Reads ROUNDING from env (default multistart). Logs to logs/sweep_<REGION>_<FUNC>.log.
region="$1"; func="$2"
log="logs/sweep_${region}_${func}.log"
start=$(date +%s)
echo "[start $(date +%H:%M:%S)] $region $func -> $log"
COUNTRIES="$region" TRAVEL_FUNC="$func" ROUNDING="${ROUNDING:-multistart}" \
  julia --startup-file=no lambda_sweep_simplex.jl > "$log" 2>&1
rc=$?
echo "[done  $(date +%H:%M:%S)] $region $func (exit $rc, $(( $(date +%s) - start ))s)"
