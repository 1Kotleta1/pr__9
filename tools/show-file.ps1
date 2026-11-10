# Prints part of a text file in a console window (for report screenshots).
param([string]$Path, [int]$Skip = 0, [int]$First = 60)
Set-Location (Split-Path -Parent $Path)
$name = Split-Path -Leaf $Path
Write-Host "PS $((Get-Location).Path)> Get-Content .\$name -Encoding UTF8 | Select-Object -Skip $Skip -First $First" -ForegroundColor Yellow
Get-Content $Path -Encoding UTF8 | Select-Object -Skip $Skip -First $First
