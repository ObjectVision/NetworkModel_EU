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
    { text: `c(t_max) travel  LIN ${fmtCost(bl.cost)} · LOG ${fmtCost(bg.cost)}`, options: { color: MUTED } },
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
  slide.addText("Charts: travel_relax & travel_multi (left), log₁₀(w) (right) vs sum_x; ★ baseline, ◆ S1, ■ S2.  multistart ≤ LP-relax bound; stranded clients priced at c(t_max) — in the baseline too (coverage-consistent).",
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

  const cy = 1.6, cw = 5.85, chh = 3.44;
  for (const [fn, x] of [["LINEAR", 0.32], ["LOGISTIC", 6.42]]) {
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
      fontSize: ri === 0 ? 9 : 9.5, bold: ri === 0, align: ci <= 1 ? "left" : "center",
      color: ri === 0 ? "FFFFFF" : INK, fill: ri === 0 ? NAVY : (ri % 2 ? PANEL : "FFFFFF"),
      fontFace: "Calibri", valign: "middle",
    },
  })));
  slide.addTable(tRows, {
    x: 0.5, y: 5.32, w: 12.33, colW: [1.2, 2.5, 1.3, 1.5, 1.6, 2.1, 2.13],
    rowH: 0.28, border: { type: "solid", color: "D9E0E7", pt: 0.5 }, valign: "middle",
  });
  const unbr = [ !L.S1 && "S1", !L.S2 && "S2" ].filter(Boolean).join("/");
  slide.addText(`Exact-by-separability aggregation over ${L.n_regions} disjoint areas (13 countries + FR/IT/SE/PL NUTS-1; country-level Poland excluded in favour of its 7 NUTS-1): at a common λ the sum of the regional optima IS the combined optimum. Summed at the union of swept w-values inside the range every area covers (${L.n_w} points; an area without that exact λ is log-interpolated between its adjacent sweep points — the λ-table rule).` +
    (unbr ? ` ${unbr} not bracketed: the aggregate baseline (★) lies outside the common λ range — the full-coverage floor exceeds today's count (roadmap: extend the w-grid / exact S1-S2).` : ""),
    { x: 0.5, y: 6.98, w: 12.33, h: 0.46, fontSize: 8.5, italic: true, color: MUTED, fontFace: "Calibri" });
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
  slide.addText("cell = multistart travel above the LP-relax bound  (multistart clients stranded by rounding, priced at c(t_max)).  Sparse Swedish regions keep the largest bound-gaps.",
    { x: 0.5, y: 7.12, w: 12.33, h: 0.3, fontSize: 8.5, italic: true, color: "9FB0C2", fontFace: "Calibri" });
}

function statusSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText("ROADMAP", { x: 0.45, y: 0.28, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "Status against Lewis's & Bernhard's framing  ", options: { bold: true, color: INK } },
    { text: "— implemented · in progress · remaining", options: { color: NAVY } },
  ], { x: 0.45, y: 0.54, w: 12.5, h: 0.42, fontSize: 21, fontFace: "Georgia" });
  slide.addText([
    { text: "The λ-sweep is the working general method. ", options: { bold: true, color: INK } },
    { text: "A proposed A→D ladder would cap catchments + set a min threshold to sidestep it — but the descriptives show catchments vary so widely (p10–p90 several-fold; many pharmacies at zero) that realistic bounds are hard to set, and the ladder may not actually simplify the problem.", options: { color: MUTED } },
  ], { x: 0.45, y: 0.97, w: 12.5, h: 0.4, fontSize: 9.5, fontFace: "Calibri", valign: "top" });

  const GREEN = "1E7A52", AMBER = "B9791C", SLATE = "5B6B7B";
  const col = (x, tint, fill, title, items) => {
    slide.addShape(pptx.ShapeType.roundRect, { x, y: 1.42, w: 4.07, h: 4.95, rectRadius: 0.05, fill: { color: fill }, line: { color: tint, width: 1 } });
    slide.addText(title, { x: x + 0.18, y: 1.5, w: 3.7, h: 0.3, fontSize: 13, bold: true, color: tint, fontFace: "Calibri" });
    slide.addText(items.map((t) => ({ text: t, options: { bullet: { indent: 12 }, breakLine: true } })),
      { x: x + 0.2, y: 1.86, w: 3.72, h: 4.45, fontSize: 9, color: INK, fontFace: "Calibri", lineSpacingMultiple: 0.98, paraSpaceAfter: 4, valign: "top" });
  };

  col(0.4, GREEN, "F0F6F2", "Implemented ✓", [
    "Tabula-rasa LP allocation + λ-sweep → Pareto curve of #facilities vs travel cost (Option D)",
    "Lewis's 3 cases live: S1 (same #, ↓travel) · S2 (same travel, ↓#) · S3 full frontier",
    "All 6 of Lewis's 22-May descriptive indicators, per country (deck pages 5–8)",
    "Catchments now by ROAD-network travel time (not Euclidean); #empty + smallest non-zero catchment reported",
    "Cap-ladder rungs prototyped (cost-function-free, exploratory): S1-A/B · S2-A/B — run for NL",
    "Recalculation done: candidates = ≥50-pop cells ∪ pharmacy cells · clients = FULL population · adapted logit (25/10) — all 42 areas re-swept, incl. Poland + its 7 NUTS-1",
    "Aggregated frontier over all 41 disjoint areas (exact by separability) — new page after the region pages",
    "LINEAR & LOGISTIC travel costs both run & compared",
  ]);
  col(4.62, AMBER, "FBF5EA", "In progress ◐", [
    "Investigate and fix sweeps for FRM, ITG, SE2 (diagnosed: baseline drops unreachable clients + w-grid truncation; DK the same)",
    "Extend the w-grid upward so S1 brackets everywhere — also unlocks aggregate S1/S2",
    "Fix baseline_metrics: it drops un-reachable clients (ITG ≈14% of pop) while the sweep prices them at c(t_max) — make consistent before any distance-to-Pareto metric",
    "A single 2-D status-quo→frontier distance metric (coverage-honest; stranded priced at c(t_max))",
    "Calculating better estimations for S1 and S2 (exact soft-coverage p-median MIP at p = baseline)",
    "Exploring (not committed): max-cap + min-threshold rungs — but the descriptives suggest realistic bounds are hard to set, so this may not pay off",
  ]);
  col(8.84, SLATE, "F2F5F8", "Remaining ○", [
    "Urban/non-urban flag → model only non-urban, hold urban fixed (options B/C)",
    "Settlement candidate set: verify existing ⊂ settlements, then restrict locations",
    "Flat-then-linear travel-cost variant; sweep logit-parameter sensitivity",
    "Calibrate real pharmacy a,b (schools: 99 699 + 3 277.5x); ?fixed cost vs <6-y care",
    "Communicate λ intuitively (person-minutes / value-per-user)",
    "Cost-function-free S3: balance #/capita vs mean travel, widen beyond the A–B segment",
    "Counterfactuals: −10% pop · replace a known X% · choose which X to close (hard)",
    "Pharmacist-based cap (Ana); caps/thresholds pooled across countries, reported per-country",
    "Border-cases",
    "Corr catchment & travel costs",
  ]);

  slide.addText([
    { text: "Open questions for the group:  ", options: { bold: true, color: NAVY } },
    { text: "is the cap/threshold ladder worth pursuing given how widely catchments vary?  ·  logistic vs linear travel cost (the equity-weighting choice)?  ·  best way to communicate λ?", options: { color: MUTED } },
  ], { x: 0.45, y: 6.5, w: 12.5, h: 0.7, fontSize: 10, italic: true, fontFace: "Calibri", valign: "top" });
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

  slide.addText("c(t) is applied to travel time in minutes (raw OD seconds ÷ 60); LINEAR uses c(t)=t. settings.jl:82",
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
    { text: "Full-scale ladder run incomplete; S1 (fixed-count) figures are sensitive to LP-relaxation rounding and can shift on re-run (robust multistart rounding still to be ported) — read the direction, not the exact %. LINEAR travel cost; max cap = NL observed cell-catchment max (~35k). 'stranded' = demand the cap can't serve within reach, priced at c(t_max).", options: { color: MUTED } },
  ], { x: 0.45, y: 6.72, w: 12.5, h: 0.55, fontSize: 8.5, italic: true, fontFace: "Calibri", valign: "top" });
}

// Proposed meeting agenda. Generated as the FIRST slide of region_summary.pptx;
// merge_deck.ps1 then moves it to position 2 (between the title and the rest of
// the concept slides). Marker text "Proposed agenda" is what the merge looks for.
function agendaSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText("AGENDA", { x: 0.45, y: 0.34, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "Proposed agenda  ", options: { bold: true, color: INK } },
    { text: "— assessing the current pharmacy distribution", options: { color: NAVY } },
  ], { x: 0.45, y: 0.62, w: 12.5, h: 0.5, fontSize: 24, fontFace: "Georgia" });

  const items = [
    ["Scope & method", "Tabula-rasa LP allocation + λ-sweep over the road-network OD; how to read the #facilities ↔ travel-cost frontier.", false],
    ["The current distribution", "Descriptive metrics per country & key NUTS1 — residents per pharmacy and catchment-size distributions, by road.", false],
    ["Scenario results", "S1 (same #, less travel) and S2 (same travel, fewer pharmacies) per country and NUTS1 — what the frontiers show so far.", false],
    ["Travel-cost function", "Logistic vs linear, and the adapted logit with kinks at ~5 & ~45 min (following page).", true],
    ["Cap / threshold ladder", "A proposed shortcut to the λ-sweep — but catchments vary so widely that realistic min/max bounds are hard to set. Pursue or drop?", true],
    ["Known issues & roadmap", "Baseline consistency (FRM / ITG / SE2; clients with no reachable pharmacy); priorities and next steps.", false],
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
    { text: "travel-cost shape (logistic vs linear / adapted logit)  ·  whether the cap–threshold ladder is worth pursuing  ·  how to communicate λ.", options: { color: MUTED } },
  ], { x: 0.45, y: 6.96, w: 12.5, h: 0.4, fontSize: 10, italic: true, fontFace: "Calibri", valign: "top" });
}

// Cross-region table of the λ that hits each scenario target, interpolated from
// the sweep points. S1: λ where the open-facility count equals the baseline #cells.
// S2: λ where the multistart travel cost equals the baseline travel. Per travel-cost
// function (LINEAR / LOGISTIC). λ = w · FACILITY_MIN_COSTS (settings.jl).
// opts: {eyebrow, titleRest, col0, label(e), pick(e), labelWide}.
const COUNTRY_SET = new Set(["Austria", "Belgium", "Czechia", "Denmark", "Estonia", "France", "Ireland", "Italy", "Latvia", "Lithuania", "Luxembourg", "Netherlands", "Norway", "Poland", "Portugal", "Slovenia", "Sweden"]);
function lambdaTableSlide(opts) {
  const FMIN = 100000;  // FACILITY_MIN_COSTS (settings.jl); λ = w · FMIN
  // log-interpolate w against `key` at `target`, between adjacent w-sorted sweep
  // rows that bracket it; null if target is outside the swept range (no bracket).
  const interp = (rows, key, target) => {
    if (!rows || rows.length < 2 || target == null) return null;
    for (let i = 0; i < rows.length - 1; i++) {
      const a = rows[i], b = rows[i + 1], xa = a[key], xb = b[key];
      if (xa == null || xb == null || !(a.w > 0) || !(b.w > 0) || xa === xb) continue;
      if (target >= Math.min(xa, xb) && target <= Math.max(xa, xb)) {
        const f = (target - xa) / (xb - xa);
        return Math.exp(Math.log(a.w) + f * (Math.log(b.w) - Math.log(a.w))) * FMIN;
      }
    }
    return null;
  };
  const fL = (v) => (v == null ? "—" : Math.round(v).toLocaleString("en-US"));
  const rowsC = data.filter((e) => opts.pick(e) && e.func.LINEAR && e.func.LINEAR.baseline);

  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText(opts.eyebrow, { x: 0.45, y: 0.28, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "Interpolated λ for S1 and S2  ", options: { bold: true, color: INK } },
    { text: opts.titleRest, options: { color: NAVY } },
  ], { x: 0.45, y: 0.54, w: 12.5, h: 0.5, fontSize: 22, fontFace: "Georgia" });

  const n = rowsC.length;
  const fs = n > 14 ? 9 : 11;
  const rh = Math.max(0.22, Math.min(0.34, 5.0 / (n + 1)));
  const c0 = opts.labelWide ? 3.3 : 2.6;
  const rest = (11.7 - c0 - 1.5) / 4;
  const colW = [c0, 1.5, rest, rest, rest, rest];

  const head = [opts.col0, "baseline #", "λ · S1 (lin)", "λ · S2 (lin)", "λ · S1 (log)", "λ · S2 (log)"];
  const body = [head.map((h) => ({ text: h, options: { bold: true, color: "FFFFFF", fill: NAVY, fontSize: Math.min(fs + 1, 11), align: h === opts.col0 ? "left" : "center", fontFace: "Calibri", margin: [2, 2, 2, 4] } }))];
  rowsC.forEach((e, i) => {
    const L = e.func.LINEAR, G = e.func.LOGISTIC;
    const cells = L.baseline.cells;
    const c = [opts.label(e), cells != null ? cells.toLocaleString("en-US") : "—",
      fL(interp(L.rows, "sum_x", cells)), fL(interp(L.rows, "multi", L.baseline.cost)),
      fL(G ? interp(G.rows, "sum_x", G.baseline.cells) : null), fL(G ? interp(G.rows, "multi", G.baseline.cost) : null)];
    const fill = i % 2 ? PANEL : "FFFFFF";
    body.push(c.map((v, ci) => ({ text: v, options: { fontSize: fs, align: ci === 0 ? "left" : "center", color: INK, fill, fontFace: "Calibri", valign: "middle", margin: [2, 2, 2, 4] } })));
  });
  slide.addTable(body, { x: 0.8, y: 1.68, w: 11.7, colW, rowH: rh, border: { type: "solid", color: "D9E0E7", pt: 0.5 }, valign: "middle" });

  slide.addText([
    { text: "λ = w · €100,000 (facility fixed-cost weight). ", options: { bold: true, color: NAVY } },
    { text: "S1 = λ at which the open-facility count equals the baseline #cells; S2 = λ at which the multistart travel cost equals the baseline — each log-interpolated between adjacent sweep points, per travel-cost function (lin / log). “—” = the baseline target lies outside the swept λ range (S1/S2 not yet bracketed — see roadmap).", options: { color: MUTED } },
  ], { x: 0.8, y: 6.9, w: 11.7, h: 0.5, fontSize: 9, italic: true, fontFace: "Calibri", valign: "top" });
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
  slide.addText([
    M("min", { bold: true, color: "8FD4F0" }), M("x,y", { fontSize: 10, subscript: true, color: "8FD4F0" }),
    M("   Σᵢ Σⱼ  popᵢ · c(tᵢⱼ) · yᵢⱼ   +   λ · Σⱼ xⱼ", {}),
  ], { x: 0.8, y: 1.55, w: 6.1, h: 0.45, fontSize: 16 });
  slide.addText([
    [M("s.t.", { bold: true, color: "8FD4F0" }), M("  Σⱼ yᵢⱼ  =  1"), M("          every client fully assigned", { fontFace: "Calibri", fontSize: 10.5, color: "9FB0C2" })],
    [M("      yᵢⱼ  ≤  xⱼ"), M("            only to open pharmacies", { fontFace: "Calibri", fontSize: 10.5, color: "9FB0C2" })],
    [M("      xⱼ ∈ {0,1}"), M("  →  relaxed to  0 ≤ xⱼ ≤ 1,   yᵢⱼ ≥ 0", { color: "FFD9A0" })],
  ].map((line) => line.map((seg, si) => ({ ...seg, options: { ...seg.options, breakLine: si === line.length - 1 } }))).flat(),
    { x: 0.8, y: 2.1, w: 6.1, h: 1.5, fontSize: 15, lineSpacingMultiple: 1.35 });
  slide.addText([
    M("i", { italic: true }), M(" = populated 1 km² cells (clients) · ", { fontFace: "Calibri", fontSize: 10.5, color: "C7D2DD" }),
    M("j", { italic: true }), M(" = candidate pharmacy cells · ", { fontFace: "Calibri", fontSize: 10.5, color: "C7D2DD" }),
    M("(i,j)", { italic: true }), M(" only where the road network gives tᵢⱼ ≤ t_max — the exported OD", { fontFace: "Calibri", fontSize: 10.5, color: "C7D2DD" }),
  ], { x: 0.8, y: 3.75, w: 6.0, h: 0.8, fontSize: 11, valign: "top" });

  // right column: ingredients
  const ing = (y, head, body) => {
    slide.addText(head, { x: 7.45, y, w: 5.4, h: 0.28, fontSize: 12.5, bold: true, color: NAVY, fontFace: "Calibri" });
    slide.addText(body, { x: 7.45, y: y + 0.27, w: 5.4, h: 0.62, fontSize: 10.5, color: MUTED, fontFace: "Calibri", valign: "top" });
  };
  ing(1.4, "c(t) — travel cost, t in minutes", "LINEAR c(t)=t; LOGISTIC c(t)=1/(1+e^−(t−30)/15). The swept LPs run once per function.");
  ing(2.32, "λ = w · €100,000 — the price of a pharmacy", "Linear facility cost a+b·q reduces to λ·#open: the b·q part is constant once every client is assigned, so only the fixed cost a matters.");
  ing(3.24, "One LP per λ, exact", "JuMP + HiGHS dual simplex; the model is built once and re-solved along the w-grid from the previous optimal basis (lp_run.jl solve_at_w!) — millions of yᵢⱼ, minutes per point.");
  // review flags — modelling details the group should challenge
  slide.addShape(pptx.ShapeType.roundRect, { x: 7.45, y: 4.22, w: 5.4, h: 0.78, rectRadius: 0.05, fill: { color: "FBF5EA" }, line: { color: "B9791C", width: 1 } });
  slide.addText([
    { text: "⚠ For review:  ", options: { bold: true, color: "B9791C" } },
    { text: "each client's OD is capped at its 5 nearest facilities (max_nr_facilities_per_client) — it shrinks the LP but limits reassignment choice; and in DK / ITG / FRM / SE2 not every client can be matched (unreachable within t_max → dropped from the baseline, forced-served in the LP), so ★ and frontier are not yet fully comparable there. Feedback welcome.", options: { color: INK } },
  ], { x: 7.58, y: 4.28, w: 5.16, h: 0.68, fontSize: 8.3, fontFace: "Calibri", valign: "top", lineSpacingMultiple: 0.98 });

  // bottom: bounds story
  slide.addShape(pptx.ShapeType.roundRect, { x: 0.5, y: 5.05, w: 12.33, h: 1.85, rectRadius: 0.06, fill: { color: PANEL }, line: { color: "D9E0E7", width: 1 } });
  slide.addText([
    { text: "Why the relaxation, and what it buys.  ", options: { bold: true, color: INK } },
    { text: "With xⱼ ∈ {0,1} this is the (NP-hard) uncapacitated facility-location problem, in its strong disaggregated formulation — one yᵢⱼ ≤ xⱼ per OD pair — whose LP relaxation is known to be nearly integral, which the sweeps confirm (frac_x stays small). The LP optimum is a certified ", options: { color: MUTED } },
    { text: "lower bound", options: { bold: true, color: BASE } },
    { text: " (the grey dashed line); rounding x* to a real set of pharmacies (multistart, p. 6) gives a feasible ", options: { color: MUTED } },
    { text: "upper bound", options: { bold: true, color: MULTI } },
    { text: " — the integer optimum is pinched between the two (+0–18% LINEAR, +0–4.7% LOGISTIC).", options: { color: MUTED, breakLine: true } },
    { text: "Relation to the p-median problem.  ", options: { bold: true, color: INK } },
    { text: "Imposing the count (Σⱼ xⱼ = p) instead of pricing it gives exactly the p-median problem with costs c(tᵢⱼ) (ReVelle & Swain 1970) — S1 at the baseline count is a p-median instance. The λ-sweep is its Lagrangian relaxation w.r.t. that constraint (Cornuéjols, Fisher & Nemhauser 1977): it recovers only the p’s on the lower convex envelope of the p-median value function, so p-values in non-convex gaps are unreachable by any λ — there S1/S2 are interpolated between sweep points, or pinned exactly with the cardinality constraint (roadmap: better S1/S2 estimations). The swap polish of p. 6 is the classic p-median vertex-substitution search.", options: { color: MUTED } },
  ], { x: 0.75, y: 5.2, w: 11.85, h: 1.62, fontSize: 10, fontFace: "Calibri", valign: "top" });

  slide.addText("Implementation: lp_run.jl (build_lp_warmstart / solve_at_w!) · weights popᵢ = total residents of cell i (CLIENT_WEIGHT=total_pop) · OD from GeoDMS impedance_matrix_od64, t = seconds/60.",
    { x: 0.5, y: 7.05, w: 12.33, h: 0.3, fontSize: 8.5, italic: true, color: MUTED, fontFace: "Calibri" });
}

// How the fractional LP solution is rounded to real pharmacies — the multistart
// method in lp_run.jl (multistart_round / swap_round! / travel_of), and why the
// result is an upper bound. merge_deck.ps1 moves this to position 6 via the
// marker "How multistart rounds".
function multistartSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  slide.addText("FROM FRACTIONS TO PHARMACIES", { x: 0.45, y: 0.3, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "How multistart rounds the LP relaxation  ", options: { bold: true, color: INK } },
    { text: "— and why it is an upper bound", options: { color: NAVY } },
  ], { x: 0.45, y: 0.56, w: 12.5, h: 0.5, fontSize: 22, fontFace: "Georgia" });

  const steps = [
    ["Fix the count", "p = round(Σ xⱼ*) — the integer pharmacy count nearest the LP's fractional total, so every rounded point stays on the same axis as the relaxation."],
    ["Seed 10 candidate sets", "top-p by x* and the lazy-greedy set (CELF, Leskovec et al. 2007 — marginal travel gains are submodular), so the result can never be worse than either; plus 8 x*-weighted random draws (Efraimidis–Spirakis 2006 A-Res); must-open pharmacies (x*≈1) are always kept."],
    ["Polish by swaps", "best-improving open↔closed swaps over the fractional pool — the classic p-median vertex-substitution search, in its fast-interchange form (Resende & Werneck 2007). Each swap is accepted only if the exact travel delta improves — cost strictly decreases, ≤ 12 rounds per seed."],
    ["Score coverage-honestly, keep the best", "every client priced at its nearest open pharmacy, c(t); a client left with no open pharmacy in the OD (stranded) is priced at c(t_max) — the worst travel time in the data, so abandoning remote clusters is never free. Lowest total wins."],
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
    { text: "The rounded set is a feasible point of the original problem: exactly p pharmacies actually open (x integer) and every client explicitly assigned. Feasible ⟹ its objective can only be ≥ the integer optimum, which is ≥ the LP optimum:", options: { color: INK, breakLine: true } },
    { text: "", options: { breakLine: true, fontSize: 4 } },
    { text: "LP relax  ≤  integer optimum  ≤  multistart", options: { bold: true, color: "1E7A52", align: "center", breakLine: true } },
    { text: "", options: { breakLine: true, fontSize: 4 } },
    { text: "Rigorous whenever stranded = 0 — the common case (see the summary table). With stranding, strict full-coverage is infeasible at that count; the point is then priced conservatively (c is non-decreasing, so c(t_max) ≥ any real within-OD assignment) and the stranded count is reported next to every figure.", options: { color: MUTED, breakLine: true } },
    { text: "", options: { breakLine: true, fontSize: 4 } },
    { text: "The multi-vs-relax column in the end tables is therefore a certified optimality gap: the integer optimum lies inside it.", options: { color: INK, italic: true, breakLine: true } },
  ], { x: 8.2, y: 1.88, w: 4.45, h: 3.35, fontSize: 10.5, fontFace: "Calibri", valign: "top", lineSpacingMultiple: 1.04 });

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
  agendaSlide();
  optProblemSlide();
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
  lambdaTableSlide({ eyebrow: "SCENARIO λ", titleRest: "— per country, by travel-cost function", col0: "country", pick: (e) => COUNTRY_SET.has(e.region), label: (e) => e.name });
  lambdaTableSlide({ eyebrow: "SCENARIO λ · NUTS-1", titleRest: "— FR / IT / SE NUTS-1 regions", col0: "NUTS-1 region", labelWide: true, pick: (e) => !COUNTRY_SET.has(e.region), label: (e) => `${e.region} · ${e.name}` });
  summarySlide(); statusSlide(); logisticSlide();
}

await pptx.writeFile({ fileName: join(__dir, outName) });
console.log(`wrote ${join(__dir, outName)} : ${regions.length} region slide(s)${(!only && !args.includes("--no-summary")) ? " + summary" : ""}`);
