# (Re)build the status-quo<->frontier ANALYSIS slide section at the end of a deck.
# Idempotent: first DELETES any existing analysis slides (matched by title prefix),
# then appends the current doc\charts\*.png set. Safe to re-run after regenerating
# the charts (e.g. interp1 -> interp2) without duplicating slides.
#   powershell -File doc\rebuild_analysis_slides.ps1 [-Deck doc\lambda_sweep5.pptx]
param([string]$Deck = "doc\lambda_sweep5.pptx")
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)   # repo root

$RANK = 0.9130      # rank charts  1680x1840
$CLOUD = 1.4516     # point clouds 1800x1240
$LAXIS = 2.8333     # lambda-axis charts 2380x840 (doc\lambda_axis_chart.py)
$charts = @(
  @{f='doc\charts\lambda_axis_AGGREGATE.png';    t='The sweep read along lambda  -  all 41 areas: travel-cost bounds (left) and facility count (right)'; r=$LAXIS; n='x = lambda, the price per location (log scale). Left axis: LP relaxation (lower bound) and multistart integer solution (upper bound) on travel cost. Right axis: the LP-relaxed count sum_y and the integer count n_open = round(sum_y); they coincide by construction - the certified gap is on TOTAL cost only (p12). Dotted = baseline: S2 is where travel crosses its baseline, S1 where the count does; the guides are interpolated crossings, each labelled with the quantity that defines it - S1 with its facility count (today''s) and the facility cost lambda x N at that lambda, S2 with its travel cost (today''s) - so S1 reads the same count under LINEAR and LOGISTIC. The count axis is logarithmic and shared by both panels: same height = same count.'},
  @{f='doc\charts\lambda_axis_Netherlands.png';  t='The sweep read along lambda  -  Netherlands: travel-cost bounds (left) and facility count (right)'; r=$LAXIS; n='Same reading as the aggregate. The count falls over two decades of lambda before the travel bounds separate; under LINEAR they open only above ~EUR 50,000 per location, beyond S2, so the S1/S2 figures sit where lower and upper bound agree. S1 is 1,615 facilities under both cost functions by construction; the deck_data scenario rows would have put the guide a whole grid step off (1,334 LINEAR, 1,788 LOGISTIC), which is the S1/S2 snap noted on p9.'},
  @{f='doc\charts\pointcloud_LINEAR.png';        t='Baselines and their frontier projections  -  LINEAR';   r=$CLOUD},
  @{f='doc\charts\pointcloud_LOGISTIC.png';      t='Baselines and their frontier projections  -  LOGISTIC'; r=$CLOUD},
  @{f='doc\charts\rank_lambda_LINEAR.png';       t='Lambda at the balanced-improvement crossing, ranked  -  LINEAR';   r=$RANK; n='Lambda is in EUR only through the placeholder EUR 100,000 per location (REGIO review, Brons/BN): the crossing point and this ranking do not depend on it; only the EUR axis rescales with the true fixed cost.'},
  @{f='doc\charts\rank_lambda_LOGISTIC.png';     t='Lambda at the balanced-improvement crossing, ranked  -  LOGISTIC'; r=$RANK; n='Lambda is in EUR only through the placeholder EUR 100,000 per location (REGIO review, Brons/BN): the crossing point and this ranking do not depend on it; only the EUR axis rescales with the true fixed cost.'},
  @{f='doc\charts\rank_area_LINEAR.png';         t='Improvement-potential rectangle area (raw), ranked  -  LINEAR';   r=$RANK},
  @{f='doc\charts\rank_area_LOGISTIC.png';       t='Improvement-potential rectangle area (raw), ranked  -  LOGISTIC'; r=$RANK},
  @{f='doc\charts\rank_area_rel_LINEAR.png';     t='Improvement potential relative to baseline facility x travel cost  -  LINEAR';   r=$RANK},
  @{f='doc\charts\rank_area_rel_LOGISTIC.png';   t='Improvement potential relative to baseline facility x travel cost  -  LOGISTIC'; r=$RANK}
)
# any slide whose title starts with one of these is a previously-built analysis slide
$prefixes = @('The sweep read along lambda',
              'Baselines and their frontier projections',
              'Lambda at the balanced-improvement',
              'Improvement-potential rectangle',
              'Improvement potential relative')

$deckPath = (Resolve-Path $Deck).Path
$pp = New-Object -ComObject PowerPoint.Application
$d = $pp.Presentations.Open($deckPath, $false, $false, $false)
$before = $d.Slides.Count

# --- delete existing analysis slides (walk backwards; indices shift on delete) ---
$removed = 0
for ($i = $d.Slides.Count; $i -ge 1; $i--) {
  $s = $d.Slides.Item($i)
  if ($s.Shapes.Count -lt 1) { continue }
  $txt = ""
  try { if ($s.Shapes.Item(1).HasTextFrame) { $txt = $s.Shapes.Item(1).TextFrame.TextRange.Text } } catch { $txt = "" }
  foreach ($p in $prefixes) {
    if ($txt -and $txt.StartsWith($p)) { $s.Delete(); $removed++; break }
  }
}

# --- append the current chart set ---
$SW = 960.0; $SH = 540.0; $availTop = 70.0; $availH = 450.0
foreach ($c in $charts) {
  if (-not (Test-Path $c.f)) { Write-Warning "missing chart: $($c.f)"; continue }
  $slide = $d.Slides.Add($d.Slides.Count + 1, 12)   # 12 = ppLayoutBlank
  $tb = $slide.Shapes.AddTextbox(1, 30, 15, 900, 45)
  $tb.TextFrame.TextRange.Text = $c.t
  $tb.TextFrame.TextRange.Font.Size = 20
  $tb.TextFrame.TextRange.Font.Bold = $true
  $tb.TextFrame.TextRange.Font.Name = 'Calibri'
  $tb.TextFrame.TextRange.Font.Color.RGB = 0x503010
  $h = $availH; $w = $h * $c.r
  if ($w -gt 920) { $w = 920; $h = $w / $c.r }
  $picTop = $availTop + ($availH - $h) / 2
  [void]$slide.Shapes.AddPicture((Resolve-Path $c.f).Path, $false, $true, ($SW - $w) / 2, $picTop, $w, $h)
  if ($c.n) {   # caveat under the chart (ASCII only: this file has no BOM, PS 5.1 would read UTF-8 as ANSI).
                # Placed just below the picture, so a wide chart (which is short) leaves room for a
                # two-line note; a tall chart keeps the old fixed position at the slide's foot.
    $noteTop = [Math]::Min(518.0, $picTop + $h + 6)
    $nb = $slide.Shapes.AddTextbox(1, 30, $noteTop, 900, 20)
    $nb.TextFrame.TextRange.Text = $c.n
    $nb.TextFrame.TextRange.Font.Size = 9
    $nb.TextFrame.TextRange.Font.Italic = $true
    $nb.TextFrame.TextRange.Font.Name = 'Calibri'
    $nb.TextFrame.TextRange.Font.Color.RGB = 0x7B6B5B
  }
}
$d.Save()
"deck: $deckPath"
"  slides before=$before  removed=$removed  added=$($charts.Count)  after=$($d.Slides.Count)"
$d.Close(); $pp.Quit(); [System.Runtime.Interopservices.Marshal]::ReleaseComObject($pp) | Out-Null
