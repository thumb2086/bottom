<# 
.SYNOPSIS
    分析 btm-custom 產生的 CSV 記錄檔
#>

param(
    [string]$LogDir = "$env:USERPROFILE\.local\share\bottom\logs",
    [string]$Date = (Get-Date -Format "yyyyMMdd"),
    [switch]$ShowGpu,
    [switch]$ShowProcesses,
    [switch]$ExportHtml
)

$CsvPath = Join-Path $LogDir "metrics_$Date.csv"
if (-not (Test-Path $CsvPath)) {
    Write-Error "找不到 $CsvPath"
    exit 1
}

Write-Host "=== 分析 $CsvPath ===" -ForegroundColor Cyan

# 讀取 CSV（處理 JSON 欄位）
$Raw = Import-Csv $CsvPath

# 解析 JSON 欄位
$Data = $Raw | ForEach-Object {
    $_ | Select-Object @{N='Time';E={$_['timestamp']}},
        @{N='CPU_Total';E={[double]$_['cpu_total_percent']}},
        @{N='CPU_Cores';E={$_['cpu_per_core'] | ConvertFrom-Json}},
        @{N='Mem_Pct';E={[double]$_['memory_used_percent']}},
        @{N='Mem_Total_GB';E={[math]::Round([double]$_['memory_total_bytes']/1GB,2)}},
        @{N='Swap_Pct';E{[double]$_['swap_used_percent']}},
        @{N='Disk_Read_MBps';E{[math]::Round([double]$_['disk_read_bytes_per_sec']/1MB,2)}},
        @{N='Disk_Write_MBps';E{[math]::Round([double]$_['disk_write_bytes_per_sec']/1MB,2)}},
        @{N='Net_RX_MBps';E{[math]::Round([double]$_['network_rx_bytes_per_sec']/1MB,2)}},
        @{N='Net_TX_MBps';E{[math]::Round([double]$_['network_tx_bytes_per_sec']/1MB,2)}},
        @{N='GPU_Util';E={$_['gpu_util_percent'] | ConvertFrom-Json}},
        @{N='GPU_Mem';E={$_['gpu_memory_used_percent'] | ConvertFrom-Json}},
        @{N='GPU_Temp';E={$_['gpu_temperature'] | ConvertFrom-Json}},
        @{N='Top_Procs';E={$_['top_processes'] | ConvertFrom-Json}}
}

# 統計摘要
$Stats = [pscustomobject]@{
    Samples      = $Data.Count
    Time_Range   = "$($Data[0].Time) 至 $($Data[-1].Time)"
    CPU_Avg      = [math]::Round(($Data | Measure-Object CPU_Total -Average).Average, 1)
    CPU_Max      = [math]::Round(($Data | Measure-Object CPU_Total -Maximum).Maximum, 1)
    Mem_Avg      = [math]::Round(($Data | Measure-Object Mem_Pct -Average).Average, 1)
    Mem_Max      = [math]::Round(($Data | Measure-Object Mem_Pct -Maximum).Maximum, 1)
    Disk_Read_Avg_MBps  = [math]::Round(($Data | Measure-Object Disk_Read_MBps -Average).Average, 2)
    Disk_Write_Avg_MBps = [math]::Round(($Data | Measure-Object Disk_Write_MBps -Average).Average, 2)
    Net_RX_Avg_MBps     = [math]::Round(($Data | Measure-Object Net_RX_MBps -Average).Average, 2)
    Net_TX_Avg_MBps     = [math]::Round(($Data | Measure-Object Net_TX_MBps -Average).Average, 2)
}

Write-Host "`n📊 系統指標摘要" -ForegroundColor Cyan
$Stats | Format-List

# GPU 詳細
if ($ShowGpu -and $Data[0].GPU_Util) {
    Write-Host "`n🎮 GPU 分析" -ForegroundColor Magenta
    $GpuData = $Data | Where-Object { $_.GPU_Util } | ForEach-Object {
        $util = $_['GPU_Util'][0][1]
        $mem  = $_['GPU_Mem'][0][1]
        $temp = $_['GPU_Temp'][0][1]
        [pscustomobject]@{
            Time   = $_['Time']
            GPU_Util = $util
            GPU_Mem_Pct = [math]::Round($mem, 1)
            GPU_Temp = $temp
        }
    }
    Write-Host "  平均 GPU 利用率: $([math]::Round(($GpuData | Measure-Object GPU_Util -Average).Average, 1))%"
    Write-Host "  最大 GPU 利用率: $($GpuData | Measure-Object GPU_Util -Maximum).Maximum%"
    Write-Host "  平均顯存使用率: $([math]::Round(($GpuData | Measure-Object GPU_Mem_Pct -Average).Average, 1))%"
    Write-Host "  平均溫度: $([math]::Round(($GpuData | Measure-Object GPU_Temp -Average).Average, 1))°C"
    $GpuData | Select-Object Time, GPU_Util, GPU_Mem_Pct, GPU_Temp | Format-Table -AutoSize
}

# 熱門程序
if ($ShowProcesses -and $Data[0].Top_Procs) {
    Write-Host "`n🔥 熱門程序 (依 CPU% 排序)" -ForegroundColor Yellow
    $AllProcs = $Data | ForEach-Object { $_['Top_Procs'] } | Where-Object { $_ }
    $ProcStats = $AllProcs | Group-Object name | ForEach-Object {
        $cpu = ($_.Group | Measure-Object cpu_percent -Average).Average
        $mem = ($_.Group | Measure-Object memory_percent -Average).Average
        $gpu = ($_.Group | Measure-Object gpu_util_percent -Average).Average
        [pscustomobject]@{
            Name         = $_.Name
            Count        = $_.Count
            Avg_CPU_Pct  = [math]::Round($cpu, 2)
            Avg_Mem_Pct  = [math]::Round($mem, 2)
            Avg_GPU_Pct  = [math]::Round($gpu, 2)
        }
    } | Sort-Object Avg_CPU_Pct -Descending | Select-Object -First 10
    $ProcStats | Format-Table -AutoSize
}

# 匯出 HTML 圖表
if ($ExportHtml) {
    $HtmlPath = Join-Path $LogDir "report_$Date.html"
    $Html = @"
<!DOCTYPE html>
<html><head><title>btm Report $Date</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<style>
body { font-family: sans-serif; margin: 20px; }
canvas { max-width: 100%; height: 300px; margin: 10px 0; }
h2 { color: #333; }
</style></head><body>
<h1>btm-custom 系統報告 - $Date</h1>
<p>樣本數: $($Stats.Samples) | 時間: $($Stats.Time_Range)</p>
<canvas id="cpuChart"></canvas>
<canvas id="memChart"></canvas>
<canvas id="diskChart"></canvas>
<canvas id="netChart"></canvas>
<canvas id="gpuChart"></canvas>
<script>
const times = $($Data | ForEach-Object { '"{0:HH:mm:ss}"' -f [datetime]$_['Time'] } | ConvertTo-Json -Compress);
const cpu = $($Data | ForEach-Object { $_['CPU_Total'] } | ConvertTo-Json -Compress);
const mem = $($Data | ForEach-Object { $_['Mem_Pct'] } | ConvertTo-Json -Compress);
const diskR = $($Data | ForEach-Object { $_['Disk_Read_MBps'] } | ConvertTo-Json -Compress);
const diskW = $($Data | ForEach-Object { $_['Disk_Write_MBps'] } | ConvertTo-Json -Compress);
const netR = $($Data | ForEach-Object { $_['Net_RX_MBps'] } | ConvertTo-Json -Compress);
const netT = $($Data | ForEach-Object { $_['Net_TX_MBps'] } | ConvertTo-Json -Compress);

function makeChart(ctx, label, data, color) {
    new Chart(ctx, {type:'line', data:{labels:times, datasets:[{label:label, data:data, borderColor:color, fill:false, tension:0.1}]}, options:{responsive:true, scales:{y:{beginAtZero:true}}}});
}
makeChart(document.getElementById('cpuChart').getContext('2d'), 'CPU Total %', cpu, '#e74c3c');
makeChart(document.getElementById('memChart').getContext('2d'), 'Memory %', mem, '#3498db');
makeChart(document.getElementById('diskChart').getContext('2d'), 'Disk Read MB/s', diskR, '#2ecc71');
makeChart(document.getElementById('diskChart').getContext('2d'), 'Disk Write MB/s', diskW, '#f39c12');
makeChart(document.getElementById('netChart').getContext('2d'), 'Net RX MB/s', netR, '#9b59b6');
makeChart(document.getElementById('netChart').getContext('2d'), 'Net TX MB/s', netT, '#e67e22');
</script>
</body></html>
"@
    $Html | Out-File -Encoding utf8 $HtmlPath
    Write-Host "`n📄 HTML 報告已產生：$HtmlPath" -ForegroundColor Green
}

Write-Host "`n✅ 分析完成" -ForegroundColor Green