# Lambda-sweep results deck — generation pipeline

The per-region results deck (`lambda_sweep5.pptx`) is **generated from the sweep logs**,
not hand-edited. Concept slides 1–4 are carried over from `lambda_sweep4.pptx`; the
region slides and the summary are regenerated.

## Run order (from `doc/`)

```bash
# 1. parse logs/sweep_<region>_<FUNC>.log  ->  doc/deck_data.json
PYTHONIOENCODING=utf-8 python build_deck_data.py

# 2. render the per-region charts  ->  doc/charts/<region>_<FUNC>.png   (matplotlib)
PYTHONIOENCODING=utf-8 python build_charts.py

# 3. assemble region + summary slides  ->  doc/region_summary.pptx      (Node + pptxgenjs)
npm install        # first time only (installs pptxgenjs locally)
node build_deck.mjs                 # flags: --only <REGION>, --no-summary, --out <file>

# 4. merge concept slides 1-4 + new slides  ->  doc/lambda_sweep5.pptx  (PowerPoint COM)
powershell -ExecutionPolicy Bypass -File merge_deck.ps1
```

## What each region chart shows  (per `build_charts.py`)

x = `sum_x` (LP-relaxed facility count). Two charts per region: LINEAR | LOGISTIC.

- **left axis** — total travel cost: `travel_relax` (LP lower bound, dashed grey) and
  `travel_multi` (multistart, solid blue). `travel_topp` / `travel_greedy` are intentionally omitted.
- **2nd left axis** — `frac_x` (count of fractional x-variables), green, shaded.
- **right axis** — `log₁₀(w)` (the sweep weight used at each point), amber dashed.
- **★ baseline** = current network at `(cells, cost)`; **◆ S1**, **■ S2** on the multistart curve.
- LINEAR y starts at 0; **LOGISTIC y is stretched** to the data (non-zero origin) so the
  small relax↔multi gap is visible.

## Notes
- Rendering / QA on this machine (no LibreOffice): PowerPoint COM `Slide.Export(png,"PNG",1600,900)`.
- `merge_deck.ps1` never calls `$pp.Quit()` — COM may attach to a running PowerPoint where
  the base deck is open, and Quit would close the user's session. It edits a temp **copy**.
- `doc/node_modules`, `doc/charts`, `doc/region_summary.pptx` are git-ignored (regenerated).
- Methodology: see the project memory (greedy-rounding, parse-compare). Sweep logs are the
  inputs; regenerate them only when re-running the optimisation (slow).
