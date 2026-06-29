use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use std::fs;
use thiserror::Error;

#[derive(Debug, Error)]
pub enum ConfigError {
    #[error("Failed to read config file: {0}")]
    IoError(#[from] std::io::Error),
    #[error("Failed to parse JSON: {0}")]
    JsonError(#[from] serde_json::Error),
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct StreamConfig {
    pub url: String,
    pub api_key: String,
    pub account_id: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type")]
pub enum AgentConfig {
    #[serde(rename = "mt5_ea")]
    Mt5 {
        tcp_bind: String,
        symbol_map: HashMap<String, String>,
    },
    #[serde(rename = "binance_spot")]
    Binance {
        api_key: String,
        api_secret: String,
        api_url: String,
        symbol_map: HashMap<String, String>,
    },
    #[serde(rename = "okx_spot")]
    Okx {
        api_key: String,
        api_secret: String,
        passphrase: String,
        api_url: String,
        symbol_map: HashMap<String, String>,
    },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Config {
    pub stream: StreamConfig,
    pub agents: HashMap<String, AgentConfig>,
}

impl Config {
    pub fn load_from_file(path: &str) -> Result<Self, ConfigError> {
        let content = fs::read_to_string(path)?;
        let parsed: Config = serde_json::from_str(&content)?;
        Ok(parsed)
    }
}
