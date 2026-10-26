//! Recording configuration.

use serde::{Deserialize, Serialize};

/// Configuration for metrics recording.
#[derive(Clone, Debug, Default, Deserialize, Serialize)]
#[cfg_attr(feature = "generate_schema", derive(schemars::JsonSchema))]
#[cfg_attr(test, serde(deny_unknown_fields), derive(PartialEq))]
pub struct RecordingConfig {
    /// Enable metrics recording to CSV.
    #[serde(default)]
    pub enabled: bool,

    /// Recording interval (e.g. "5s", "1000ms").
    #[serde(default)]
    pub interval: Option<String>,

    /// Output directory for CSV files.
    #[serde(default)]
    pub output_dir: Option<String>,

    /// Number of days to keep CSV files.
    #[serde(default)]
    pub keep_days: Option<u32>,

    /// Compress old CSV files.
    #[serde(default)]
    pub compress: bool,
}