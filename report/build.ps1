# build.ps1 — Compile HCMUT thesis with pdflatex
# Run from the report/ directory: .\build.ps1
# Requires: MiKTeX or TeX Live with pdflatex, bibtex, makeglossaries

$ErrorActionPreference = "Stop"
$doc = "main"

Write-Host "=== Pass 1: pdflatex ===" -ForegroundColor Cyan
pdflatex -interaction=nonstopmode "$doc.tex"

Write-Host "=== BibTeX ===" -ForegroundColor Cyan
bibtex $doc

Write-Host "=== Glossaries ===" -ForegroundColor Cyan
makeglossaries $doc

Write-Host "=== Pass 2: pdflatex ===" -ForegroundColor Cyan
pdflatex -interaction=nonstopmode "$doc.tex"

Write-Host "=== Pass 3: pdflatex (final) ===" -ForegroundColor Cyan
pdflatex -interaction=nonstopmode "$doc.tex"

if (Test-Path "$doc.pdf") {
    $size = (Get-Item "$doc.pdf").Length / 1KB
    Write-Host ""
    Write-Host "=== Done: $doc.pdf ($([math]::Round($size)) KB) ===" -ForegroundColor Green
    # Open PDF
    Start-Process "$doc.pdf"
} else {
    Write-Host "ERROR: $doc.pdf not produced - check $doc.log" -ForegroundColor Red
}
