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
# right after the Netherlands results slide. The first two generated slides are the
# descriptives tables (country + NUTS1), then the NL results, so NL sits at
# KeepFirst+3. InsertFromFile reads a fresh copy so a locked/open $Base is not a problem.
if ($MapsSlide -gt 0) {
  $mapsCopy = Join-Path $env:TEMP ("maps_{0}.pptx" -f ([guid]::NewGuid().ToString("N").Substring(0,8)))
  Copy-Item $Base $mapsCopy -Force
  $nlPos = $KeepFirst + 3
  $m = $deck.Slides.InsertFromFile($mapsCopy, $nlPos, $MapsSlide, $MapsSlide)
  Write-Host "carried over $m maps slide(s) after slide $nlPos -> total $($deck.Slides.Count)"
  Remove-Item $mapsCopy -Force -ErrorAction SilentlyContinue
}

# ppSaveAsOpenXMLPresentation = 24
$deck.SaveAs($Out, 24)
$deck.Close()
Remove-Item $copy -Force -ErrorAction SilentlyContinue
Write-Host "saved $Out"
# NOTE: deliberately no `$pp.Quit()` so a user's open PowerPoint session is untouched.
