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
  slide.addText("Charts: travel_relax & travel_multi (left), frac_x (2nd left), log₁₀(w) (right) vs sum_x; ★ baseline, ◆ S1, ■ S2.  multistart ≤ LP-relax bound; stranded clients priced at c(t_max).",
    { x: 0.5, y: 7.12, w: 12.33, h: 0.3, fontSize: 8.5, italic: true, color: MUTED, fontFace: "Calibri" });
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
    { text: "Status against Bernhard's & Lewis's framing  ", options: { bold: true, color: INK } },
    { text: "— implemented · in progress · remaining", options: { color: NAVY } },
  ], { x: 0.45, y: 0.54, w: 12.5, h: 0.5, fontSize: 21, fontFace: "Georgia" });

  const GREEN = "1E7A52", AMBER = "B9791C", SLATE = "5B6B7B";
  const col = (x, tint, fill, title, items) => {
    slide.addShape(pptx.ShapeType.roundRect, { x, y: 1.3, w: 4.07, h: 5.05, rectRadius: 0.05, fill: { color: fill }, line: { color: tint, width: 1 } });
    slide.addText(title, { x: x + 0.18, y: 1.42, w: 3.7, h: 0.32, fontSize: 13, bold: true, color: tint, fontFace: "Calibri" });
    slide.addText(items.map((t) => ({ text: t, options: { bullet: { indent: 12 }, breakLine: true } })),
      { x: x + 0.2, y: 1.82, w: 3.72, h: 4.45, fontSize: 9.5, color: INK, fontFace: "Calibri", lineSpacingMultiple: 1.0, paraSpaceAfter: 5, valign: "top" });
  };

  col(0.4, GREEN, "F0F6F2", "Implemented ✓", [
    "Tabula-rasa LP allocation — replaces the old one-by-one greedy",
    "Linear facility cost a+bx → reduces to λ·#facilities in the LP (λ = w·a, a=100k)",
    "λ-sweep → Pareto curve of #facilities vs travel cost",
    "Lewis's 3 cases live: S1 (same #, ↓travel) · S2 (same travel, ↓#) · S3 full frontier (↓both)",
    "LINEAR & LOGISTIC travel costs both run & compared (this deck)",
    "Inhabited-cell candidates; pharmacies merged per grid cell (1 992→1 617 in NL)",
    "Per-region (NUTS-1) analysis — 22 regions across FR/IT/SE/NL",
    "Fractional = the LP lower bound (travel_relax); rounded to integer by multistart, so we ship whole pharmacies — and the fractional LP is the cheap part",
  ]);
  col(4.62, AMBER, "FBF5EA", "In progress ◐", [
    "Status-quo → curve distance: coverage-honest (stranded priced at c(t_max)); a single 2-D distance metric still to formalize",
    "Logistic params: now midpoint 30 / scale 15 min — retune to Lewis's ~5 & ~45-min kinks, then sweep sensitivity",
    "Regional vs unconstrained-frontier gap — have per-region curves, not yet the \"how far from unconstrained\" comparison",
    "Investigate FR1, ITG, SE2 vs the much-lower baseline — higher λ required? (baseline & sweep use different location sets)",
  ]);
  col(8.84, SLATE, "F2F5F8", "Remaining ○", [
    "Calibrate a real pharmacy a,b (schools: 99 699 + 3 277.5x); decide if fixed cost depends on <6-y care",
    "Communicate λ intuitively — e.g. express it in travel-time-equivalent units (person-min per facility)",
    "Settlement candidate set: verify existing pharmacies ⊂ settlements, then restrict locations",
    "Catchment-realism check outside urban areas — any cell un-servable by one pharmacy?",
    "non-linear facility cost (after linear) · other travel shapes if needed",
    "Mixed-integer testing of S2 for a few small regions",
    "Lewis' indicators as in his e-mail of 22 May",
    "Aggregate Pareto frontier per country (combine the regional sweeps)",
    "Counterfactuals: −10% pop (easy) · replace a known X% (easy) · choose which X to close (hard)",
    "Analyse locations & client counts for NL and ITF",
  ]);

  slide.addText([
    { text: "Open questions for the group:  ", options: { bold: true, color: NAVY } },
    { text: "fixed cost constant with vs without <6-y care?  ·  logistic vs linear = the equity-weighting choice  ·  best way to communicate λ?", options: { color: MUTED } },
  ], { x: 0.45, y: 6.55, w: 12.5, h: 0.7, fontSize: 10, italic: true, fontFace: "Calibri", valign: "top" });
}

function logisticSlide() {
  const slide = pptx.addSlide();
  slide.background = { color: "FFFFFF" };
  const CUR = "185FA5", ALT = "1D9E75";
  slide.addText("TRAVEL-COST FUNCTION", { x: 0.45, y: 0.28, w: 9, h: 0.3, fontSize: 12, bold: true, color: MULTI, charSpacing: 2 });
  slide.addText([
    { text: "Logistic c(t)  ", options: { bold: true, color: INK } },
    { text: "— current vs a Lewis-tuned alternative", options: { color: NAVY } },
  ], { x: 0.45, y: 0.54, w: 12.5, h: 0.5, fontSize: 22, fontFace: "Georgia" });

  const p = join(__dir, "charts", "logistic_compare.png");
  if (existsSync(p)) slide.addImage({ path: p, x: 0.35, y: 1.55, w: 7.8, h: 4.21 });

  // right panel: parameters + value table + note
  slide.addText([{ text: "current", options: { bold: true, color: CUR } }, { text: "   midpoint 30 · scale 15", options: { color: MUTED } }],
    { x: 8.4, y: 1.6, w: 4.6, h: 0.28, fontSize: 12, fontFace: "Calibri" });
  slide.addText([{ text: "alternative", options: { bold: true, color: ALT } }, { text: "   midpoint 25 · scale 10", options: { color: MUTED } }],
    { x: 8.4, y: 1.92, w: 4.6, h: 0.28, fontSize: 12, fontFace: "Calibri" });

  const tbl = [["t (min)", "current", "alternative"],
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
    { text: "The alternative is lower below ~10 min (ignores minor relocations) and saturates by ~45 min (caps remote weight) — closer to Lewis's 22-May ask. Not yet swept; see roadmap.", options: { color: MUTED } },
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

  const head = ["region", P.cntLab, "residents", P.perLab, "p10", "p25", "p50", "p75", "p90", "max"];
  const body = [head.map((h) => ({ text: h, options: { bold: true, color: "FFFFFF", fill: NAVY, fontSize: Math.min(fs, 10), align: h === "region" ? "left" : "center", fontFace: "Calibri", margin: [1, 2, 1, 3] } }))];
  rows.forEach((r, i) => {
    const reg = r[ix.study_area]; const isC = COUNTRIES.has(reg); const hi = isC && anyNuts;
    const fill = hi ? "E6EDF4" : (i % 2 ? PANEL : "FFFFFF");
    const c = [(anyNuts && !isC ? "    " : "") + reg, nf(r[ix[P.cnt]]), fM(r[ix.n_residents]), nf(r[ix[P.per]]),
      nf(r[ix[P.d + "p10"]]), nf(r[ix[P.d + "p25"]]), nf(r[ix[P.d + "p50"]]), nf(r[ix[P.d + "p75"]]), nf(r[ix[P.d + "p90"]]), nf(r[ix[P.d + "max"]])];
    body.push(c.map((v, ci) => ({ text: v, options: {
      fontSize: fs, bold: hi, align: ci === 0 ? "left" : "center", color: INK,
      fill, fontFace: "Calibri", valign: "middle", margin: [1, 2, 1, 3] } })));
  });
  slide.addTable(body, { x: 0.5, y: 1.7, w: 12.33, colW: [2.2, 1.25, 1.3, 1.3, 1.16, 1.16, 1.16, 1.16, 1.16, 1.16], rowH, border: { type: "solid", color: "D9E0E7", pt: 0.5 }, valign: "middle" });
  const note = view === "pharm"
    ? "Catchment = residents whose nearest pharmacy is this one (a cell's catchment split evenly among the pharmacies in it); p10..max = percentiles of that per-pharmacy catchment."
    : "A location = a unique 1 km² cell with ≥1 pharmacy; catchment = residents whose nearest pharmacy cell is this one; p10..max = percentiles of that per-location catchment.";
  slide.addText(note + (anyNuts ? " Country rows bold, NUTS1 indented below." : "") + " Source: pharmacy_descriptives.csv (Lewis, 22 May).",
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

let regions = data;
if (only) regions = data.filter((e) => e.region === only);
if (!only && !args.includes("--no-summary")) {
  descriptivesSlide("pharmacy_descriptives.csv",       "pharm", "BASELINE · RESIDENTS PER PHARMACY",       "— per country");
  descriptivesSlide("pharmacy_descriptives_nuts1.csv", "pharm", "BASELINE · RESIDENTS PER PHARMACY",       "— key NUTS1 regions (FR / IT / SE)");
  descriptivesSlide("pharmacy_descriptives.csv",       "loc",   "BASELINE · RESIDENTS PER 1 KM² LOCATION", "— per country");
  descriptivesSlide("pharmacy_descriptives_nuts1.csv", "loc",   "BASELINE · RESIDENTS PER 1 KM² LOCATION", "— key NUTS1 regions (FR / IT / SE)");
  capSlide("cap_results_Netherlands.csv");
}
regions.forEach(regionSlide);
if (!only && !args.includes("--no-summary")) { summarySlide(); statusSlide(); logisticSlide(); }

await pptx.writeFile({ fileName: join(__dir, outName) });
console.log(`wrote ${join(__dir, outName)} : ${regions.length} region slide(s)${(!only && !args.includes("--no-summary")) ? " + summary" : ""}`);
