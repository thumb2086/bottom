//! Metrics recorder for CSV logging.

use std::{
    fs::{File, OpenOptions},
    io::BufWriter,
    path::PathBuf,
    sync::mpsc,
    thread,
    time::{Duration, Instant},
};

use chrono::{DateTime, Local, NaiveDate};
use csv::Writer;
use serde_json;

use crate::{
    app::{data::DataStore, AppConfigFields},
    collection::{Data, DataCollector},
};

/// Recorded metrics data point.
#[derive(Debug, Clone, serde::Serialize)]
pub struct MetricsRecord {
    #[serde(serialize_with = "serialize_datetime")]
    pub timestamp: DateTime<Local>,
    pub cpu_total_percent: f64,
    pub cpu_per_core: Vec<f64>,
    pub memory_used_percent: f64,
    pub memory_total_bytes: u64,
    pub swap_used_percent: f64,
    pub disk_read_bytes_per_sec: u64,
    pub disk_write_bytes_per_sec: u64,
    pub network_rx_bytes_per_sec: u64,
    pub network_tx_bytes_per_sec: u64,
    pub gpu_util_percent: Vec<(String, u32)>,
    pub gpu_memory_used_percent: Vec<(String, f64)>,
    pub gpu_temperature: Vec<(String, Option<f32>)>,
    pub top_processes: Vec<ProcessRecord>,
}

fn serialize_datetime<S>(dt: &DateTime<Local>, serializer: S) -> Result<S::Ok, S::Error>
where
    S: serde::Serializer,
{
    serializer.serialize_str(&dt.to_rfc3339())
}

/// Top process record for CSV.
#[derive(Debug, Clone, serde::Serialize)]
pub struct ProcessRecord {
    pub pid: u32,
    pub name: String,
    pub cpu_percent: f64,
    pub memory_percent: f64,
    pub gpu_memory_bytes: u64,
    pub gpu_util_percent: u32,
}

/// Configuration for the recorder.
#[derive(Debug, Clone)]
pub struct RecorderConfig {
    pub enabled: bool,
    pub interval: Duration,
    pub output_dir: PathBuf,
    pub keep_days: u32,
    pub compress: bool,
}

/// Background recorder handle.
pub struct RecorderHandle {
    sender: mpsc::Sender<RecorderCommand>,
    thread_handle: Option<thread::JoinHandle<()>>,
}

impl Clone for RecorderHandle {
    fn clone(&self) -> Self {
        Self {
            sender: self.sender.clone(),
            thread_handle: None,
        }
    }
}

enum RecorderCommand {
    Record(Box<Data>),
    Shutdown,
}

impl RecorderHandle {
    /// Create a new recorder with the given configuration.
    pub fn new(config: RecorderConfig, data_store: DataStore) -> Self {
        let (sender, receiver) = mpsc::channel();

        let thread_handle = thread::spawn(move || {
            recorder_thread(config, receiver, data_store);
        });

        Self {
            sender,
            thread_handle: Some(thread_handle),
        }
    }

    /// Send a data snapshot for recording.
    pub fn record(&self, data: Box<Data>) {
        let _ = self.sender.send(RecorderCommand::Record(data));
    }

    /// Shutdown the recorder.
    pub fn shutdown(mut self) {
        let _ = self.sender.send(RecorderCommand::Shutdown);
        if let Some(handle) = self.thread_handle.take() {
            let _ = handle.join();
        }
    }
}

/// Main recorder thread function.
fn recorder_thread(config: RecorderConfig, receiver: mpsc::Receiver<RecorderCommand>, mut data_store: DataStore) {
    if !config.enabled {
        return;
    }

    // Create output directory
    std::fs::create_dir_all(&config.output_dir).ok();

    let mut current_date = Local::now().date_naive();
    let mut writer = create_writer(&config.output_dir, current_date, config.compress);

    let mut last_record = Instant::now();

    loop {
        match receiver.recv_timeout(config.interval) {
            Ok(RecorderCommand::Record(data)) => {
                // Update data store with the new data
                data_store.eat_data(data, &AppConfigFields::default());

                let now = Instant::now();
                if now.duration_since(last_record) >= config.interval {
                    if let Err(e) = write_metrics(&mut writer, &data_store, &config, &mut current_date) {
                        eprintln!("Failed to write metrics: {}", e);
                    }
                    last_record = now;
                }
            }
            Ok(RecorderCommand::Shutdown) => {
                // Final write
                let _ = write_metrics(&mut writer, &data_store, &config, &mut current_date);
                break;
            }
            Err(mpsc::RecvTimeoutError::Timeout) => {
                // Periodic write
                if let Err(e) = write_metrics(&mut writer, &data_store, &config, &mut current_date) {
                    eprintln!("Failed to write metrics: {}", e);
                }
                last_record = Instant::now();
            }
            Err(mpsc::RecvTimeoutError::Disconnected) => {
                break;
            }
        }
    }
}

/// Create a CSV writer for the given date.
fn create_writer(output_dir: &PathBuf, date: NaiveDate, _compress: bool) -> Writer<BufWriter<File>> {
    let filename = format!("metrics_{}.csv", date.format("%Y%m%d"));
    let path = output_dir.join(filename);
    let file = OpenOptions::new()
        .create(true)
        .append(true)
        .open(&path)
        .unwrap_or_else(|_| panic!("Failed to open {}", path.display()));
    let metadata = file.metadata().ok();
    let mut writer = Writer::from_writer(BufWriter::new(file));

    // Write header if file is empty
    if metadata.map(|m| m.len()).unwrap_or(0) == 0 {
        writer.write_record(&[
            "timestamp",
            "cpu_total_percent",
            "cpu_per_core",
            "memory_used_percent",
            "memory_total_bytes",
            "swap_used_percent",
            "disk_read_bytes_per_sec",
            "disk_write_bytes_per_sec",
            "network_rx_bytes_per_sec",
            "network_tx_bytes_per_sec",
            "gpu_util_percent",
            "gpu_memory_used_percent",
            "gpu_temperature",
            "top_processes",
        ]).ok();
        writer.flush().ok();
    }

    writer
}

/// Extract f32 from TypedTemperature.
fn typed_temp_to_f32(temp: &crate::app::data::TypedTemperature) -> f32 {
    match temp {
        crate::app::data::TypedTemperature::Celsius(v) => *v as f32,
        crate::app::data::TypedTemperature::Kelvin(v) => *v as f32,
        crate::app::data::TypedTemperature::Fahrenheit(v) => *v as f32,
    }
}

/// Write metrics to CSV.
fn write_metrics(
    writer: &mut Writer<BufWriter<File>>,
    data_store: &DataStore,
    config: &RecorderConfig,
    current_date: &mut NaiveDate,
) -> Result<(), Box<dyn std::error::Error>> {
    let data = data_store.get_data();
    let now = Local::now();

    // Check if date changed
    let today = now.date_naive();
    if today != *current_date {
        *current_date = today;
        // Create new writer for new date
        *writer = create_writer(&config.output_dir, today, config.compress);
    }

    // Collect CPU data
    let cpu_total = data.cpu_harvest.iter().map(|c| c.usage as f64).sum::<f64>();
    let cpu_per_core: Vec<f64> = data.cpu_harvest.iter().map(|c| c.usage as f64).collect();

    // Memory
    let memory_used_percent = data.ram_harvest.as_ref().map(|m| m.percentage()).unwrap_or(0.0);
    let memory_total_bytes = data.ram_harvest.as_ref().map(|m| m.total_bytes.get()).unwrap_or(0);
    let swap_used_percent = data.swap_harvest.as_ref().map(|m| m.percentage()).unwrap_or(0.0);

    // Disk I/O
    let disk_read: u64 = data.disk_harvest.iter().filter_map(|d| d.io_read_rate_bytes).sum();
    let disk_write: u64 = data.disk_harvest.iter().filter_map(|d| d.io_write_rate_bytes).sum();

    // Network
    let network_rx = data.network_harvest.rx;
    let network_tx = data.network_harvest.tx;

    // GPU utilization
    let gpu_util: Vec<(String, u32)> = data.gpu_util_harvest.clone();
    let gpu_memory: Vec<(String, f64)> = data.gpu_harvest.iter().map(|(n, m)| (n.clone(), m.percentage())).collect();
    let gpu_temp: Vec<(String, Option<f32>)> = data.temp_data.iter()
        .filter(|t| t.sensor.to_lowercase().contains("gpu"))
        .map(|t| (t.sensor.clone(), t.temperature.as_ref().map(typed_temp_to_f32)))
        .collect();

    // Top processes (by CPU)
    let mut processes: Vec<ProcessRecord> = data.process_data.process_harvest.iter().map(|(_, p)| ProcessRecord {
        pid: p.pid as u32,
        name: p.name.clone(),
        cpu_percent: p.cpu_usage_percent as f64,
        memory_percent: p.mem_usage_percent as f64,
        gpu_memory_bytes: p.gpu_mem,
        gpu_util_percent: p.gpu_util,
    }).collect();
    processes.sort_by(|a, b| b.cpu_percent.partial_cmp(&a.cpu_percent).unwrap());
    let top_processes = processes.into_iter().take(5).collect::<Vec<_>>();

    let record = MetricsRecord {
        timestamp: now,
        cpu_total_percent: cpu_total,
        cpu_per_core,
        memory_used_percent,
        memory_total_bytes,
        swap_used_percent,
        disk_read_bytes_per_sec: disk_read,
        disk_write_bytes_per_sec: disk_write,
        network_rx_bytes_per_sec: network_rx,
        network_tx_bytes_per_sec: network_tx,
        gpu_util_percent: gpu_util,
        gpu_memory_used_percent: gpu_memory,
        gpu_temperature: gpu_temp,
        top_processes,
    };

    // Serialize complex fields to JSON strings
    let cpu_per_core_json = serde_json::to_string(&record.cpu_per_core)?;
    let gpu_util_json = serde_json::to_string(&record.gpu_util_percent)?;
    let gpu_memory_json = serde_json::to_string(&record.gpu_memory_used_percent)?;
    let gpu_temp_json = serde_json::to_string(&record.gpu_temperature)?;
    let top_processes_json = serde_json::to_string(&record.top_processes)?;

    writer.write_record(&[
        &record.timestamp.to_rfc3339(),
        &record.cpu_total_percent.to_string(),
        &cpu_per_core_json,
        &record.memory_used_percent.to_string(),
        &record.memory_total_bytes.to_string(),
        &record.swap_used_percent.to_string(),
        &record.disk_read_bytes_per_sec.to_string(),
        &record.disk_write_bytes_per_sec.to_string(),
        &record.network_rx_bytes_per_sec.to_string(),
        &record.network_tx_bytes_per_sec.to_string(),
        &gpu_util_json,
        &gpu_memory_json,
        &gpu_temp_json,
        &top_processes_json,
    ])?;

    writer.flush()?;
    Ok(())
}