# btm-custom v0.14.9

Fork 自 [ClementTsang/bottom](https://github.com/ClementTsang/bottom)，新增 **Windows GPU 利用率** 與 **全指標 CSV 記錄** 功能。

## ✨ 新增功能

| 功能 | 說明 |
|------|------|
| **NVIDIA GPU 利用率** | 直接呼叫 NVML，支援 GPU%、顯存%、溫度、功耗、時脈 |
| **AMD/Intel GPU** | Linux 下支援 amdgpu / i915 / xe 驅動 |
| **GPU Time Series** | TUI 內可切換 GPU 利用率圖表（Tab 鍵） |
| **全指標 CSV 記錄** | `--record` 參數每 N 秒寫入 CSV |
| **記錄輪轉/壓縮** | 每日新檔、保留天數、自動 gzip 壓縮 |

---

## 🚀 快速開始

### 1. 安裝
```powershell
# 以系統管理員身分執行
.\install.ps1 -AddToPath -CreateShortcut
```

### 2. 常用模式
```powershell
# 即時監控（含 GPU）
btm --disable_gpu=false

# 背景記錄（適合排程/服務）
btm --record --record_interval 5s --record_dir C:\logs\btm --record_keep_days 30 --record_compress

# 輕量模式（無圖表、低資源）
btm --basic

# 使用包裝腳本
.\btm-wrapper.ps1 live          # 即時監控
.\btm-wrapper.ps1 record        # 背景記錄
.\btm-wrapper.ps1 basic         # 輕量模式
.\btm-wrapper.ps1 gpu           # GPU 專注
```

### 3. 開機自動記錄
```powershell
# 以系統管理員身分執行
.\create-scheduled-task.ps1
```

---

## 📊 記錄檔分析
```powershell
# 基本分析
.\analyze-logs.ps1

# 含 GPU 詳細、熱門程序
.\analyze-logs.ps1 -ShowGpu -ShowProcesses

# 匯出互動式 HTML 圖表
.\analyze-logs.ps1 -ExportHtml
```

---

## 📋 CSV 欄位說明

| 欄位 | 說明 |
|------|------|
| `timestamp` | RFC3339 時間戳 |
| `cpu_total_percent` | 總 CPU 使用率 |
| `cpu_per_core` | 各核心使用率 (JSON 陣列) |
| `memory_used_percent` | 記憶體使用率 |
| `memory_total_bytes` | 總記憶體位元組 |
| `swap_used_percent` | Swap 使用率 |
| `disk_read_bytes_per_sec` | 磁碟讀取速度 |
| `disk_write_bytes_per_sec` | 磁碟寫入速度 |
| `network_rx_bytes_per_sec` | 網路接收速度 |
| `network_tx_bytes_per_sec` | 網路發送速度 |
| `gpu_util_percent` | GPU 利用率 (JSON: `[["GPU名",%]]`) |
| `gpu_memory_used_percent` | 顯存使用率 (JSON) |
| `gpu_temperature` | GPU 溫度 (JSON) |
| `top_processes` | Top 5 程序 (JSON: pid, name, cpu%, mem%, gpu_mem, gpu%) |

---

## ⌨️ TUI 快捷鍵

| 按鍵 | 功能 |
|------|------|
| `Tab` / `Shift+Tab` | 切換 Widget (CPU/記憶體/網路/磁碟/GPU/程序/溫度) |
| `↑/↓` / `j/k` | 程序列表上下 |
| `Enter` | 展開/折疊程序群組 |
| `d` | 顯示/隱藏磁碟 I/O 細節 |
| `n` | 顯示/隱藏網路細節 |
| `m` | 切換記憶體顯示模式 |
| `c` | 切換 CPU 顯示模式 |
| `g` | 切換程序分組 |
| `t` | 切換樹狀檢視 |
| `/` | 搜尋程序 |
| `k` / `K` | 送訊號 / 強制終止程序 |
| `h` / `?` | 顯示說明 |
| `q` / `Esc` | 離開 |

---

## 🔧 開發/建置

```bash
# 需求：Rust 1.95+、Git
git clone https://github.com/thumb2086/bottom
cd bottom
cargo build --release

# 執行檔位置
./target/release/btm.exe
```

### 依賴新增
- `nvml-wrapper` (NVIDIA GPU)
- `chrono` (時間處理)
- `csv` (CSV 寫入)
- `serde_json` (JSON 序列化)

---

## 📁 專案結構

```
bottom/
├── src/
│   ├── recorder.rs                    # CSV 記錄器核心
│   ├── collection/gpu/nvidia.rs       # NVML 直接呼叫
│   ├── collection/gpu/amd.rs          # AMD GPU (Linux)
│   ├── collection/gpu/intel.rs        # Intel GPU (Linux)
│   ├── app/data/time_series.rs        # GPU Time Series
│   ├── options/args.rs                # CLI 參數 (--record 等)
│   └── options/config/recording.rs    # 設定檔結構
├── install.ps1                        # 安裝腳本
├── create-scheduled-task.ps1          # 排程任務
├── btm-wrapper.ps1                    # 便利包裝
└── analyze-logs.ps1                   # 記錄分析
```

---

## 🐛 已知問題 / TODO

- [ ] Windows 上 Intel GPU 需額外驅動支援
- [ ] 記錄模式下 TUI 會佔用終端機（建議用排程任務背景執行）
- [ ] GPU 溫度單位統一（目前依 NVML 回傳）
- [ ] 遠端監控/推送到 InfluxDB/Prometheus

---

## 📄 授權

MIT License - 同原專案