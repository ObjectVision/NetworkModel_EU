# TODO — short-term issues to process in the next recalculation

Consolidated from: the methodology draft (`doc/cjc_20260628_Exploring local bandwidths
of physical access to services_LD.docx`), the deck roadmap page (`lambda_sweep5.pptx`,
2nd-last slide), the mail thread "How to assess the current distribution"
(Chris 24 Jun 2026, agreed by Lewis), and the DK/ITG/FRM/SE2 sweep diagnosis.

## A. Input / search-space changes (agreed — do first, they change every downstream number)

0. legend of pareto frontier curves;
   - remove green curves
   - log(facility const weight)
   - cost lowerbound, dashed and on top of
   - cost upperbound
   - check if both bounds are shown
0a Update Italian data, aka #46
0b interpolate better the locations of S1 and S2, which sligtly conflicts with
0c make available to Chris the resulting facility locations for S1 and S2 for each region, for use in the GeoDMS, aka #45
0d describe the fractional selection algorithm, aka #47

1. ✅ *(implemented 2-Jul, commit 7c6768f — recalc batch running via `run_recalc_batch.ps1`;
   also fixed: the candidate set's CountCurrentObjects was joined against SCHOOLS, so the
   OD's nearest-5-current-facilities limit counted school cells in pharmacy runs)*
   **Restrict the candidate set to grid cells with ≥ 50 inhabitants, plus all cells that
   currently contain a pharmacy.**
   Agreed in the 24-Jun thread (Chris: ≥50 keeps ~98% of pharmacy locations, shrinks the
   search space from ~7.5% to ~2.9% of EU cells; Lewis: "allocating all pharmacies to grid
   cells with more than 50 people is the best option"). The methodology draft (§2.2.1)
   states the same rule: *"grid cells that contain a pharmacy currently, or have at least
   50 inhabitants."*
   - Current state: `ModelParameters.dms` `MinPopSizeVoorPotentialSchoolLocation := 1`
     (i.e. all inhabited cells) and `NewPharmacyLocations` does **not** union in the
     existing-pharmacy cells.
   - Change: threshold 1 → 50 for the pharmacy runs **and** union
     `Pharmacies/within_StudyArea/uq_cells` into the candidate set (the ~2% of pharmacies
     in <50-pop cells must stay reachable/selectable).
   - Consequences: **delete the stale NewPharmacies `FinalSet_*.mmd` per area** (GeoDMS
     silently skips rewriting), rebuild network1/network2 + alloc, re-sweep. Bonus: the
     LP shrinks ~2.5×, so sweeps get materially cheaper (helps Poland, §C6).

2. ✅ *(implemented 2-Jul — `Client := 'population'`; pilot Luxembourg: client population
   now exactly the 634,435 residents; Existing OD 5.4k→8.0k rows, New OD 76k→119k;
   both network sides rebuilt per area in the recalc batch. Switch back to
   'pop_primaryschool' for school runs.)*
   **Clients = whole population for pharmacy runs.**
   Methodology §2.1: *"for pharmacies the entire population is expected to contribute to
   demand."* Currently `ModelParameters/Client := 'pop_primaryschool'`, so the OD client
   set only contains cells with school-age children (LP weights are already `total_pop`,
   but cells without 6–12-year-olds are missing as clients entirely, and the road
   descriptives only cover OD-client cells).
   - Change: `Client := 'population'`; rebuild ODs together with item 1.

## B. Consistency fixes exposed by the DK / ITG / FRM / SE2 investigation

3. ✅ *(implemented 5-Jul in lambda_sweep_simplex.jl baseline_metrics — unreachable
   clients (in the candidate OD, absent from the existing OD) priced like the scenarios:
   BIG = 1.0 for LOGISTIC, c(t_max of the data) otherwise; count/pop reported per region.
   Effective at the next full rerun. Note: after A2, stranding is near-zero in most
   regions — the islands remain.)*
   **Coverage-consistent baseline.** `baseline_metrics` silently drops clients that cannot
   reach any existing pharmacy within t_max (DK ~11% of residents, ITG ~15%, SE2 ~5% —
   islands/sparse interior), while the LP must serve everyone. Price the dropped clients
   at c(t_max) in the baseline so the ★ and the frontier are comparable (DK baseline
   travel roughly doubles). Same fix listed on the roadmap ("Fix baseline_metrics").

4. ✅ *(implemented 5-Jul — fixed COMMON grid 1-2-5 per decade, 1e-4…5.0, identical for
   every region with NO early stop (the old travel_c>baseline stop truncated the
   aggregate at one region's exit, e.g. Belgium w=0.1), plus a region-specific upward
   extension (×2.5, plateau-detected) until S1 brackets. Validated: FRM S1 now brackets
   at (0.1,0.2). Effective at the next full rerun — then the aggregate has full common-λ
   support.)*
   **Extend the w-grid upward** (currently tops out at w = 0.5, λ = €50k). In all three
   regions sum_x was still falling at the top of the grid, so S1 was never bracketed
   ("—" in the interpolated-λ tables; DK floor 459 vs target 444 — nearly there).
   Cheap: append w ∈ {1, 2, 5, …} until sum_x floors or brackets the baseline count.

5. **Exact S1/S2 instead of interpolation** (roadmap: "better estimations for S1 and S2").
   The LP relaxation is nearly integral (frac_x small), so branch-and-bound is cheap:
   - S1: solve the p-median MIP (binary x + Σx = p, p = baseline count) per region.
   - Make coverage **soft** in the MIP too — a stranding variable per client priced at
     c(t_max) — so S1 stays well-defined below the full-coverage floor (ITG/SE2 are
     structural: no λ ever reaches the baseline count under hard coverage).
   - Optionally an ε-constraint window over p around the baseline for the local frontier.

6. **Review the OD sparsity rule** (flagged on deck p. 3, feedback requested): each client
   is connected up to its **5 nearest existing-facility locations**
   (`max_nr_facilities_per_client := 5`) or 120 min (`max_traveltime_to_facility`).
   At S2-level facility counts the 5-nearest choice set can bind (all of a client's
   candidates closed while a 6th could serve it). Decide with the group whether 5 is
   enough — raising it enlarges the OD roughly linearly.

## C. Scenario / run extensions

7. ✅ *(done 4/5-Jul — all 7 PL NUTS-1 swept; country-level Poland retried and completed
   under the shrunken candidate set: N=15.1M OD rows, M=90,941; LINEAR 29h + LOGISTIC 3.3h;
   S1 −18.8% travel at ≈same count, S2 −0.15% travel with 26.6% fewer facilities.
   Aggregate uses the 7 NUTS-1, excluding country-Poland for disjointness.)*
   **Poland**: country-level sweep was held (too heavy). Run the 7 PL NUTS-1 sweeps
   (networks + ODs already prepared); after item 1 shrinks the candidate set, retry
   country-level Poland as well. Roadmap bullet "Calculating Poland".

8. ✅ *(implemented 2-Jul, commit 7c6768f — settings.jl defaults now midpoint 25 / scale 10,
   env-overridable via LOGISTIC_MIDPOINT/LOGISTIC_SCALE; deck page relabelled; LOGISTIC
   sweeps re-running in the recalc batch)*
   **Adapted logit travel-cost function** (roadmap; deck has a comparison page):
   decide parameters with the group — current LOGISTIC is midpoint 30 / scale 15 min;
   the proposed alternative (midpoint 25 / scale 10) tracks Lewis's ~5 & ~45-min kinks;
   the methodology draft (§2.1) specifies a **log-logistic** transform. Align the draft,
   `settings.jl c(t)`, and the deck, then re-sweep the LOGISTIC variants.

9. (deleted handling border-cases)

## D. Reporting / documentation after the recalculation

10. ✅ *(done 5-Jul — descriptives re-run on the rebuilt Existing ODs (full-population
    clients; Iceland dropped from the loop: it HANGS under the new config); deck
    regenerated: 61 slides, 42 region pages incl. Poland + PL NUTS-1, plus a NEW
    aggregated-frontier page after the region pages — facilities & travel summed per
    common λ over the 41 disjoint areas, exact by separability, log-interpolated onto
    the union w-grid; aggregate S1/S2 not bracketed until the w-grid is extended (#4).)*
    **Regenerate** the road-based descriptives (pages 5–8), all sweeps, the interpolated-λ
    tables and the deck (`build_deck_data.py → build_charts.py → build_deck.mjs →
    merge_deck.ps1`).

11. **Correlate catchment size with travel costs** (roadmap bullet "Corr catchment &
    travel costs") — now cheap post-processing on the per-region arrows.

12. ✅ *(done 10-Jul — the draft now matches the implementation end-to-end: §2.2.2 rewritten
    to the multistart rounding (top-p + CELF-greedy + Efraimidis–Spirakis A-Res x*-weighted
    seeds + Resende–Werneck swap search, incl. the ∝x_j proof; References section added);
    assumptions switched to SOFT coverage (Σy ≤ 1, unserved demand priced at f(t_max) —
    matching the 10-Jul solver change); objective corrected to
    C = Σ f(t)·Q·y + f(t_max)·Q·(1−Σy) + λ·β0·Σx, with the β1·S_j load term explicitly
    noted as omitted (≈constant under (near-)full assignment); "log-logistic" → logistic
    (midpoint 25 / scale 10) in all 3 places; OD sparsity rule stated precisely (all
    candidates up to the 5th-nearest EXISTING facility, 120-min cap); solver per variant
    (warm-started dual simplex LINEAR, IPM-no-crossover LOGISTIC); λ-grid (1-2-5/decade,
    per travel function, bisection refinement) and the coverage-consistent baseline in the
    S1/S2 section.)*
    **Align the methodology draft with the implemented solver**: §2.2.2 still describes the
    older randomized-threshold rounding; the implemented method is multistart (top-p +
    CELF-greedy + x*-weighted seeds, swap local search, coverage-honest scoring at
    c(t_max)) with p = round(Σx*). Also note there that the facility-cost load term
    β₁·Sⱼ only cancels under full assignment — with soft coverage (item 5) it no longer
    does exactly.
