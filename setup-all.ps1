<# 
.SYNOPSIS
    One-click full deployment: install + scheduled task + config + verification
#>

Write-Host "=== btm-custom One-Click Deploy ===" -ForegroundColor Cyan

# 1. Install main binary
Write-Host "`n[1/5] Installing main binary..." -ForegroundColor Yellow
.\install.ps1 -AddToPath -CreateShortcut

# 2. Create scheduled task (requires admin)
Write-Host "`n[2/5] Creating startup scheduled task..." -ForegroundColor Yellow
try {
    .\create-scheduled-task.ps1 -RunAsSystem
}
catch {
    Write-Warning "Scheduled task requires admin rights. Run manually later:"
    Write-Host "  PowerShell (Admin) > .\create-scheduled-task.ps1 -RunAsSystem"
}

# 3. Verify binary
Write-Host "`n[3/5] Verifying binary..." -ForegroundColor Yellow
$BtmPath = "$env:USERPROFILE\.local\bin\btm.exe"
if (Test-Path $BtmPath) {
    & $BtmPath --version
    Write-Host "Binary OK"
} else {
    Write-Error "Binary not found at $BtmPath"
}

# 4. Test GPU detection
Write-Host "`n[4/5] Testing GPU detection..." -ForegroundColor Yellow
$TestOut = & $BtmPath --disable_gpu=false --basic 2>&1 | Select-Object -First 5
if ($LASTEXITCODE -eq 0 -or $TestOut -match "GPU") {
    Write-Host "GPU detection OK"
} else {
    Write-Warning "GPU may need admin rights or driver support"
}

# 5. Test recording
Write-Host "`n[5/5] Testing recording (3 sec)..." -ForegroundColor Yellow
$TestLogDir = "$env:TEMP\btm-test-$(Get-Date -Format 'HHmmss')"
New-Item -ItemType Directory -Path $TestLogDir -Force | Out-Null
$Job = Start-Job -ScriptBlock {
    param($Path, $Log)
    & $Path --record --record_interval 1s --record_dir $Log --basic
} -ArgumentList $BtmPath, $TestLogDir
Start-Sleep 4
Stop-Job $Job
Remove-Job $Job -Force

$CsvFiles = Get-ChildItem $TestLogDir -Filter "metrics_*.csv" | Sort-Object LastWriteTime -Descending
if ($CsvFiles.Count -gt 0) {
    $CsvFile = $CsvFiles[0]
    $Lines = Get-Content $CsvFile.FullName -TotalCount 3
    Write-Host "Recording OK. File: $($CsvFile.FullName)"
    Write-Host "Header: $($Lines[0])"
    if ($Lines.Count -gt 1) {
        Write-Host "Data: $($Lines[1].Substring(0,[Math]::Min(100,$Lines[1].Length)))..."
    }
    Remove-Item $TestLogDir -Recurse -Force
} else {
    Write-Warning "Recording test produced no file"
}

Write-Host "`n=== Deploy Complete ===" -ForegroundColor Green
Write-Host "`nCommon commands:" -ForegroundColor Cyan
Write-Host "  btm --disable_gpu=false        # Live monitor"
Write-Host "  btm --record                   # Background record"
Write-Host "  btm --basic                    # Lightweight mode"
Write-Host "  .\btm-wrapper.ps1 live         # Wrapper script"
Write-Host "  .\analyze-logs.ps1 -ShowGpu    # Analyze logs"
Write-Host "`nConfig: $env:APPDATA\bottom\bottom.toml"
Write-Host "Logs: $env:USERPROFILE\.local\share\bottom\logs"