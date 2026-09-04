// Assemble the lambda-sweep region slides from doc/deck_data.json + the matplotlib
// charts in doc/charts/ (rendered by build_charts.py).
// Each region slide: header, baseline strip, two embedded charts (LINEAR | LOGISTIC),
// an S1/S2 stats table, and a closing LINEAR-vs-LOGISTIC summary slide.
//
//   node build_deck.mjs [--only FR1] [--no-summary] [--out region_summary.pptx]
//
import pptxgen from "pptxgenjs";
import { readFileSync, existsSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const __dir = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const only = args.includes("--only") ? args[args.indexOf("--only") + 1] : null;
const outName = args.includes("--out") ? args[args.indexOf("--out") + 1] : "region_summary.pptx";
const data = JSON.parse(readFileSync(join(__dir, "deck_data.json"), "utf-8"));

// ---- palette ----------------------------------------------------------------
const INK = "12233A", NAVY = "1C3D5A", MULTI = "0B6E99", RELAX = "9AA7B4";
const BASE = "5B6B7B", PANEL = "F2F5F8", MUTED = "5B6B7B", TOPP = "E8A33D";

const pptx = new pptxgen();
pptx.defineLayout({ name: "W", width: 13.333, height: 7.5 });
pptx.layout = "W";
pptx.theme = { headFontFace: "Georgia", bodyFontFace: "Calibri" };

const fmtCost = (v) => {
  if (v == null) return "—";
  if (v >= 1e8) return (v / 1e6).toFixed(0) + "M";
  if (v >= 1e6) return (v / 1e6).toFixed(1) + "M";
  if (v >= 1e3) return (v / 1e3).toFixed(0) + "k";
  return v.toFixed(0);
};
const pct = (a, b) => (b ? (100 * (a - b) / b) : 0);
const spct = (v) => (v >= 0 ? "+" : "") + v.toFixed(0) + "%";

function regionSlide(e) {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText(e.title, { x: 0.45, y: 0.26, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: e.name + "  ", options: { bold: true, color: INK } },
    { text: "— multistart vs the LP-relax frontier", options: { color: NAVY } },
  ], { x: 0.45, y: 0.52, w: 12.4, h: 0.5, fontSize: 22, fontFace: "Georgia" });

  const bl = e.func.LINEAR.baseline, bg = e.func.LOGISTIC.baseline;
  slide.addText([
    { text: "baseline (current)  ", options: { bold: true, color: NAVY } },
    { text: `${bl.cells.toLocaleString()} cells · ${bl.mean_t.toFixed(2)} min mean · `, options: { color: INK } },
    { text: `travel (stranded at BIG)  LIN ${fmtCost(bl.cost)} · LOG ${fmtCost(bg.cost)}`, options: { color: MUTED } },
  ], { x: 0.45, y: 1.16, w: 12.4, h: 0.3, fontSize: 10, fontFace: "Calibri" });

  // two embedded charts
  const cy = 1.6, cw = 5.85, chh = 3.44;
  for (const [fn, x] of [["LINEAR", 0.32], ["LOGISTIC", 6.42]]) {
    const p = join(__dir, "charts", `${e.region}_${fn}.png`);
    if (existsSync(p)) slide.addImage({ path: p, x, y: cy, w: cw, h: chh });
    else slide.addText(`${fn}: chart missing`, { x, y: cy, w: cw, h: chh, align: "center", valign: "middle", italic: true, color: MUTED });
  }

  // S1/S2 stats table (top-p / greedy dropped)
  const head = ["", "scenario", "w", "n_open", "frac", "multi vs relax", "stranded (multi)"];
  const body = [head];
  const mk = (fn, fd) => {
    for (const pt of ["S1", "S2"]) {
      const d = fd.scen[pt];
      if (!d) continue;
      body.push([pt === "S1" ? fn : "", pt, (+d.w).toPrecision(3), String(d.n_open), String(d.frac),
        spct(pct(d.multi, d.relax)), String((d.st || [0, 0, 0])[2])]);
    }
  };
  mk("LINEAR", e.func.LINEAR);
  mk("LOGISTIC", e.func.LOGISTIC);
  const tRows = body.map((row, ri) => row.map((c, ci) => ({
    text: c, options: {
      fontSize: ri === 0 ? 9 : 10, bold: ri === 0, align: ci <= 1 ? "left" : "center",
      color: ri === 0 ? "FFFFFF" : INK, fill: ri === 0 ? NAVY : (ri % 2 ? PANEL : "FFFFFF"),
      fontFace: "Calibri", valign: "middle",
    },
  })));
  slide.addTable(tRows, {
    x: 0.5, y: 5.5, w: 12.33, colW: [1.5, 1.1, 1.5, 1.6, 1.4, 2.6, 2.63],
    rowH: 0.3, border: { type: "solid", color: "D9E0E7", pt: 0.5 }, valign: "middle",
  });
  slide.addText("Charts: cost lowerbound (LP relaxation, dashed grey — drawn on top) & cost upperbound (multistart integer solution, solid blue) on the left; log₁₀(facility cost weight €) on the right, vs sum_y; ★ baseline, ◆ S1, ■ S2.  Lower ≤ integer optimum ≤ upper; stranded clients priced at BIG (120 min linear / 1.0 logistic) — in the baseline too (coverage-consistent).",
    { x: 0.5, y: 7.12, w: 12.33, h: 0.3, fontSize: 8.5, italic: true, color: MUTED, fontFace: "Calibri" });
}

// Aggregate frontier over all disjoint areas (doc/agg_data.json, written by
// build_charts.py render_aggregate): per common w, #facilities and travel are SUMMED
// across areas — exact for the combined problem because the objective separates by
// area at a common λ. Shown right after the individual region slides.
function aggregateSlide() {
  const p = join(__dir, "agg_data.json");
  if (!existsSync(p)) { console.log("(no agg_data.json — skipping aggregate slide)"); return; }
  const agg = JSON.parse(readFileSync(p, "utf-8"));
  const L = agg.LINEAR, G = agg.LOGISTIC;
  if (!L || !G) { console.log("(agg_data incomplete — skipping aggregate slide)"); return; }

  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText(`ALL AREAS COMBINED · ${L.n_regions} DISJOINT AREAS`, { x: 0.45, y: 0.26, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "The aggregated frontier  ", options: { bold: true, color: INK } },
    { text: "— facilities and travel cost summed per λ", options: { color: NAVY } },
  ], { x: 0.45, y: 0.52, w: 12.4, h: 0.5, fontSize: 22, fontFace: "Georgia" });

  slide.addText([
    { text: "aggregate baseline (current)  ", options: { bold: true, color: NAVY } },
    { text: `${L.baseline.cells.toLocaleString()} pharmacy cells · `, options: { color: INK } },
    { text: `travel  LIN ${fmtCost(L.baseline.cost)} · LOG ${fmtCost(G.baseline.cost)}`, options: { color: MUTED } },
  ], { x: 0.45, y: 1.16, w: 12.4, h: 0.3, fontSize: 10, fontFace: "Calibri" });

  const cy = 1.5, cw = 5.19, chh = 3.05;   // 9 table rows + footnote must fit below
  for (const [fn, x] of [["LINEAR", 0.62], ["LOGISTIC", 6.9]]) {
    const cp = join(__dir, "charts", `AGGREGATE_${fn}.png`);
    if (existsSync(cp)) slide.addImage({ path: cp, x, y: cy, w: cw, h: chh });
  }

  const head = ["", "point", "w", "n_open", "Δ facilities", "multi vs relax", "Δ travel (multi)"];
  const body = [head];
  for (const [fn, A] of [["LINEAR", L], ["LOGISTIC", G]]) {
    const pts = [];
    if (A.S1) pts.push(["S1 (same count)", A.S1]);
    if (A.S2) pts.push(["S2 (same travel)", A.S2]);
    pts.push(["fewest facilities swept", A.few]);
    pts.push(["most facilities swept", A.many]);
    pts.forEach(([lab, d], i) => {
      body.push([i === 0 ? fn : "", lab, (+d.w).toPrecision(3), Math.round(d.n_open).toLocaleString("en-US"),
        spct(pct(d.n_open, A.baseline.cells)), spct(pct(d.multi, d.relax)), spct(pct(d.multi, A.baseline.cost))]);
    });
  }
  const tRows = body.map((row, ri) => row.map((c, ci) => ({
    text: c, options: {
      fontSize: ri === 0 ? 8.5 : 9, bold: ri === 0, align: ci <= 1 ? "left" : "center",
      color: ri === 0 ? "FFFFFF" : INK, fill: ri === 0 ? NAVY : (ri % 2 ? PANEL : "FFFFFF"),
      fontFace: "Calibri", valign: "middle",
    },
  })));
  slide.addTable(tRows, {
    x: 0.5, y: 4.7, w: 12.33, colW: [1.2, 2.5, 1.3, 1.5, 1.6, 2.1, 2.13],
    rowH: 0.235, border: { type: "solid", color: "D9E0E7", pt: 0.5 }, valign: "middle",
  });
  const unbr = [ !L.S1 && "S1", !L.S2 && "S2" ].filter(Boolean).join("/");
  slide.addText(`Exact-by-separability aggregation over ${L.n_regions} disjoint areas (13 countries + FR/IT/SE/PL NUTS-1; country-level Poland excluded in favour of its 7 NUTS-1): at a common λ the sum of the regional optima IS the combined optimum. Summed at the union of swept w-values inside the range every area covers (${L.n_w} points; an area without that exact λ is log-interpolated between its adjacent sweep points — the λ-table rule).` +
    ` The Δ columns state the aggregate S1/S2 gain in native units and need no λ; λ only prices them (placeholder €100,000 per location).` +
    (unbr ? ` ${unbr} not bracketed: the aggregate baseline (★) lies outside the common λ range, which is capped by the slowest regions' sweep limits (LINEAR: Belgium & FRI time out above w = 0.2) — extending those two sweeps closes it; final frontier segment to follow.` : ""),
    { x: 0.5, y: 6.9, w: 12.33, h: 0.55, fontSize: 8.3, italic: true, color: MUTED, fontFace: "Calibri" });
}

function summarySlide() {
  const slide = pptx.addSlide();
  slide.background = { color: INK };
  slide.addText("LINEAR vs LOGISTIC", { x: 0.5, y: 0.32, w: 9, h: 0.3, fontSize: 12, bold: true, color: TOPP, charSpacing: 2 });
  slide.addText("multistart tracks the LP-relax lower bound — the gap is tightest under LOGISTIC",
    { x: 0.5, y: 0.6, w: 12.3, h: 0.7, fontSize: 24, color: "FFFFFF", fontFace: "Georgia" });

  const card = (x, head, big, sub, tint) => {
    slide.addShape(pptx.ShapeType.roundRect, { x, y: 1.5, w: 6.0, h: 1.35, rectRadius: 0.06, fill: { color: "1B3350" }, line: { color: tint, width: 1 } });
    slide.addText(head, { x: x + 0.25, y: 1.62, w: 5.5, h: 0.3, fontSize: 13, bold: true, color: tint, fontFace: "Calibri" });
    slide.addText(big, { x: x + 0.25, y: 1.92, w: 5.5, h: 0.5, fontSize: 19, bold: true, color: "FFFFFF", fontFace: "Georgia" });
    slide.addText(sub, { x: x + 0.25, y: 2.4, w: 5.55, h: 0.4, fontSize: 10.5, color: "C7D2DD", fontFace: "Calibri" });
  };
  card(0.5, "LINEAR  c(t) — unbounded, stranding expensive", "multistart sits +0–18% over the LP bound",
    "integer rounding costs more where stranding is dear", TOPP);
  card(6.83, "LOGISTIC  c(t) — saturates ≈1, stranding cheap", "multistart sits +0–4.7% over the LP bound",
    "rounding is nearly free; the frontier is almost integral", MULTI);

  // condensed comparison: cell = multi-vs-relax %  (multistart stranded), two blocks of 11
  const head = ["reg", "LIN S1", "LIN S2", "LOG S1", "LOG S2"];
  const cell = (scen) => scen ? `${spct(pct(scen.multi, scen.relax))} (${(scen.st || [0, 0, 0])[2]})` : "—";
  const mkBlock = (slice) => {
    const body = [head.map((h) => ({ text: h, options: { bold: true, color: "FFFFFF", fill: NAVY, fontSize: 9, align: h === "reg" ? "left" : "center", fontFace: "Calibri", margin: [1, 2, 1, 3] } }))];
    slice.forEach((e, i) => {
      const L = e.func.LINEAR, G = e.func.LOGISTIC;
      const cells = [e.region, cell(L?.scen?.S1), cell(L?.scen?.S2), cell(G?.scen?.S1), cell(G?.scen?.S2)];
      body.push(cells.map((c, ci) => ({
        text: c, options: {
          fontSize: 9, align: ci === 0 ? "left" : "center", bold: ci === 0,
          color: ci === 0 ? "FFFFFF" : "DDE6EF", fill: i % 2 ? "163052" : "12233A", fontFace: "Calibri", valign: "middle", margin: [1, 2, 1, 3],
        },
      })));
    });
    return body;
  };
  const half = Math.ceil(data.length / 2);
  const colW = [0.95, 1.27, 1.27, 1.27, 1.27];
  slide.addTable(mkBlock(data.slice(0, half)), { x: 0.5, y: 3.5, w: 6.03, colW, rowH: 0.27, border: { type: "solid", color: "2A4565", pt: 0.5 }, valign: "middle" });
  slide.addTable(mkBlock(data.slice(half)), { x: 6.8, y: 3.5, w: 6.03, colW, rowH: 0.27, border: { type: "solid", color: "2A4565", pt: 0.5 }, valign: "middle" });
  slide.addText("cell = multistart travel above the LP-relax bound  (multistart clients stranded by rounding, priced at BIG).  Sparse Swedish regions keep the largest bound-gaps.",
    { x: 0.5, y: 7.12, w: 12.33, h: 0.3, fontSize: 8.5, italic: true, color: "9FB0C2", fontFace: "Calibri" });
}

function statusSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText("ROADMAP", { x: 0.45, y: 0.28, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "Status against Lewis's & Bernhard's framing  ", options: { bold: true, color: INK } },
    { text: "— implemented · remaining · not pursued", options: { color: NAVY } },
  ], { x: 0.45, y: 0.54, w: 12.5, h: 0.42, fontSize: 21, fontFace: "Georgia" });
  slide.addText([
    { text: "The λ-sweep is the working general method. ", options: { bold: true, color: INK } },
    { text: "Two method changes since the previous deck — landbody-complete networks and NUTS region exclusion — make these figures NOT comparable with earlier ones. The REGIO review (Moreno Monroy, Brons, Nöbauer) is worked in where it asked for answers and listed below where it asked for work. Status confirmed 4 Sep 2026: nothing is mid-flight, so the list is what is done and what remains, in priority order.", options: { color: MUTED } },
  ], { x: 0.45, y: 0.97, w: 12.5, h: 0.4, fontSize: 9.5, fontFace: "Calibri", valign: "top" });

  const GREEN = "1E7A52", SLATE = "5B6B7B", AMBER = "B9791C";
  const col = (x, w, tint, fill, title, items, fs = 9) => {
    slide.addShape(pptx.ShapeType.roundRect, { x, y: 1.42, w, h: 4.7, rectRadius: 0.05, fill: { color: fill }, line: { color: tint, width: 1 } });
    slide.addText(title, { x: x + 0.18, y: 1.5, w: w - 0.36, h: 0.3, fontSize: 13, bold: true, color: tint, fontFace: "Calibri" });
    slide.addText(items.map((t) => ({ text: t, options: { bullet: { indent: 12 }, breakLine: true } })),
      { x: x + 0.2, y: 1.86, w: w - 0.4, h: 4.2, fontSize: fs, color: INK, fontFace: "Calibri", lineSpacingMultiple: 0.98, paraSpaceAfter: 4, valign: "top" });
  };
  // Status as confirmed item by item on 4 Sep 2026: nothing is in progress except the
  // λ-communication thread, so two columns — done, and remaining in priority order — and
  // a one-line record of what was dropped, so the reviewers who asked for it see the answer.
  col(0.4, 6.2, GREEN, "F0F6F2", "Implemented ✓", [
    "NETWORK per landbody + REGION EXCLUSION (>50% of inhabitant locations unreachable → NUTS region dropped, population AND candidates): ITG mean travel 22.3 → 4.9 min; Azores/Madeira out, Portugal baseline travel −62%. A DATA gap no longer ranks as headroom (p8)",
    "Tabula-rasa LP allocation + λ-sweep → Pareto curve of #locations vs travel (Option D); p-median notation (x = assignment, y = facility)",
    "S1 (same #, ↓travel) · S2 (same travel, ↓#) · S3 full frontier — S1/S2 interpolated onto the frontier, stated in NATIVE units first, € second (p60–61)",
    "Lewis's 6 descriptive indicators per country and key NUTS1, catchments by ROAD travel time — ahead of the model (p3–6)",
    "Candidates = ≥50-pop cells ∪ pharmacy cells · clients = FULL population · adapted logit (25/10) — all 42 areas swept incl. Poland + 7 NUTS-1",
    "Soft coverage (Σx ≤ 1, unserved priced at BIG on BOTH sides): every region brackets S1 & S2; baseline coverage-consistent",
    "Aggregated frontier over 41 disjoint areas (exact by separability), bracketing S1 and S2 for both functions (p59)",
    "Improvement rectangle (raw + relative), diagonal crossing + λ, point-cloud with projections; ranked lists by policy typology, free of coverage artefacts (ITF #1 on an UNCHANGED value)",
    "REGIO review worked in: choice set (p9), λ-tangency (p10), logistic parametrised (p64), bounds on TOTAL cost only (p12), €100,000 a placeholder everywhere",
    "Large-region subsampling keeps EVERY baseline location, so the frontier still dominates the baseline",
  ]);
  col(6.75, 6.2, SLATE, "F2F5F8", "Remaining ○ — in priority order  (◐ = in progress)", [
    "◐ Communicate λ intuitively (person-minutes per location): the tangency slide (p10) and the native-unit S1/S2 tables (p60–61) are the first steps; the € labels stay placeholders until a is calibrated",
    "Widen the CANDIDATE radius per client (5 → 10 nearest EXISTING), one area first — measured to bind at S2 (SE2: 10.2% of residents one closure from stranding, p9)",
    "RSSV spatial-voting candidate reduction (Avignon CpLP paper, Figueiredo & Genre-Grandpierre) — a principled replacement for the stride subsample on the largest regions; needs the wider radius first",
    "Exact soft-coverage p-median MIP to pin S1/S2 at p = baseline — also replaces the nearest-grid-point snap that makes S1 = S2 in 5 areas (FRC/FRH/FRJ/FRK/SE2, p9)",
    "Territorial coverage constraints (≥1 pharmacy per NUTS unit; multi-scale) as a STRUCTURED equity lever alongside the soft-coverage BIG penalty",
    "DECIDE: rescale the logistic so c(0) and c(60) match the linear (BN, 23 July) — less degeneracy, but it changes the equity weighting the logistic was chosen for (p64)",
    "Calibrate the real pharmacy fixed cost a (schools: 99 699 + 3 277.5x) — only the € labels move, nothing else in the deck",
    "Capacity / max-catchment cap constraint (CpMP; the Avignon strengthened ILP shows how to solve it)",
    "Counterfactuals: −10% pop · replace a known X% · choose which X to close (hard)",
  ]);

  slide.addText([
    { text: "Not pursued (decided 4 Sep 2026):  ", options: { bold: true, color: AMBER } },
    { text: "the catchment-cap / min-threshold ladder (explored on the Netherlands; p15 kept as the record) · age-weighted demand · candidate cells plus their neighbours · urban/non-urban split and a settlement candidate set · flat-then-linear cost and logit-parameter sensitivity · pharmacist-based and pooled caps, catchment–travel correlation, border cases.", options: { color: MUTED } },
  ], { x: 0.45, y: 6.2, w: 12.5, h: 0.45, fontSize: 9, fontFace: "Calibri", valign: "top" });
  slide.addText([
    { text: "Open questions for the group:  ", options: { bold: true, color: NAVY } },
    { text: "widen the choice set before RSSV (p9)?  ·  logistic vs linear, and BN's rescaling (p64)?  ·  territorial coverage constraints for equity, or keep soft coverage?", options: { color: MUTED } },
  ], { x: 0.45, y: 6.68, w: 12.5, h: 0.5, fontSize: 10, italic: true, fontFace: "Calibri", valign: "top" });
}

function logisticSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  const CUR = "185FA5", ALT = "1D9E75";
  slide.addText("TRAVEL-COST FUNCTION", { x: 0.45, y: 0.28, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "Logistic c(t)  ", options: { bold: true, color: INK } },
    { text: "— the adopted Lewis-tuned curve vs the previous one", options: { color: NAVY } },
  ], { x: 0.45, y: 0.54, w: 12.5, h: 0.5, fontSize: 22, fontFace: "Georgia" });

  const p = join(__dir, "charts", "logistic_compare.png");
  if (existsSync(p)) slide.addImage({ path: p, x: 0.35, y: 1.55, w: 7.8, h: 4.21 });

  // right panel: parameters + value table + note
  slide.addText([{ text: "previous", options: { bold: true, color: CUR } }, { text: "   midpoint 30 · scale 15", options: { color: MUTED } }],
    { x: 8.4, y: 1.6, w: 4.6, h: 0.28, fontSize: 12, fontFace: "Calibri" });
  slide.addText([{ text: "adopted", options: { bold: true, color: ALT } }, { text: "   midpoint 25 · scale 10", options: { color: MUTED } }],
    { x: 8.4, y: 1.92, w: 4.6, h: 0.28, fontSize: 12, fontFace: "Calibri" });

  const tbl = [["t (min)", "previous", "adopted"],
    ["0", "0.12", "0.08"], ["5", "0.16", "0.12"], ["15", "0.27", "0.27"],
    ["25", "0.42", "0.50"], ["30", "0.50", "0.62"], ["45", "0.73", "0.88"], ["60", "0.88", "0.97"]];
  const rows = tbl.map((r, ri) => r.map((cval, ci) => ({
    text: cval, options: {
      fontSize: ri === 0 ? 10 : 11, bold: ri === 0, align: "center",
      color: ri === 0 ? "FFFFFF" : (ci === 1 ? CUR : ci === 2 ? ALT : INK),
      fill: ri === 0 ? NAVY : (ri % 2 ? PANEL : "FFFFFF"), fontFace: "Calibri", valign: "middle",
    },
  })));
  slide.addTable(rows, { x: 8.4, y: 2.42, w: 4.55, colW: [1.45, 1.55, 1.55], rowH: 0.3, border: { type: "solid", color: "D9E0E7", pt: 0.5 }, valign: "middle" });

  slide.addText([
    { text: "Both cross at ≈15 min (0.27). ", options: { color: INK } },
    { text: "The adopted curve is lower below ~10 min (ignores minor relocations) and saturates by ~45 min (caps remote weight) — Lewis's 22-May ask. Applied in the recalculation (settings.jl defaults; previous variant via LOGISTIC_MIDPOINT=30 LOGISTIC_SCALE=15).", options: { color: MUTED } },
  ], { x: 8.4, y: 4.7, w: 4.6, h: 1.05, fontSize: 10, italic: true, fontFace: "Calibri", valign: "top" });

  // Review answers (REGIO comments 28, 35, 36): name the function, its value at 0, and
  // where the degeneracy Brons asks about actually comes from; table BN's rescaling.
  slide.addShape(pptx.ShapeType.roundRect, { x: 0.4, y: 5.92, w: 12.55, h: 1.05, rectRadius: 0.05, fill: { color: "F0F6F2" }, line: { color: "1E7A52", width: 1 } });
  slide.addText([
    { text: "Answers to the review.  ", options: { bold: true, color: "1E7A52" } },
    { text: "It is a plain logistic, not a log-logistic:  c(t) = 1 / (1 + e", options: { color: INK } },
    { text: "−(t−25)/10", options: { color: INK, superscript: true, fontSize: 7.5 } },
    { text: ").  It does not start at zero — c(0) = 0.076 — so a relocation within a few minutes is nearly free but not free; c(60) = 0.971, c(120) ≈ 1.  ", options: { color: INK } },
    { text: "The degeneracy: ", options: { bold: true, color: INK } },
    { text: "both variants sweep the same 1-2-5/decade λ-grid (1e-4 … 5), but c(t) here spans only 0.08–1 where the linear one spans 0–120, so the travel term is ~100× smaller relative to λ·#open. The aggregate’s useful λ-range is 1e-4 … 0.02 for logistic against 1e-4 … 0.5 for linear — that compression is the degeneracy: many λ values map to one solution.  ", options: { color: MUTED } },
    { text: "Open (BN, 23 Jul): ", options: { bold: true, color: "B9791C" } },
    { text: "rescale c(t) so c(0) and c(60) match the linear curve. It would spread the λ-range and reduce degeneracy, but it also changes the equity weighting the group chose the logistic for — a group decision, not a tuning.", options: { color: MUTED } },
  ], { x: 0.6, y: 5.98, w: 12.2, h: 0.95, fontSize: 8.6, fontFace: "Calibri", valign: "top", lineSpacingMultiple: 0.98 });

  slide.addText("c(t) is applied to travel time in minutes (raw OD seconds ÷ 60); LINEAR uses c(t)=t. settings.jl c(): logistic_midpoint=25, logistic_scale=10.",
    { x: 0.45, y: 7.05, w: 12.5, h: 0.3, fontSize: 8.5, italic: true, color: MUTED, fontFace: "Calibri" });
}

// view "pharm": residents per individual pharmacy (catchment split among the
// pharmacies sharing a cell). view "loc": residents per unique 1 km² location
// (pharmacies in a cell combined). Each renders the count, residents, the per-X
// mean and the p10..max distribution of the per-X catchment population.
function descriptivesSlide(csvName, view, eyebrow, subtitle) {
  const csv = join(__dir, csvName);
  if (!existsSync(csv)) { console.log(`(no ${csvName} — skipping descriptives slide)`); return; }
  const lines = readFileSync(csv, "utf-8").split(/\r?\n/).filter((l) => l.trim());
  if (lines.length < 2) { console.log(`(${csvName} empty — skipping)`); return; }
  const hdr = lines[0].split(","); const ix = {}; hdr.forEach((h, i) => (ix[h] = i));
  const rows = lines.slice(1).map((l) => l.split(","));
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText(eyebrow, { x: 0.45, y: 0.26, w: 11, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: (view === "pharm" ? "Residents per pharmacy  " : "Residents per 1 km² location  "), options: { bold: true, color: INK } },
    { text: subtitle, options: { color: NAVY } },
  ], { x: 0.45, y: 0.52, w: 12.5, h: 0.5, fontSize: 21, fontFace: "Georgia" });

  const COUNTRIES = new Set(["Austria", "Belgium", "Czechia", "Denmark", "Estonia", "France", "Iceland", "Ireland", "Italy", "Latvia", "Lithuania", "Luxembourg", "Netherlands", "Norway", "Poland", "Portugal", "Slovenia", "Sweden"]);
  const anyNuts = rows.some((r) => !COUNTRIES.has(r[ix.study_area]));  // are NUTS1 rows present?
  const nf = (v) => { const n = Number(v); return isFinite(n) ? Math.round(n).toLocaleString("en-US") : v; };
  const fM = (v) => { const n = Number(v); return isFinite(n) ? (n / 1e6).toFixed(1) + "M" : v; };
  const fs = rows.length <= 8 ? 12 : 8.5;
  const rowH = Math.max(0.205, Math.min(0.45, 5.2 / (rows.length + 1)));

  const P = view === "pharm"
    ? { cnt: "n_pharmacies",    per: "residents_per_pharmacy", d: "pharm_", cntLab: "pharm.",    perLab: "resid/ph" }
    : { cnt: "n_pharmacy_cells", per: "cell_avg",              d: "cell_",  cntLab: "locations", perLab: "resid/loc" };

  const head = ["region", P.cntLab, "residents", P.perLab, "#empty", "min>0", "p10", "p25", "p50", "p75", "p90", "max"];
  const body = [head.map((h) => ({ text: h, options: { bold: true, color: "FFFFFF", fill: NAVY, fontSize: Math.min(fs, 10), align: h === "region" ? "left" : "center", fontFace: "Calibri", margin: [1, 2, 1, 3] } }))];
  rows.forEach((r, i) => {
    const reg = r[ix.study_area]; const isC = COUNTRIES.has(reg); const hi = isC && anyNuts;
    const fill = hi ? "E6EDF4" : (i % 2 ? PANEL : "FFFFFF");
    const c = [(anyNuts && !isC ? "    " : "") + reg, nf(r[ix[P.cnt]]), fM(r[ix.n_residents]), nf(r[ix[P.per]]),
      nf(r[ix[P.d + "n_empty"]]), nf(r[ix[P.d + "min_nz"]]), nf(r[ix[P.d + "p10"]]), nf(r[ix[P.d + "p25"]]), nf(r[ix[P.d + "p50"]]), nf(r[ix[P.d + "p75"]]), nf(r[ix[P.d + "p90"]]), nf(r[ix[P.d + "max"]])];
    body.push(c.map((v, ci) => ({ text: v, options: {
      fontSize: fs, bold: hi, align: ci === 0 ? "left" : "center", color: INK,
      fill, fontFace: "Calibri", valign: "middle", margin: [1, 2, 1, 3] } })));
  });
  slide.addTable(body, { x: 0.5, y: 1.7, w: 12.33, colW: [1.85, 1.05, 1.08, 1.08, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.9, 0.97], rowH, border: { type: "solid", color: "D9E0E7", pt: 0.5 }, valign: "middle" });
  const empt = view === "pharm" ? "pharmacies" : "locations";
  const note = view === "pharm"
    ? "Catchment = residents whose nearest pharmacy BY ROAD-NETWORK travel time is this one (a cell's catchment split evenly among the pharmacies in it); p10..max = percentiles of that per-pharmacy catchment."
    : "A location = a unique 1 km² cell with ≥1 pharmacy; catchment = residents whose nearest pharmacy cell BY ROAD is this one; p10..max = percentiles of that per-location catchment.";
  const note2 = ` #empty = ${empt} that are never the road-nearest for any populated cell (fully shadowed / disconnected); min>0 = smallest non-zero catchment.`;
  slide.addText(note + note2 + (anyNuts ? " Country rows bold, NUTS1 indented below." : "") + " Source: pharmacy_descriptives.csv (road OD; Lewis, 22 May).",
    { x: 0.5, y: 7.12, w: 12.33, h: 0.3, fontSize: 8, italic: true, color: MUTED, fontFace: "Calibri" });
}

// Preliminary capacitated-ladder results (rungs A/B/C, no cost function) for one
// country, as one card per rung — real numbers where cap_results_<country>.csv
// (collect_cap.py) has a row, "run pending" otherwise. Placed right before the
// region (Pareto-frontier) slides so it precedes NL's.
function capSlide(csvName) {
  const csv = join(__dir, csvName);
  const lines = existsSync(csv) ? readFileSync(csv, "utf-8").split(/\r?\n/).filter((l) => l.trim()) : [];
  const data = {};
  if (lines.length >= 2) {
    const hdr = lines[0].split(","); const ix = {}; hdr.forEach((h, i) => (ix[h] = i));
    lines.slice(1).forEach((l) => { const f = l.split(","); data[f[ix.scen] + f[ix.rung]] = { f, ix }; });
  }
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText("PRELIMINARY · CATCHMENT-CAP LADDER (NO COST FUNCTION)", { x: 0.45, y: 0.26, w: 12, h: 0.3, fontSize: 12, bold: true, color: TOPP, charSpacing: 2 });
  slide.addText([
    { text: "Netherlands — five rungs, capping catchments instead of a cost function  ", options: { bold: true, color: INK } },
    { text: "— S1 fix #, ↓travel · S2 ↓#, hold travel", options: { color: NAVY } },
  ], { x: 0.45, y: 0.52, w: 12.5, h: 0.5, fontSize: 19, fontFace: "Georgia" });

  const nf = (v) => { const n = Number(v); return isFinite(n) ? Math.round(n).toLocaleString("en-US") : v; };
  const cards = [
    { key: "S1A", title: "S1 · A", rule: "max cap · multiple per cell" },
    { key: "S1B", title: "S1 · B", rule: "max cap · one per cell" },
    { key: "S1C", title: "S1 · C", rule: "urban fixed · model the rest" },
    { key: "S2A", title: "S2 · A", rule: "min + max cap · all facilities" },
    { key: "S2B", title: "S2 · B", rule: "min + max cap · outside urban" },
  ];
  const card = (x, y, w, h, c) => {
    const d = data[c.key];
    slide.addShape(pptx.ShapeType.roundRect, { x, y, w, h, rectRadius: 0.06, fill: { color: "F2F5F8" }, line: { color: d ? MULTI : "C9D2DB", width: 1 } });
    slide.addText(c.title, { x: x + 0.18, y: y + 0.11, w: w - 0.3, h: 0.3, fontSize: 15, bold: true, color: d ? MULTI : "8A98A6", fontFace: "Calibri" });
    slide.addText(c.rule, { x: x + 0.18, y: y + 0.45, w: w - 0.3, h: 0.3, fontSize: 9.5, italic: true, color: MUTED, fontFace: "Calibri" });
    if (!d) {
      slide.addText("full-scale run\npending", { x: x + 0.18, y: y + 0.95, w: w - 0.36, h: 0.9, fontSize: 12, color: "8A98A6", align: "center", valign: "middle", fontFace: "Calibri" });
      return;
    }
    const { f, ix } = d; const dt = Number(f[ix.dtravel_pct]); const scen = f[ix.scen];
    slide.addText([
      { text: (dt >= 0 ? "+" : "") + dt.toFixed(1) + "%", options: { bold: true, fontSize: 25, color: dt < 0 ? "1E7A52" : "B23A2E" } },
      { text: "  travel vs today", options: { fontSize: 10.5, color: MUTED } },
    ], { x: x + 0.18, y: y + 0.85, w: w - 0.3, h: 0.5, fontFace: "Georgia" });
    const lines2 = (scen === "S1"
      ? [`${nf(f[ix.n_pharm])} pharmacies · ${nf(f[ix.n_cells])} cells`,
         `${Number(f[ix.strand_pct]).toFixed(1)}% stranded · cap ${nf(f[ix.max_cap])}`]
      : [`${nf(f[ix.n_pharm])} pharmacies (was ${nf(f[ix.base])})`,
         `${Number(f[ix.strand_pct]).toFixed(1)}% stranded · min ${nf(f[ix.min_cap])}`])
      .concat(f[ix.urban_fx] !== "0" ? [`${nf(f[ix.urban_fx])} urban pharmacies fixed`] : []);
    slide.addText(lines2.map((t) => ({ text: t, options: { breakLine: true } })),
      { x: x + 0.18, y: y + 1.48, w: w - 0.3, h: 0.95, fontSize: 10, color: INK, fontFace: "Calibri", lineSpacingMultiple: 1.05, valign: "top" });
  };
  const cw = 4.07, ch = 2.5, gap = 0.2, x0 = 0.5;
  cards.slice(0, 3).forEach((c, i) => card(x0 + i * (cw + gap), 1.45, cw, ch, c));
  cards.slice(3).forEach((c, i) => card(x0 + i * (cw + gap), 4.15, cw, ch, c));

  slide.addText([
    { text: "S1 ", options: { bold: true, color: MULTI } },
    { text: "keeps today's count, minimises travel under a max catchment cap.  ", options: { color: INK } },
    { text: "S2 ", options: { bold: true, color: MULTI } },
    { text: "minimises the count under a min (viability) + max catchment, holding travel ≈ today.  Cost-function rung (S1-D / S2-C) = the λ-sweep that follows.", options: { color: INK } },
  ], { x: 8.77, y: 4.15, w: 4.05, h: 2.5, fontSize: 11, fontFace: "Calibri", valign: "top" });
  slide.addText([
    { text: "PRELIMINARY — INDICATIVE ONLY. ", options: { bold: true, color: "B23A2E" } },
    { text: "Full-scale ladder run incomplete; S1 (fixed-count) figures are sensitive to LP-relaxation rounding and can shift on re-run (robust multistart rounding still to be ported) — read the direction, not the exact %. LINEAR travel cost; max cap = NL observed cell-catchment max (~35k). 'stranded' = demand the cap can't serve within reach, priced at that run's c(t_max) (the λ-sweep now prices stranding at BIG).", options: { color: MUTED } },
  ], { x: 0.45, y: 6.72, w: 12.5, h: 0.55, fontSize: 8.5, italic: true, fontFace: "Calibri", valign: "top" });
}

// Proposed meeting agenda. Generated as the FIRST slide of region_summary.pptx;
// merge_deck.ps1 then moves it to position 2 (between the title and the rest of
// the concept slides). Marker text "Proposed agenda" is what the merge looks for.
// TITLE slide. Until 2026-09 the title was slide 1 of the base deck (lambda_sweep4.pptx),
// authored by hand and never updated ("what the Netherlands sweep tells us", May 2026).
// merge_deck.ps1 now deletes that base slide by its marker and moves this one to
// position 1 via the marker "how far is today's network from the frontier".
function titleSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addShape(pptx.ShapeType.rect, { x: 0.6, y: 1.55, w: 0.1, h: 3.9, fill: { color: MULTI }, line: { width: 0 } });
  slide.addText("NETWORKMODEL_EU  ·  SERVICE ACCESS  ·  PHARMACIES", { x: 1.0, y: 1.55, w: 11.5, h: 0.32, fontSize: 12, bold: true, color: MULTI, charSpacing: 2, fontFace: "Calibri" });
  slide.addText("Pharmacy locations across EU regions: how far is today's network from the frontier?",
    { x: 1.0, y: 1.95, w: 11.5, h: 1.45, fontSize: 32, bold: true, color: INK, fontFace: "Georgia", valign: "top" });
  slide.addText("A λ-sweep over a facility-location LP on the road network — what exists today, by how much it could improve at equal cost or equal accessibility, and which of 42 study areas have the most to gain",
    { x: 1.0, y: 3.5, w: 11.5, h: 0.95, fontSize: 15, color: NAVY, fontFace: "Calibri", valign: "top" });
  slide.addText([
    { text: "Lola Dekhuijzen  ·  Maarten Hilferink", options: { bold: true, color: INK, breakLine: true } },
    { text: "Object Vision", options: { color: MUTED } },
  ], { x: 1.0, y: 4.75, w: 11.5, h: 0.75, fontSize: 16, fontFace: "Calibri", valign: "top" });
  slide.addText("Draft for discussion  ·  September 2026  ·  GeoDMS road-network OD + Julia (JuMP / HiGHS)  ·  NetworkModel_EU / ServiceAccess",
    { x: 1.0, y: 6.6, w: 11.5, h: 0.4, fontSize: 10, italic: true, color: MUTED, fontFace: "Calibri" });
}

function agendaSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText("AGENDA", { x: 0.45, y: 0.34, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "Proposed agenda  ", options: { bold: true, color: INK } },
    { text: "— assessing the current pharmacy distribution", options: { color: NAVY } },
  ], { x: 0.45, y: 0.62, w: 12.5, h: 0.5, fontSize: 24, fontFace: "Georgia" });

  const items = [
    ["The current distribution", "What exists today: residents per pharmacy and per 1 km² location, per country and key NUTS1, catchments by road (p3–6).", false],
    ["Scope & method", "By how much can accessibility improve at equal cost, or cost fall at equal accessibility? A tabula-rasa LP allocation on the road OD, swept over λ, answers that as a frontier of #locations vs travel (p7–14). Cost and accessibility trade off continuously under exogenous demand — there is no trilemma to resolve.", false],
    ["Scenario results", "S1 (same #, less travel) and S2 (same travel, fewer locations) per area, quantified first in native units — locations and person-minutes, which need no λ — and only then in € (p16–61).", false],
    ["Travel-cost function", "Linear vs the logistic (midpoint 25 / scale 10), its compressed λ-range, and BN's proposal to rescale it (p64).", true],
    ["Cap / threshold ladder", "A proposed shortcut to the λ-sweep, explored on the Netherlands — catchments vary so widely that realistic min/max bounds cannot be set. Dropped; p15 kept as the record.", false],
    ["Choice set, open items & roadmap", "Where the 5-nearest choice set binds and why widening it precedes RSSV (p9); exact S1/S2 pinning; what remains, in priority order, and what was dropped (p63).", false],
  ];
  const y0 = 1.6, dy = 0.86;
  items.forEach((it, i) => {
    const y = y0 + i * dy;
    slide.addShape(pptx.ShapeType.roundRect, { x: 0.5, y, w: 0.44, h: 0.44, rectRadius: 0.22, fill: { color: NAVY }, line: { width: 0 } });
    slide.addText(String(i + 1), { x: 0.5, y, w: 0.44, h: 0.44, align: "center", valign: "middle", fontSize: 16, bold: true, color: "FFFFFF", fontFace: "Calibri" });
    slide.addText([
      { text: it[0], options: { bold: true, color: INK } },
      ...(it[2] ? [{ text: "    ▸ for discussion / decision", options: { color: MULTI, italic: true, fontSize: 11 } }] : []),
    ], { x: 1.12, y: y - 0.03, w: 11.6, h: 0.32, fontSize: 15, fontFace: "Calibri", valign: "middle" });
    slide.addText(it[1], { x: 1.12, y: y + 0.29, w: 11.7, h: 0.46, fontSize: 11.5, color: MUTED, fontFace: "Calibri", valign: "top" });
  });

  slide.addText([
    { text: "Decisions sought:  ", options: { bold: true, color: NAVY } },
    { text: "travel-cost shape (linear vs logistic, and BN's rescaling)  ·  widen the candidate radius before RSSV  ·  territorial coverage constraints for equity, or keep soft coverage.", options: { color: MUTED } },
  ], { x: 0.45, y: 6.96, w: 12.5, h: 0.4, fontSize: 10, italic: true, fontFace: "Calibri", valign: "top" });
}

// Cross-region table of the λ that hits each scenario target, interpolated from
// the sweep points. S1: λ where the open-facility count equals the baseline #cells.
// S2: λ where the multistart travel cost equals the baseline travel. Per travel-cost
// function (LINEAR / LOGISTIC). λ = w · FACILITY_MIN_COSTS (settings.jl).
// opts: {eyebrow, titleRest, col0, label(e), pick(e), labelWide}.
const COUNTRY_SET = new Set(["Austria", "Belgium", "Czechia", "Denmark", "Estonia", "France", "Ireland", "Italy", "Latvia", "Lithuania", "Luxembourg", "Netherlands", "Norway", "Poland", "Portugal", "Slovenia", "Sweden"]);
function lambdaTableSlide(opts) {
  const FMIN = 100000;  // FACILITY_MIN_COSTS (settings.jl); λ = w · FMIN — a PLACEHOLDER, see the footnote
  const byW = (rows) => [...(rows || [])].filter((r) => r.w > 0).sort((a, b) => a.w - b.w);
  // Walk adjacent w-sorted sweep rows; where `key` brackets `target`, return the value of
  // `out` there — linear in `key`, or log-interpolated w (× FMIN) when out === "w".
  // null = the target lies outside the swept range (not bracketed).
  const interp = (rows, key, target, out) => {
    const rs = byW(rows);
    if (rs.length < 2 || target == null) return null;
    for (let i = 0; i < rs.length - 1; i++) {
      const a = rs[i], b = rs[i + 1], xa = a[key], xb = b[key];
      if (xa == null || xb == null || xa === xb) continue;
      if (target >= Math.min(xa, xb) && target <= Math.max(xa, xb)) {
        const f = (target - xa) / (xb - xa);
        if (out === "w") return Math.exp(Math.log(a.w) + f * (Math.log(b.w) - Math.log(a.w))) * FMIN;
        if (a[out] == null || b[out] == null) return null;
        return a[out] + f * (b[out] - a[out]);
      }
    }
    return null;
  };
  const fL = (v) => (v == null ? "—" : Math.round(v).toLocaleString("en-US"));
  const sgn = (d) => (d < 0 ? "−" : "+");
  const dpct = (v, base) => (v == null || !base ? "—" : `${sgn(v - base)}${Math.abs((v / base - 1) * 100).toFixed(1)}%`);
  const fmtMin = (d) => (Math.abs(d) >= 1e6 ? `${(Math.abs(d) / 1e6).toFixed(1)} M` : `${(Math.abs(d) / 1e3).toFixed(0)} k`);
  // S1 = same count as today (n_open = baseline cells): how much less travel?
  // S2 = same travel as today (multi = baseline cost): how many fewer locations?
  // Read off the MULTISTART frontier (feasible solutions, so the gains are achievable),
  // in native units; these need no λ. The λ columns say at which price the sweep gets there.
  const s1Lin = (F) => { if (!F) return "—"; const t = interp(F.rows, "n_open", F.baseline.cells, "multi"); return t == null ? "—" : `${sgn(t - F.baseline.cost)}${fmtMin(t - F.baseline.cost)} min · ${dpct(t, F.baseline.cost)}`; };
  const s1Log = (F) => { if (!F) return "—"; const t = interp(F.rows, "n_open", F.baseline.cells, "multi"); const m = interp(F.rows, "n_open", F.baseline.cells, "mean_t"); return t == null ? "—" : `${dpct(t, F.baseline.cost)}` + (m == null || F.baseline.mean_t == null ? "" : ` · ${sgn(m - F.baseline.mean_t)}${Math.abs(m - F.baseline.mean_t).toFixed(1)} min`); };
  const s2 = (F) => { if (!F) return "—"; const n = interp(F.rows, "multi", F.baseline.cost, "n_open"); return n == null ? "—" : `${sgn(n - F.baseline.cells)}${fL(Math.abs(n - F.baseline.cells))} · ${dpct(n, F.baseline.cells)}`; };
  const rowsC = data.filter((e) => opts.pick(e) && e.func.LINEAR && e.func.LINEAR.baseline);

  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText(opts.eyebrow, { x: 0.45, y: 0.28, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "By how much: S1 and S2  ", options: { bold: true, color: INK } },
    { text: opts.titleRest, options: { color: NAVY } },
  ], { x: 0.45, y: 0.54, w: 12.5, h: 0.5, fontSize: 22, fontFace: "Georgia" });
  slide.addText("Gains in native units first — person-minutes and locations, read off the frontier and independent of any λ — then the λ at which the sweep reaches each point.",
    { x: 0.45, y: 1.0, w: 12.5, h: 0.3, fontSize: 10, color: MUTED, fontFace: "Calibri" });

  const n = rowsC.length;
  const fs = n > 24 ? 7.6 : n > 14 ? 8.6 : 10;                 // the NUTS-1 table holds 28 rows
  const rh = Math.max(0.17, Math.min(0.34, 5.0 / (n + 1)));
  const c0 = opts.labelWide ? 2.9 : 2.2;
  const dW = 1.32, lamW = (11.9 - c0 - 0.8 - 4 * dW) / 4;
  const colW = [c0, 0.8, dW, dW, dW, dW, lamW, lamW, lamW, lamW];

  const head = [opts.col0, "today #", "S1 · Δ travel (lin)", "S2 · Δ # (lin)", "S1 · Δ cost · Δ mean t (log)", "S2 · Δ # (log)", "λ S1 lin", "λ S2 lin", "λ S1 log", "λ S2 log"];
  const body = [head.map((h, ci) => ({ text: h, options: { bold: true, color: "FFFFFF", fill: ci >= 6 ? "5B6B7B" : NAVY, fontSize: Math.min(fs, 9.5), align: ci === 0 ? "left" : "center", fontFace: "Calibri", margin: [2, 2, 2, 4] } }))];
  rowsC.forEach((e, i) => {
    const L = e.func.LINEAR, G = e.func.LOGISTIC;
    const cells = L.baseline.cells;
    const c = [opts.label(e), cells != null ? cells.toLocaleString("en-US") : "—",
      s1Lin(L), s2(L), s1Log(G), s2(G),
      fL(interp(L.rows, "sum_y", cells, "w")), fL(interp(L.rows, "multi", L.baseline.cost, "w")),
      fL(G ? interp(G.rows, "sum_y", G.baseline.cells, "w") : null), fL(G ? interp(G.rows, "multi", G.baseline.cost, "w") : null)];
    const fill = i % 2 ? PANEL : "FFFFFF";
    body.push(c.map((v, ci) => ({ text: v, options: { fontSize: ci >= 6 ? fs - 0.6 : fs, align: ci === 0 ? "left" : "center", color: ci >= 6 ? MUTED : INK, fill, fontFace: "Calibri", valign: "middle", margin: n > 24 ? [1, 2, 1, 3] : [2, 2, 2, 4] } })));
  });
  slide.addTable(body, { x: 0.7, y: 1.4, w: 11.9, colW, rowH: rh, border: { type: "solid", color: "D9E0E7", pt: 0.5 }, valign: "middle" });

  slide.addText([
    { text: "S1 = today's number of locations, travel minimised; S2 = today's travel, fewer locations. ", options: { bold: true, color: NAVY } },
    { text: "Δ columns are read off the multistart frontier by interpolation between adjacent sweep points — person-minutes (linear), dimensionless logistic cost with the mean minutes beside it, and locations — and need no λ. ", options: { color: MUTED } },
    { text: "λ = w · €100,000 is the price per location at which the sweep reaches that point; the €100,000 is a placeholder, not an estimate — the frontier, the Δs and the ranking of areas do not depend on it, only these € figures do. ", options: { color: MUTED } },
    { text: "“—” = the target lies outside the swept λ range.", options: { color: MUTED } },
  ], { x: 0.7, y: 6.72, w: 11.9, h: 0.66, fontSize: 8.6, italic: true, fontFace: "Calibri", valign: "top" });
}

// The optimization problem, as actually implemented in lp_run.jl
// (build_lp_warmstart / solve_at_w!): uncapacitated facility location, solved as
// an LP relaxation per λ, warm-started along the w-grid. merge_deck.ps1 moves this
// to position 3 via the marker "The optimization problem".
function optProblemSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText("MODEL", { x: 0.45, y: 0.3, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "The optimization problem  ", options: { bold: true, color: INK } },
    { text: "— uncapacitated facility location on the road OD", options: { color: NAVY } },
  ], { x: 0.45, y: 0.56, w: 12.5, h: 0.5, fontSize: 22, fontFace: "Georgia" });

  // formulation panel (dark)
  slide.addShape(pptx.ShapeType.roundRect, { x: 0.5, y: 1.35, w: 6.6, h: 3.4, rectRadius: 0.06, fill: { color: INK }, line: { width: 0 } });
  const M = (t, o = {}) => ({ text: t, options: { fontFace: "Cambria Math", color: "FFFFFF", ...o } });
  // SOFT coverage (2026-07-10): a client need NOT be assigned; the unserved share is
  // priced at BIG. Factoring popᵢ keeps the objective on one line.
  slide.addText([
    M("min", { bold: true, color: "8FD4F0" }), M("x,y", { fontSize: 10, subscript: true, color: "8FD4F0" }),
    M("   Σᵢ popᵢ · [ Σⱼ c(tᵢⱼ)·xᵢⱼ  +  BIG·(1 − Σⱼ xᵢⱼ) ]   +   λ · Σⱼ yⱼ", {}),
  ], { x: 0.8, y: 1.5, w: 6.1, h: 0.4, fontSize: 14 });
  slide.addText("travel of the served share   +   the unserved share, priced at BIG   +   facility cost",
    { x: 0.8, y: 1.9, w: 6.1, h: 0.25, fontSize: 9, italic: true, fontFace: "Calibri", color: "9FB0C2" });
  slide.addText([
    [M("s.t.", { bold: true, color: "8FD4F0" }), M("  Σⱼ xᵢⱼ  ≤  1"), M("          a client MAY be left unserved", { fontFace: "Calibri", fontSize: 10.5, color: "FFD9A0" })],
    [M("      xᵢⱼ  ≤  yⱼ"), M("            only to open pharmacies", { fontFace: "Calibri", fontSize: 10.5, color: "9FB0C2" })],
    [M("      yⱼ ∈ {0,1}"), M("  →  relaxed to  0 ≤ yⱼ ≤ 1,   xᵢⱼ ≥ 0", { color: "FFD9A0" })],
  ].map((line) => line.map((seg, si) => ({ ...seg, options: { ...seg.options, breakLine: si === line.length - 1 } }))).flat(),
    { x: 0.8, y: 2.25, w: 6.1, h: 1.4, fontSize: 15, lineSpacingMultiple: 1.35 });
  slide.addText([
    M("i", { italic: true }), M(" = populated 1 km² cells (clients) · ", { fontFace: "Calibri", fontSize: 10.5, color: "C7D2DD" }),
    M("j", { italic: true }), M(" = candidate pharmacy cells · ", { fontFace: "Calibri", fontSize: 10.5, color: "C7D2DD" }),
    M("(i,j)", { italic: true }), M(" only where the road network gives tᵢⱼ ≤ t_max — the exported OD.  ", { fontFace: "Calibri", fontSize: 10.5, color: "C7D2DD" }),
    M("BIG", { italic: true, color: "FFD9A0" }), M(" = price of leaving a client unserved: 120 min (linear) / 1.0 (logistic saturation). Opening a facility only pays off where it saves more travel than λ.", { fontFace: "Calibri", fontSize: 10.5, color: "C7D2DD" }),
  ], { x: 0.8, y: 3.68, w: 6.05, h: 0.95, fontSize: 11, valign: "top" });

  // right column: ingredients
  const ing = (y, head, body, fs = 10.5) => {
    slide.addText(head, { x: 7.45, y, w: 5.4, h: 0.28, fontSize: 12.5, bold: true, color: NAVY, fontFace: "Calibri" });
    slide.addText(body, { x: 7.45, y: y + 0.27, w: 5.4, h: 0.62, fontSize: fs, color: MUTED, fontFace: "Calibri", valign: "top" });
  };
  ing(1.4, "c(t) — travel cost, t in minutes", "LINEAR c(t)=t; LOGISTIC (adapted logit) c(t)=1/(1+e^−(t−25)/10). The swept LPs run once per function.");
  ing(2.32, "λ = w · €100,000 — the price of a location (placeholder)", "Linear cost a + b·q reduces to λ·#open: b·q is ~constant while (nearly) all demand is served, so only the fixed cost a matters (approximately, under soft coverage). €100,000 is a placeholder, not an estimate: the frontier, S1/S2 and the rankings are invariant to it — only the € labels move with the true a.", 9.6);
  ing(3.36, "One LP per λ, exact", "JuMP + HiGHS dual simplex; the model is built once and re-solved along the w-grid from the previous optimal basis (lp_run.jl solve_at_w!) — millions of xᵢⱼ, minutes per point.");
  // review flags — modelling details the group should challenge
  slide.addShape(pptx.ShapeType.roundRect, { x: 7.45, y: 4.22, w: 5.4, h: 0.78, rectRadius: 0.05, fill: { color: "FBF5EA" }, line: { color: "B9791C", width: 1 } });
  slide.addText([
    { text: "⚠ For review:  ", options: { bold: true, color: "B9791C" } },
    { text: "each client's OD holds every candidate out to its 5 nearest EXISTING pharmacies (max_nr_facilities_per_client) — it shrinks the LP but limits reassignment choice, and it can bind at S2-level facility counts. Clients still unreachable within t_max are priced at BIG on BOTH sides — stranded in the baseline, optionally stranded in the LP — so ★ and frontier stay directly comparable. After the scope rules on p8 that is only 0.012% of residents: 34 of 41 areas have none at all, the largest remainder is SE2 with 165 cells / 14,210 residents (0.32%), and these are genuinely remote cells rather than a coverage artefact. Feedback welcome.", options: { color: INK } },
  ], { x: 7.58, y: 4.28, w: 5.16, h: 0.68, fontSize: 8.3, fontFace: "Calibri", valign: "top", lineSpacingMultiple: 0.98 });

  // bottom: bounds story
  slide.addShape(pptx.ShapeType.roundRect, { x: 0.5, y: 5.05, w: 12.33, h: 1.85, rectRadius: 0.06, fill: { color: PANEL }, line: { color: "D9E0E7", width: 1 } });
  slide.addText([
    { text: "Why the relaxation, and what it buys.  ", options: { bold: true, color: INK } },
    { text: "With yⱼ ∈ {0,1} this is the (NP-hard) uncapacitated facility-location problem, in its strong disaggregated formulation — one xᵢⱼ ≤ yⱼ per OD pair — whose LP relaxation is known to be nearly integral, which the sweeps confirm (frac_y stays small). The LP optimum is a certified ", options: { color: MUTED } },
    { text: "lower bound", options: { bold: true, color: BASE } },
    { text: " (the grey dashed line); rounding x* to a real set of pharmacies (multistart, p. 12) gives a feasible ", options: { color: MUTED } },
    { text: "upper bound", options: { bold: true, color: MULTI } },
    { text: " — the integer optimum is pinched between the two (+0–18% LINEAR, +0–4.7% LOGISTIC).", options: { color: MUTED, breakLine: true } },
    { text: "Relation to the p-median problem.  ", options: { bold: true, color: INK } },
    { text: "Imposing the count (Σⱼ yⱼ = p) instead of pricing it gives the p-median problem with costs c(tᵢⱼ) (ReVelle & Swain 1970) — S1 at the baseline count is a p-median instance, in its soft-coverage form: a client may go unserved at BIG rather than be forced onto a far facility (an outside option / p-median with an upper bound on assignment cost). The λ-sweep is its Lagrangian relaxation w.r.t. that constraint (Cornuéjols, Fisher & Nemhauser 1977): it recovers only the p’s on the lower convex envelope of the p-median value function, so p-values in non-convex gaps are unreachable by any λ — there S1/S2 are interpolated between sweep points, or pinned exactly with the cardinality constraint (roadmap: better S1/S2 estimations). The swap polish of p. 12 is the classic p-median vertex-substitution search.", options: { color: MUTED } },
  ], { x: 0.75, y: 5.2, w: 11.85, h: 1.62, fontSize: 10, fontFace: "Calibri", valign: "top" });

  slide.addText("Implementation: lp_run.jl (build_lp_warmstart / solve_at_w!) · weights popᵢ = total residents of cell i (CLIENT_WEIGHT=total_pop) · OD from GeoDMS impedance_matrix_od64, t = seconds/60.",
    { x: 0.5, y: 7.05, w: 12.33, h: 0.3, fontSize: 8.5, italic: true, color: MUTED, fontFace: "Calibri" });
}

// How the fractional LP solution is rounded to real pharmacies — the multistart
// CHOICE-SET slide: how each client's candidate set is bounded, measured evidence that
// the bound binds at S2, and why widening it is a precondition for the RSSV route.
// merge_deck.ps1 moves this to position 5 via the marker "The choice set".
function choiceSetSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText("CHOICE SET", { x: 0.45, y: 0.3, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "The choice set  ", options: { bold: true, color: INK } },
    { text: "— where the 5-nearest rule binds, and why widening it comes before RSSV", options: { color: NAVY } },
  ], { x: 0.45, y: 0.56, w: 12.5, h: 0.5, fontSize: 22, fontFace: "Georgia" });
  slide.addText("Each client is connected to every candidate cell within the road distance to its 5th-nearest EXISTING pharmacy (or 120 min). That radius holds ~70–90 candidates on average — so it is not “5 choices”, it is a radius fixed by today’s five. When the optimiser removes facilities, the radius does not grow.",
    { x: 0.45, y: 1.0, w: 12.5, h: 0.45, fontSize: 10, color: MUTED, fontFace: "Calibri", valign: "top" });

  const box = (x, w, tint, fill, head, items, foot) => {
    slide.addShape(pptx.ShapeType.roundRect, { x, y: 1.58, w, h: 4.3, rectRadius: 0.05, fill: { color: fill }, line: { color: tint, width: 1 } });
    slide.addText(head, { x: x + 0.2, y: 1.66, w: w - 0.4, h: 0.3, fontSize: 13, bold: true, color: tint, fontFace: "Calibri" });
    slide.addText(items.map((t) => ({ text: t, options: { bullet: { indent: 12 }, breakLine: true } })),
      { x: x + 0.22, y: 2.02, w: w - 0.44, h: 3.15, fontSize: 9.4, color: INK, fontFace: "Calibri", lineSpacingMultiple: 1.0, paraSpaceAfter: 5, valign: "top" });
    if (foot) slide.addText(foot, { x: x + 0.22, y: 5.22, w: w - 0.44, h: 0.6, fontSize: 9.2, bold: true, color: tint, fontFace: "Calibri", valign: "top" });
  };

  box(0.4, 4.1, "B9791C", "FBF5EA", "Where it binds — measured at S2", [
    "SE2 at S2 (309 of 452 open): 1,730 cells / 449,261 residents — 10.2% of the population — have exactly ONE open facility left inside their radius. Closing it would strand them at BIG, so the optimiser must keep it open even where a 6th-nearest pharmacy would serve them.",
    "ITF at S2 (519 of 1,253 open): 9.0% of residents are already stranded and a further 23.9% are one closure away — a third of the population pins the solution.",
    "Even at S1 — same count as today, only relocated — ITF strands 1.84%: relocation moved facilities out of clients’ fixed radii.",
  ], "The frontier is under-estimated wherever the radius, not the geography, decides who can be served.");

  box(4.72, 4.1, "1E7A52", "F0F6F2", "Why widening helps", [
    "More existing and potential locations per client → a wider radius → the optimiser can consolidate further without stranding anyone → S2 reaches the baseline travel cost with fewer facilities.",
    "The gain is concentrated exactly where the lists rank improvement potential: the areas with the most one-option clients.",
    "Keep the EXISTING-side radius at 5 for the baseline, so ★ stays comparable with earlier decks; widen the CANDIDATE side only.",
    "Cost: a wider radius enlarges the full OD (build time, memory) and the exact solve on small areas.",
  ], "A cheap experiment: one area, radius 5 → 10, compare S2 facility count and stranding.");

  box(9.04, 4.1, "0B6E99", "EEF5FA", "Why RSSV requires it", [
    "RSSV solves many sub-problems on random CANDIDATE subsets Jᵤ with the FULL client set. Every client must still reach some sampled candidate — otherwise it is stranded at BIG for that sub-problem alone, and those spurious penalties corrupt the spatial votes.",
    "The chance that a random Jᵤ leaves a client with no reachable candidate falls as the radius widens. A thin radius makes voting noisy; a wide one makes it robust.",
    "So the two size-control knobs trade against each other: under RSSV, size control moves from pruning per client to sample → vote → filter → exact solve. Widening the radius is the precondition, not a nicety.",
    "Stratified (not uniform) sampling lets a narrower radius suffice — a lever to trade against OD size.",
  ], "Sequence: widen the candidate radius → RSSV → exact MIP on the reduced set.");

  slide.addShape(pptx.ShapeType.roundRect, { x: 0.4, y: 6.05, w: 12.75, h: 0.62, rectRadius: 0.05, fill: { color: "F2F5F8" }, line: { color: "5B6B7B", width: 1 } });
  slide.addText([
    { text: "Also found: ", options: { bold: true, color: "B9791C" } },
    { text: "S1 and S2 are read off the nearest swept λ grid point. In 5 of 42 areas (FRC, FRH, FRJ, FRK, SE2) both scenarios snap to the SAME point — SE2’s S1 bracket (0.2, 0.5) and S2 bracket (0.5, 1.0) both resolve to w = 0.5, so its delivered S1 has 309 open, not the baseline 452. The interpolated tables on p60–61 are unaffected; the exported S1/S2 location files and the exact-MIP step are where this needs a refinement step rather than a snap.", options: { color: INK } },
  ], { x: 0.6, y: 6.12, w: 12.4, h: 0.52, fontSize: 8.8, fontFace: "Calibri", valign: "top" });
}

// SCOPE slide: the two decisions that determine WHICH demand and WHICH network the
// model sees. Both changed after the previous deck, so its figures are not comparable.
// merge_deck.ps1 moves this to position 4 via the marker "What the model covers".
function scopeSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText("SCOPE", { x: 0.45, y: 0.3, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "What the model covers  ", options: { bold: true, color: INK } },
    { text: "— and what it deliberately excludes", options: { color: NAVY } },
  ], { x: 0.45, y: 0.56, w: 12.5, h: 0.5, fontSize: 22, fontFace: "Georgia" });
  slide.addText("Under soft coverage every resident the model cannot route to a pharmacy is priced at BIG (120 min). That is right for someone who is genuinely remote — and wrong when the network or the supply data is simply missing, because it turns a DATA gap into apparent policy headroom. Two rules separate the cases.",
    { x: 0.45, y: 1.0, w: 12.5, h: 0.42, fontSize: 10, color: MUTED, fontFace: "Calibri", valign: "top" });

  const panel = (x, tint, fill, head, sub, rows, foot) => {
    slide.addShape(pptx.ShapeType.roundRect, { x, y: 1.55, w: 6.25, h: 4.35, rectRadius: 0.05, fill: { color: fill }, line: { color: tint, width: 1 } });
    slide.addText(head, { x: x + 0.22, y: 1.64, w: 5.85, h: 0.3, fontSize: 13.5, bold: true, color: tint, fontFace: "Calibri" });
    slide.addText(sub, { x: x + 0.22, y: 1.95, w: 5.85, h: 0.62, fontSize: 10, color: INK, fontFace: "Calibri", valign: "top" });
    slide.addText(rows.map((t) => ({ text: t, options: { bullet: { indent: 12 }, breakLine: true } })),
      { x: x + 0.24, y: 2.6, w: 5.8, h: 2.5, fontSize: 9.5, color: INK, fontFace: "Calibri", lineSpacingMultiple: 1.0, paraSpaceAfter: 5, valign: "top" });
    slide.addText(foot, { x: x + 0.24, y: 5.28, w: 5.8, h: 0.55, fontSize: 9.5, bold: true, color: tint, fontFace: "Calibri", valign: "top" });
  };

  panel(0.4, "1E7A52", "F0F6F2",
    "1 · Road network — per landbody",
    "The largest strongly-connected network is kept for EVERY separate landbody, not just the single largest one in the study area.",
    ["Before, one component survived per study area, so island networks — and the ferry links inside them — were discarded entirely.",
     "Sicilia and Sardegna are two separate landbodies, so at most one of them could ever be kept.",
     "No source data changed: the links were always in the TomTom extract, they were being pruned."],
    "ITG: mean travel 22.3 → 4.9 min · unreachable residents 983,169 → 591");

  panel(6.9, "B9791C", "FBF5EA",
    "2 · Regions the model cannot serve at all",
    "If more than 50% of a NUTS region's inhabitant locations are absent from the OD matrix, the WHOLE region is excluded — its population AND its candidate locations.",
    ["Level: NUTS3 where populated, otherwise NUTS2, otherwise NUTS1.",
     "Judged on the EXISTING network, so the baseline and the λ-sweep always agree on who is in scope.",
     "Excluded today: PT200 Azores (919 cells, 212,855 residents) and PT300 Madeira (419 cells, 244,867 residents) — both 100% absent. They hold population but no pharmacy anywhere in the source data, so no network fix could reach them.",
     "No other area comes near the threshold: it is 100% or far below."],
    "Portugal: baseline travel −62% · mean 8.64 → 3.47 min · figures now cover the MAINLAND ONLY");

  slide.addShape(pptx.ShapeType.roundRect, { x: 0.4, y: 6.05, w: 12.75, h: 0.62, rectRadius: 0.05, fill: { color: "F2F5F8" }, line: { color: "5B6B7B", width: 1 } });
  slide.addText([
    { text: "⚠ Not comparable with the previous deck.  ", options: { bold: true, color: "B9791C" } },
    { text: "Both rules change which residents are counted, so baselines, frontiers and the ranked improvement lists all shift. Absence of a pharmacy record is not evidence of absence of a pharmacy — excluding those regions states what we do not know, rather than asserting the strong version of it.", options: { color: INK } },
  ], { x: 0.6, y: 6.13, w: 12.4, h: 0.5, fontSize: 9.3, fontFace: "Calibri", valign: "top" });
}

// method in lp_run.jl (multistart_round / swap_round! / travel_of), and why the
// result is an upper bound. merge_deck.ps1 moves this to position 6 via the
// marker "How multistart rounds".
// TANGENT slide (REGIO review, Brons/BN comments 41-42): before any frontier is shown,
// show how ONE lambda picks ONE point -- the objective is a straight line of slope -lambda
// in the (#open, travel) plane and its optimum is a tangency with the feasible set. Two
// lambdas give two tangencies; the sweep over the 1-2-5 grid traces the envelope. The
// PNG is drawn from the Netherlands LINEAR rows by tangent_chart.py.
// merge_deck.ps1 moves this to position 10 via the marker "How one .* picks one point".
function tangentSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText("METHOD", { x: 0.45, y: 0.3, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "How one λ picks one point  ", options: { bold: true, color: INK } },
    { text: "— and how a sweep over λ traces the frontier", options: { color: NAVY } },
  ], { x: 0.45, y: 0.56, w: 12.5, h: 0.5, fontSize: 22, fontFace: "Georgia" });
  slide.addText("The sweep never fixes a value of λ. Each λ is one slope; the solver returns the point of the feasible set where a line of that slope touches. Netherlands, LINEAR c(t) = t, multistart-rounded solutions; the ★ is today’s network.",
    { x: 0.45, y: 1.0, w: 12.5, h: 0.42, fontSize: 10, color: MUTED, fontFace: "Calibri", valign: "top" });

  const p = join(__dir, "charts", "lambda_tangent.png");
  if (existsSync(p)) slide.addImage({ path: p, x: 0.35, y: 1.5, w: 8.1, h: 4.93 });

  const step = (y, h, tint, fill, head, body) => {
    slide.addShape(pptx.ShapeType.roundRect, { x: 8.65, y, w: 4.45, h, rectRadius: 0.05, fill: { color: fill }, line: { color: tint, width: 1 } });
    slide.addText(head, { x: 8.83, y: y + 0.07, w: 4.1, h: 0.28, fontSize: 12, bold: true, color: tint, fontFace: "Calibri" });
    slide.addText(body, { x: 8.83, y: y + 0.36, w: 4.12, h: h - 0.42, fontSize: 9.3, color: INK, fontFace: "Calibri", valign: "top" });
  };
  step(1.5, 1.2, "5B6B7B", "F2F5F8", "1 · The objective is a line",
    "We minimise  travel + λ · #open.  Every solution with the same objective value C lies on the line  travel = C − λ · #open:  slope −λ, and the lower the line, the cheaper the solution.");
  step(2.8, 1.45, "0B6E99", "EEF5FA", "2 · The optimum is a tangency",
    "Slide the line down until it last touches the feasible set. That touching point is the λ-optimum. λ₁ = €10,000 per facility touches at 3,220 open (22.6 M person-minutes); λ₂ = €50,000 touches at 831 open (74.7 M). A steeper slope buys fewer, busier pharmacies.");
  step(4.35, 1.2, "1E7A52", "F0F6F2", "3 · Many λ → the frontier",
    "Two λ give two tangencies; the 1-2-5 grid gives ~30. Their lower-left envelope is the Pareto frontier of the next slides. The frontier itself needs no λ — λ only says which point on it a decision-maker would pick.");
  step(5.65, 0.95, "B9791C", "FBF5EA", "What a tangency cannot reach",
    "A point in a concave dent of the frontier is never a tangency, whatever λ. Such points — and an exact count such as “today’s 1,615” — need a fixed-#open solve, which is the refinement step S1/S2 still lack (p9).");
}

function multistartSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText("FROM FRACTIONS TO PHARMACIES", { x: 0.45, y: 0.3, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "How multistart rounds the LP relaxation  ", options: { bold: true, color: INK } },
    { text: "— and why it is an upper bound", options: { color: NAVY } },
  ], { x: 0.45, y: 0.56, w: 12.5, h: 0.5, fontSize: 22, fontFace: "Georgia" });

  const steps = [
    ["Fix the count", "p = round(Σ yⱼ*) — the integer pharmacy count nearest the LP's fractional total, so every rounded point stays on the same axis as the relaxation."],
    ["Seed 10 candidate sets", "top-p by x* and the lazy-greedy set (CELF, Leskovec et al. 2007 — marginal travel gains are submodular), so the result can never be worse than either; plus 8 x*-weighted random draws (Efraimidis–Spirakis 2006 A-Res); must-open pharmacies (x*≈1) are always kept."],
    ["Polish by swaps", "best-improving open↔closed swaps over the fractional pool — the classic p-median vertex-substitution search, in its fast-interchange form (Resende & Werneck 2007). Each swap is accepted only if the exact travel delta improves — cost strictly decreases, ≤ 12 rounds per seed."],
    ["Score coverage-honestly, keep the best", "every client priced at its nearest open pharmacy, c(t); a client left with no open pharmacy in the OD (stranded) is priced at BIG — 120 min (linear) / 1.0 (logistic), the same price as in the LP and the baseline, so abandoning remote clusters is never free. Lowest total wins."],
  ];
  const y0 = 1.42, dy = 0.98;
  steps.forEach((s, i) => {
    const y = y0 + i * dy;
    slide.addShape(pptx.ShapeType.roundRect, { x: 0.5, y, w: 0.44, h: 0.44, rectRadius: 0.22, fill: { color: NAVY }, line: { width: 0 } });
    slide.addText(String(i + 1), { x: 0.5, y, w: 0.44, h: 0.44, align: "center", valign: "middle", fontSize: 16, bold: true, color: "FFFFFF", fontFace: "Calibri" });
    slide.addText(s[0], { x: 1.12, y: y - 0.02, w: 6.4, h: 0.3, fontSize: 14, bold: true, color: INK, fontFace: "Calibri" });
    slide.addText(s[1], { x: 1.12, y: y + 0.27, w: 6.55, h: 0.68, fontSize: 10.5, color: MUTED, fontFace: "Calibri", valign: "top" });
  });

  // right panel: the upper-bound argument (verified against lp_run.jl)
  slide.addShape(pptx.ShapeType.roundRect, { x: 8.0, y: 1.42, w: 4.83, h: 3.9, rectRadius: 0.06, fill: { color: "F0F6F2" }, line: { color: "1E7A52", width: 1 } });
  slide.addText("Why this is an upper bound ✓", { x: 8.2, y: 1.54, w: 4.45, h: 0.3, fontSize: 13, bold: true, color: "1E7A52", fontFace: "Calibri" });
  slide.addText([
    { text: "The rounded set is a feasible point of the same (soft-coverage) problem: exactly p pharmacies actually open (x integer), and every client is either assigned to its nearest open pharmacy or explicitly left unserved at BIG. Feasible ⟹ its objective can only be ≥ the integer optimum, which is ≥ the LP optimum:", options: { color: INK, breakLine: true } },
    { text: "", options: { breakLine: true, fontSize: 4 } },
    { text: "LP relax  ≤  integer optimum  ≤  multistart", options: { bold: true, color: "1E7A52", align: "center", breakLine: true } },
    { text: "", options: { breakLine: true, fontSize: 4 } },
    { text: "Rigorous throughout — no caveat needed. Under soft coverage leaving a client unserved is part of the feasible space, and it is priced at the same BIG in the LP bound, in the rounding and in the baseline. The unserved count is reported next to every figure.", options: { color: MUTED, breakLine: true } },
    { text: "", options: { breakLine: true, fontSize: 4 } },
    { text: "The multi-vs-relax column in the end tables is therefore a certified optimality gap on TOTAL cost: the integer optimum lies inside it. ", options: { color: INK, italic: true } },
    { text: "It does NOT bound travel and facility cost separately — the discrete solution may sit with higher travel and lower facility cost than the relaxation, or the reverse. For the logistic variant the bound is on the transformed cost c(t), not on minutes; mean_t is reported alongside and carries no bound. In practice the two bounds are now nearly a line for most areas.", options: { color: MUTED, italic: true, breakLine: true } },
  ], { x: 8.2, y: 1.88, w: 4.45, h: 3.38, fontSize: 9.6, fontFace: "Calibri", valign: "top", lineSpacingMultiple: 1.0 });

  slide.addShape(pptx.ShapeType.roundRect, { x: 0.5, y: 5.5, w: 12.33, h: 1.25, rectRadius: 0.06, fill: { color: PANEL }, line: { color: "D9E0E7", width: 1 } });
  slide.addText([
    { text: "Checked against the implementation (lp_run.jl).  ", options: { bold: true, color: INK } },
    { text: "An LP-guided matheuristic. The swap profit is the exact per-swap travel change (gain − loss + interaction term — verified case-by-case), so polish is monotone and multistart ≤ min(top-p, greedy) by construction; the final choice re-evaluates every polished set from scratch (travel_of). Deterministic: fixed RNG seed, so decks reproduce. Cost: seconds per point — the LP solve dominates.", options: { color: MUTED } },
  ], { x: 0.75, y: 5.65, w: 11.85, h: 1.0, fontSize: 11, fontFace: "Calibri", valign: "top" });

  slide.addText("lp_run.jl: multistart_round (seeds), swap_round! (fast interchange), travel_of (coverage-honest metric), assign_nearest (final assignment) · MS_RESTARTS=10, MS_ROUNDS=12, MS_SEED fixed.",
    { x: 0.5, y: 6.95, w: 12.33, h: 0.3, fontSize: 8.5, italic: true, color: MUTED, fontFace: "Calibri" });
}

let regions = data;
if (only) regions = data.filter((e) => e.region === only);
if (!only && !args.includes("--no-summary")) {
  titleSlide();
  agendaSlide();
  optProblemSlide();
  scopeSlide();
  choiceSetSlide();
  tangentSlide();
  multistartSlide();
  descriptivesSlide("pharmacy_descriptives.csv",       "pharm", "BASELINE · RESIDENTS PER PHARMACY",       "— per country");
  descriptivesSlide("pharmacy_descriptives_nuts1.csv", "pharm", "BASELINE · RESIDENTS PER PHARMACY",       "— key NUTS1 regions (FR / IT / SE)");
  descriptivesSlide("pharmacy_descriptives.csv",       "loc",   "BASELINE · RESIDENTS PER 1 KM² LOCATION", "— per country");
  descriptivesSlide("pharmacy_descriptives_nuts1.csv", "loc",   "BASELINE · RESIDENTS PER 1 KM² LOCATION", "— key NUTS1 regions (FR / IT / SE)");
  capSlide("cap_results_Netherlands.csv");
}
regions.forEach(regionSlide);
if (!only && !args.includes("--no-summary")) {
  aggregateSlide();
  lambdaTableSlide({ eyebrow: "SCENARIOS · PER COUNTRY", titleRest: "— per country, by travel-cost function", col0: "country", pick: (e) => COUNTRY_SET.has(e.region), label: (e) => e.name });
  lambdaTableSlide({ eyebrow: "SCENARIOS · NUTS-1", titleRest: "— FR / IT / SE / PL NUTS-1 regions", col0: "NUTS-1 region", labelWide: true, pick: (e) => !COUNTRY_SET.has(e.region), label: (e) => `${e.region} · ${e.name}` });
  summarySlide(); statusSlide(); logisticSlide();
}

await pptx.writeFile({ fileName: join(__dir, outName) });
console.log(`wrote ${join(__dir, outName)} : ${regions.length} region slide(s)${(!only && !args.includes("--no-summary")) ? " + summary" : ""}`);
