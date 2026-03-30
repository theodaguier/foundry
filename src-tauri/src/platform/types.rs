use crate::models::plugin::PluginFormat;
use std::path::PathBuf;

/// Specification for a dependency check.
pub struct DependencySpec {
    pub name: &'static str,
    pub check_command: &'static str,
    pub check_args: &'static [&'static str],
}

/// Platform-specific install configuration for a plugin format.
pub struct InstallDir {
    pub path: PathBuf,
}

/// Single install operation used by platform installers.
/// This lets a platform batch multiple bundle copies/signing steps into one flow.
#[derive(Debug, Clone)]
pub struct InstallOperation {
    #[allow(dead_code)]
    pub format: PluginFormat,
    pub source: PathBuf,
    pub destination: PathBuf,
}

/// Bundle extension mapping.
pub struct BundleMapping {
    pub format_label: &'static str,
    pub extension: &'static str,
}
