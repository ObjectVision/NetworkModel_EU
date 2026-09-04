# Merge concept slides 1-4 of an existing deck with freshly generated region/summary
# slides, via PowerPoint COM. Operates on a COPY of the base deck and never calls
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
#   agenda -> 2, optimization-problem -> 3, scope -> 4, choice set -> 5, multistart summary -> 7.
# Each is generated at the head of $Insert and located by a marker phrase. Done
# last (after all index-based inserts) and in ascending target order; re-scan
# after every move because MoveTo shifts the indices.
function Move-ByMarker([string]$pattern, [int]$target) {
  $pos = 0
  foreach ($sl in $deck.Slides) {
    $txt = ""
    foreach ($sh in $sl.Shapes) { if ($sh.HasTextFrame) { $txt += $sh.TextFrame.TextRange.Text } }
    if ($txt -match $pattern) { $pos = $sl.SlideIndex; break }
  }
  if ($pos -gt 0 -and $pos -ne $target) { $deck.Slides.Item($pos).MoveTo($target); Write-Host "moved '$pattern' slide $pos -> $target" }
}
Move-ByMarker "Proposed agenda" 2
Move-ByMarker "The optimization problem" 3
Move-ByMarker "What the model covers" 4
Move-ByMarker "The choice set" 5
Move-ByMarker "How multistart rounds" 7

# ppSaveAsOpenXMLPresentation = 24
$deck.SaveAs($Out, 24)
$deck.Close()
Remove-Item $copy -Force -ErrorAction SilentlyContinue
Write-Host "saved $Out"
# NOTE: deliberately no `$pp.Quit()` so a user's open PowerPoint session is untouched.
