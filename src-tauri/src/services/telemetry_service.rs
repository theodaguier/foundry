use std::fs;
use crate::models::telemetry::GenerationTelemetry;
use crate::services::foundry_paths;

pub fn load(id: String) -> Result<Option<GenerationTelemetry>, Box<dyn std::error::Error>> {
    let path = foundry_paths::telemetry_dir().join(format!("{}.json", id));
    if !path.exists() { return Ok(None); }
    let data = fs::read_to_string(&path)?;
    Ok(Some(serde_json::from_str(&data)?))
}

pub fn load_all() -> Result<Vec<GenerationTelemetry>, Box<dyn std::error::Error>> {
    let dir = foundry_paths::telemetry_dir();
    if !dir.exists() { return Ok(Vec::new()); }
    let mut results = Vec::new();
    for entry in fs::read_dir(&dir)? {
        let entry = entry?;
        if entry.path().extension().map_or(false, |ext| ext == "json") {
            if let Ok(data) = fs::read_to_string(entry.path()) {
                if let Ok(t) = serde_json::from_str::<GenerationTelemetry>(&data) {
                    results.push(t);
                }
            }
        }
    }
    Ok(results)
}
