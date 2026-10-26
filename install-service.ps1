<# 
.SYNOPSIS
    將 btm --record 安裝為 Windows 服務（使用 NSSM）
    需以系統管理員身分執行
#>

param(
    [string]$BtmPath = "$env:USERPROFILE\.local\bin\btm.exe",
    [string]$ServiceName = "btm-recorder",
    [string]$DisplayName = "btm-custom System Recorder",
    [string]$Description = "btm-custom 背景記錄系統指標 (CPU/GPU/磁碟/網路/程序)",
    [string]$RecordDir = "C:\logs\btm",
    [string]$Interval = "5s",
    [int]$KeepDays = 30,
    [switch]$Compress,
    [switch]$EnableGpu,
    [switch]$StartNow,
    [switch]$Uninstall
)

Write-Host "=== btm-recorder Windows 服務安裝程式 ===" -ForegroundColor Cyan

# 檢查管理員權限
$IsAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $IsAdmin) {
    Write-Error "請以系統管理員身分執行 PowerShell"
    exit 1
}

# 檢查 btm.exe
if (-not (Test-Path $BtmPath)) {
    Write-Error "找不到 $BtmPath，請先安裝 btm"
    exit 1
}

# NSSM 路徑
$NssmDir = "$env:TEMP\nssm"
$NssmExe = "$NssmDir\win64\nssm.exe"

if (-not (Test-Path $NssmExe)) {
    Write-Host "下載 NSSM..." -ForegroundColor Yellow
    $ZipPath = "$env:TEMP\nssm.zip"
    Invoke-WebRequest "https://nssm.cc/release/nssm-2.24.zip" -OutFile $ZipPath
    Expand-Archive -Path $ZipPath -DestinationPath $NssmDir -Force
    Write-Host "NSSM 已就緒：$NssmExe"
}

# 建立記錄目錄
if (-not (Test-Path $RecordDir)) {
    New-Item -ItemType Directory -Path $RecordDir -Force | Out-Null
}

# 組裝參數
$Args = @(
    "--record",
    "--record_interval", $Interval,
    "--record_dir", $RecordDir,
    "--record_keep_days", $KeepDays.ToString()
)
if ($Compress) { $Args += "--record_compress" }
if ($EnableGpu) { $Args += "--disable_gpu=false" }

$ArgsStr = $Args -join " "

if ($Uninstall) {
    Write-Host "移除服務 $ServiceName..." -ForegroundColor Yellow
    & $NssmExe stop $ServiceName 2>$null
    & $NssmExe remove $ServiceName confirm
    Write-Host "服務已移除"
    exit 0
}

# 安裝服務
Write-Host "安裝服務 $ServiceName..." -ForegroundColor Yellow
& $NssmExe install $ServiceName $BtmPath $ArgsStr

# 設定服務屬性
& $NssmExe set $ServiceName DisplayName $DisplayName
& $NssmExe set $ServiceName Description $Description
& $NssmExe set $ServiceName Start SERVICE_AUTO_START
& $NssmExe set $ServiceName AppStdout "$RecordDir\service.log"
& $NssmExe set $ServiceName AppStderr "$RecordDir\service_error.log"
& $NssmExe set $ServiceName AppRotateFiles 1
& $NssmExe set $ServiceName AppRotateBytes 10485760  # 10MB

# 設定復原動作
& $NssmExe set $ServiceName AppExit Default Restart
& $NssmExe set $ServiceName AppThrottle 1500

Write-Host "✅ 服務已安裝" -ForegroundColor Green
Write-Host "  服務名稱：$ServiceName"
Write-Host "  執行檔：$BtmPath"
Write-Host "  參數：$ArgsStr"
Write-Host "  記錄目錄：$RecordDir"

if ($StartNow) {
    Write-Host "啟動服務..." -ForegroundColor Yellow
    Start-Service $ServiceName -ErrorAction SilentlyContinue
    Start-Sleep 2
    $Status = Get-Service $ServiceName
    Write-Host "  狀態：$($Status.Status)"
}

Write-Host "`n管理指令：" -ForegroundColor Cyan
Write-Host "  開始：Start-Service $ServiceName"
Write-Host "  停止：Stop-Service $ServiceName"
Write-Host "  狀態：Get-Service $ServiceName"
Write-Host "  移除：.\install-service.ps1 -Uninstall"
Write-Host "  看日誌：Get-Content $RecordDir\service.log -Tail 20 -Wait"