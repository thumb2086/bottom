<# 
.SYNOPSIS
    建立 Windows 排程任務：開機自動啟動 btm --record (背景記錄模式)
#>

param(
    [string]$BinaryPath = "$env:USERPROFILE\.local\bin\btm.exe",
    [string]$RecordDir = "$env:USERPROFILE\.local\share\bottom\logs",
    [string]$TaskName = "btm-auto-record",
    [string]$Description = "btm-custom 開機自動記錄系統指標 (CPU/GPU/磁碟/網路)",
    [switch]$RunAsSystem
)

Write-Host "=== 建立 btm 自動記錄排程任務 ===" -ForegroundColor Cyan

# 檢查執行檔
if (-not (Test-Path $BinaryPath)) {
    Write-Error "找不到 $BinaryPath，請先執行 install.ps1"
    exit 1
}

# 建立記錄目錄
if (-not (Test-Path $RecordDir)) {
    New-Item -ItemType Directory -Path $RecordDir -Force | Out-Null
}

# 建立動作參數
$Args = @(
    "--record",
    "--record_interval", "5s",
    "--record_dir", $RecordDir,
    "--record_keep_days", "30",
    "--record_compress",
    "--disable_gpu=false"
) -join " "

# 建立觸發器：開機時
$Trigger = New-ScheduledTaskTrigger -AtStartup

# 建立動作
$Action = New-ScheduledTaskAction -Execute $BinaryPath -Argument $Args

# 設定
$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 24)

# 註冊任務
$Principal = if ($RunAsSystem) {
    New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
} else {
    New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest
}

try {
    # 先移除舊任務
    Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue | Unregister-ScheduledTask -Confirm:$false

    Register-ScheduledTask `
        -TaskName $TaskName `
        -Description $Description `
        -Trigger $Trigger `
        -Action $Action `
        -Settings $Settings `
        -Principal $Principal `
        -Force

    Write-Host "✅ 排程任務已建立：$TaskName" -ForegroundColor Green
    Write-Host "  觸發：開機時"
    Write-Host "  執行：$BinaryPath $Args"
    Write-Host "  記錄目錄：$RecordDir"

    # 立即啟動（可選）
    Start-ScheduledTask -TaskName $TaskName
    Write-Host "已啟動任務"
}
catch {
    Write-Error "建立失敗：$($_.Exception.Message)"
    Write-Host "提示：以系統管理員身分執行 PowerShell" -ForegroundColor Yellow
}