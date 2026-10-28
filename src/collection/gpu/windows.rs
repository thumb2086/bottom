//! Windows GPU utilization via nvidia-smi
//! Uses nvidia-smi to get real-time GPU utilization instead of NVML's sampled/averaged values.

#[cfg(target_os = "windows")]
use std::process::Command;

/// Get GPU utilization from nvidia-smi
#[cfg(target_os = "windows")]
pub fn get_windows_gpu_utilization() -> Vec<(String, u32)> {
    // Use nvidia-smi which is fast and reliable
    let output = Command::new("nvidia-smi")
        .args([
            "--query-gpu=utilization.gpu",
            "--format=csv,noheader,nounits"
        ])
        .output();
    
    match output {
        Ok(result) => {
            let stdout = String::from_utf8_lossy(&result.stdout);
            let util_str = stdout.trim();
            if let Ok(util) = util_str.parse::<u32>() {
                if util <= 100 {
                    return vec![("GPU 0".to_string(), util)];
                }
            }
            vec![]
        }
        Err(_) => vec![],
    }
}

/// Get GPU utilization percentage for a specific GPU by name
#[cfg(target_os = "windows")]
pub fn get_gpu_util_by_name(gpu_name: &str) -> Option<u32> {
    let results = get_windows_gpu_utilization();
    for (name, util) in results {
        if name.contains(&gpu_name.split_whitespace().last().unwrap_or("")) {
            return Some(util);
        }
    }
    None
}

// Non-Windows stub
#[cfg(not(target_os = "windows"))]
pub fn get_windows_gpu_utilization() -> Vec<(String, u32)> {
    vec![]
}

#[cfg(not(target_os = "windows"))]
pub fn get_gpu_util_by_name(_gpu_name: &str) -> Option<u32> {
    None
}