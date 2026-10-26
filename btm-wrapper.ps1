<# 
.SYNOPSIS
    btm-custom 便利包裝腳本：常用模式一鍵啟動
#>

param(
    [ValidateSet("live", "record", "basic", "gpu", "minimal")]
    [string]$Mode = "live",

    [string]$RecordDir = "$env:USERPROFILE\.local\share\bottom\logs",
    [string]$Interval = "5s",
    [int]$KeepDays = 30,
    [switch]$Compress,
    [switch]$NoGpu
)

$BtmPath = "$env:USERPROFILE\.local\bin\btm.exe"
if (-not (Test-Path $BtmPath)) {
    $BtmPath = "C:\Users\CPXru\Desktop\thumb\bottom\target\release\btm.exe"
}
if (-not (Test-Path $BtmPath)) {
    Write-Error "找不到 btm.exe，請先安裝"
    exit 1
}

switch ($Mode) {
    "live" {
        # 即時監控模式（預設）
        $Args = @("--disable_gpu=false")
        if ($NoGpu) { $Args = @() }
        Write-Host "🚀 啟動即時監控模式..." -ForegroundColor Cyan
        & $BtmPath @Args
    }
    "record" {
        # 背景記錄模式（適合排程/服務）
        if (-not (Test-Path $RecordDir)) {
            New-Item -ItemType Directory -Path $RecordDir -Force | Out-Null
        }
        $Args = @(
            "--record",
            "--record_interval", $Interval,
            "--record_dir", $RecordDir,
            "--record_keep_days", $KeepDays.ToString()
        )
        if ($Compress) { $Args += "--record_compress" }
        if (-not $NoGpu) { $Args += "--disable_gpu=false" }
        Write-Host "📝 啟動背景記錄模式..." -ForegroundColor Green
        Write-Host "  記錄目錄：$RecordDir"
        Write-Host "  間隔：$Interval"
        Write-Host "  保留：$KeepDays 天"
        if ($Compress) { Write-Host "  壓縮：啟用" }
        & $BtmPath @Args
    }
    "basic" {
        # 輕量模式（無圖表、低資源）
        $Args = @("--basic")
        if (-not $NoGpu) { $Args += "--disable_gpu=false" }
        Write-Host "⚡ 啟動輕量模式..." -ForegroundColor Yellow
        & $BtmPath @Args
    }
    "gpu" {
        # 專注 GPU 監控
        $Args = @("--disable_gpu=false", "--basic")
        Write-Host "🎮 啟動 GPU 專注模式..." -ForegroundColor Magenta
        & $BtmPath @Args
    }
    "minimal" {
        # 最小模式（僅文字、極低資源）
        $Args = @("--basic", "--hide_time", "--dot_marker")
        if (-not $NoGpu) { $Args += "--disable_gpu=false" }
        Write-Host "📱 啟動最小模式..." -ForegroundColor Gray
        & $BtmPath @Args
    }
}

# 使用範例
# .\btm-wrapper.ps1 live
# .\btm-wrapper.ps1 record --RecordDir D:\logs --Interval 10s --Compress
# .\btm-wrapper.ps1 basic
# .\btm-wrapper.ps1 gpu