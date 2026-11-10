# Opens a console with a one-shot Telegraf test run (for report screenshots).
$Root = Split-Path -Parent $PSScriptRoot
Get-Content "$Root\windows\.env" | Where-Object { $_ -match '^[A-Z_]+=' } | ForEach-Object { $k, $v = $_ -split '=', 2; Set-Item "env:$k" $v }
$env:PR9_DIR = $Root
Set-Location "$Root\bin\telegraf"
Write-Host "PS $((Get-Location).Path)> .\telegraf.exe --config ..\..\windows\telegraf\telegraf.conf --test --test-wait 0" -ForegroundColor Yellow
.\telegraf.exe --config ..\..\windows\telegraf\telegraf.conf --test --test-wait 0 2>$null |
  Select-String -Pattern 'cpu=cpu-total|^> mem|^> disk,|^> swap|^> system|interface=Ethernet|^> processes|^> disk_load|^> diskio|^> device_info|service_name=Winmgmt' |
  ForEach-Object { $_.Line -replace ' \d{19}$', '' }
