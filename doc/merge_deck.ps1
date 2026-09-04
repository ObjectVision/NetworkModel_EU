# Merge the concept slides of an existing deck (slides 2-4 of the base: Scenarios, Pareto
# frontier, Why fractional; its slide 1 title is dropped in favour of the generated one)
# with freshly generated region/summary slides, via PowerPoint COM. Operates on a COPY of the base deck and never calls
# Quit (COM may attach to a running PowerPoint where the base deck is open).
#
#   powershell -File merge_deck.ps1 [-Base lambda_sweep4.pptx] [-Insert region_summary.pptx]
#                                   [-Out lambda_sweep5.pptx] [-KeepFirst 4]
param(
  [string]$Base    = "$PSScriptRoot\lambda_sweep4.pptx",
  [string]$Insert  = "$PSScriptRoot\region_summary.pptx",
  [string]$Out     = "$PSScriptRoot\lambda_sweep5.pptx",
  [int]   $KeepFirst = 4,
  [int]   $MapsSlide = 6   # manually-authored NL maps slide in $Base; carried over after the NL results slide (0 = skip)
)
$ErrorActionPreference = "Stop"
$copy = Join-Path $env:TEMP ("deck_merge_{0}.pptx" -f ([guid]::NewGuid().ToString("N").Substring(0,8)))
Copy-Item $Base $copy -Force

$pp  = New-Object -ComObject PowerPoint.Application
$mso = [Microsoft.Office.Core.MsoTriState]
$deck = $pp.Presentations.Open($copy, $mso::msoFalse, $mso::msoFalse, $mso::msoFalse)
Write-Host "opened base copy: $($deck.Slides.Count) slides; keeping first $KeepFirst"

# drop the old result slides (everything after KeepFirst), back-to-front
for ($i = $deck.Slides.Count; $i -gt $KeepFirst; $i--) { $deck.Slides.Item($i).Delete() }

# append the new slides after the kept concept slides
$n = $deck.Slides.InsertFromFile($Insert, $KeepFirst)
Write-Host "inserted $n slides -> total $($deck.Slides.Count)"

# drop the base deck's hand-written title slide (May 2026, never updated); the generator's
# title slide replaces it and is moved to position 1 below. Found by marker so the base
# file itself need not change.
foreach ($sl in $deck.Slides) {
  $txt = ""
  foreach ($sh in $sl.Shapes) { if ($sh.HasTextFrame) { $txt += $sh.TextFrame.TextRange.Text } }
  if ($txt -cmatch "what the Netherlands sweep tells us") { $sl.Delete(); Write-Host "dropped the base title slide"; break }
}

# carry over the manually-authored NL maps slide from the base deck, placing it
# right after the Netherlands results slide. Rather than count the (now variable)
# number of leading descriptives / cap slides, find the NL results slide by its
# subtitle marker — robust to slide additions/removals. InsertFromFile reads a
# fresh copy so a locked/open $Base is not a problem.
if ($MapsSlide -gt 0) {
  $mapsCopy = Join-Path $env:TEMP ("maps_{0}.pptx" -f ([guid]::NewGuid().ToString("N").Substring(0,8)))
  Copy-Item $Base $mapsCopy -Force
  $nlPos = 0
  foreach ($sl in $deck.Slides) {
    $txt = ""
    foreach ($sh in $sl.Shapes) { if ($sh.HasTextFrame) { $txt += $sh.TextFrame.TextRange.Text } }
    if ($txt -match "multistart vs the LP-relax frontier") { $nlPos = $sl.SlideIndex; break }
  }
  if ($nlPos -eq 0) { $nlPos = $KeepFirst + 5 }   # fallback if the marker isn't found
  $m = $deck.Slides.InsertFromFile($mapsCopy, $nlPos, $MapsSlide, $MapsSlide)
  Write-Host "carried over $m maps slide(s) after NL results (slide $nlPos) -> total $($deck.Slides.Count)"
  Remove-Item $mapsCopy -Force -ErrorAction SilentlyContinue
}

# Move the generated concept slides into their positions among the kept slides:
#   title -> 1, agenda -> 2, descriptives -> 3..6, optimization-problem -> 7, scope -> 8, choice set -> 9,
#   tangent diagram -> 10, multistart summary -> 12.
# Each is generated at the head of $Insert and located by a marker phrase. Done
# last (after all index-based inserts) and in ascending target order; re-scan
# after every move because MoveTo shifts the indices.
function Move-ByMarker([string]$pattern, [int]$target) {
  $pos = 0
  foreach ($sl in $deck.Slides) {
    $txt = ""
    foreach ($sh in $sl.Shapes) { if ($sh.HasTextFrame) { $txt += $sh.TextFrame.TextRange.Text } }
    if ($txt -cmatch $pattern) { $pos = $sl.SlideIndex; break }   # case-sensitive: the agenda names the descriptives in lower case
  }
  if ($pos -gt 0 -and $pos -ne $target) { $deck.Slides.Item($pos).MoveTo($target); Write-Host "moved '$pattern' slide $pos -> $target" }
}
# Order (REGIO review, BN comment 4): what EXISTS before what we OPTIMISE, so the four
# descriptives slides go straight after the agenda. The two slides sharing a title are
# told apart by their subtitle. Then the model block, then (BN 41/42) the tangent
# diagram right before the kept "Scenarios" slide, and multistart after it.
Move-ByMarker "how far is today's network from the frontier" 1
Move-ByMarker "Proposed agenda" 2
Move-ByMarker "RESIDENTS PER PHARMACY[\s\S]*per country" 3
Move-ByMarker "RESIDENTS PER PHARMACY[\s\S]*key NUTS1" 4
Move-ByMarker "PER 1 KM. LOCATION[\s\S]*per country" 5
Move-ByMarker "PER 1 KM. LOCATION[\s\S]*key NUTS1" 6
Move-ByMarker "The optimization problem" 7
Move-ByMarker "What the model covers" 8
Move-ByMarker "The choice set" 9
Move-ByMarker "How one .* picks one point" 10
Move-ByMarker "How multistart rounds" 12

# ppSaveAsOpenXMLPresentation = 24
$deck.SaveAs($Out, 24)
$deck.Close()
Remove-Item $copy -Force -ErrorAction SilentlyContinue
Write-Host "saved $Out"
# NOTE: deliberately no `$pp.Quit()` so a user's open PowerPoint session is untouched.
