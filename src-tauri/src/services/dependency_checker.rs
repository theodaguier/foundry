use std::process::Command;
use crate::commands::dependencies::DependencyStatus;

pub async fn check_all() -> Result<Vec<DependencyStatus>, Box<dyn std::error::Error>> {
    let mut deps = Vec::new();

    let xcode = check_cmd("xcode-select", &["-p"]).await;
    deps.push(DependencyStatus { name: "Xcode Command Line Tools".into(), installed: xcode.is_some(), detail: xcode.clone(), version: xcode });

    let cmake = check_cmd("cmake", &["--version"]).await;
    deps.push(DependencyStatus { name: "CMake".into(), installed: cmake.is_some(), detail: cmake.clone(), version: cmake });

    let juce_dir = crate::services::foundry_paths::juce_dir();
    deps.push(DependencyStatus { name: "JUCE SDK".into(), installed: juce_dir.exists(), detail: if juce_dir.exists() { Some(juce_dir.to_string_lossy().into()) } else { None }, version: None });

    let claude = check_cmd("claude", &["--version"]).await;
    deps.push(DependencyStatus { name: "Claude Code CLI".into(), installed: claude.is_some(), detail: claude.clone(), version: claude });

    Ok(deps)
}

async fn check_cmd(cmd: &str, args: &[&str]) -> Option<String> {
    let resolved = Command::new("/bin/zsh")
        .args(["-l", "-c", &format!("which {}", cmd)])
        .output().ok()
        .and_then(|o| if o.status.success() { String::from_utf8(o.stdout).ok().map(|s| s.trim().to_string()) } else { None })
        .unwrap_or_else(|| cmd.to_string());

    Command::new(&resolved).args(args).output().ok()
        .and_then(|o| if o.status.success() { String::from_utf8(o.stdout).ok().map(|s| s.trim().to_string()) } else { None })
}

pub async fn install_juce() -> Result<(), Box<dyn std::error::Error>> {
    log::info!("JUCE installation not yet implemented");
    Ok(())
}
