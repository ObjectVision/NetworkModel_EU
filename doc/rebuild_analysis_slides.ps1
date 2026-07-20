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
$charts = @(
  @{f='doc\charts\pointcloud_LINEAR.png';        t='Baselines and their frontier projections  -  LINEAR';   r=$CLOUD},
  @{f='doc\charts\pointcloud_LOGISTIC.png';      t='Baselines and their frontier projections  -  LOGISTIC'; r=$CLOUD},
  @{f='doc\charts\rank_lambda_LINEAR.png';       t='Lambda at the balanced-improvement crossing, ranked  -  LINEAR';   r=$RANK},
  @{f='doc\charts\rank_lambda_LOGISTIC.png';     t='Lambda at the balanced-improvement crossing, ranked  -  LOGISTIC'; r=$RANK},
  @{f='doc\charts\rank_area_LINEAR.png';         t='Improvement-potential rectangle area (raw), ranked  -  LINEAR';   r=$RANK},
  @{f='doc\charts\rank_area_LOGISTIC.png';       t='Improvement-potential rectangle area (raw), ranked  -  LOGISTIC'; r=$RANK},
  @{f='doc\charts\rank_area_rel_LINEAR.png';     t='Improvement potential relative to baseline facility x travel cost  -  LINEAR';   r=$RANK},
  @{f='doc\charts\rank_area_rel_LOGISTIC.png';   t='Improvement potential relative to baseline facility x travel cost  -  LOGISTIC'; r=$RANK}
)
# any slide whose title starts with one of these is a previously-built analysis slide
$prefixes = @('Baselines and their frontier projections',
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
  [void]$slide.Shapes.AddPicture((Resolve-Path $c.f).Path, $false, $true,
                                 ($SW - $w) / 2, $availTop + ($availH - $h) / 2, $w, $h)
}
$d.Save()
"deck: $deckPath"
"  slides before=$before  removed=$removed  added=$($charts.Count)  after=$($d.Slides.Count)"
$d.Close(); $pp.Quit(); [System.Runtime.Interopservices.Marshal]::ReleaseComObject($pp) | Out-Null
