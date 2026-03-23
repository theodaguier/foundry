use crate::commands::dependencies::DependencyStatus;
use crate::platform;
use crate::services::build_environment;

pub async fn check_all() -> Result<Vec<DependencyStatus>, String> {
    let mut deps = Vec::new();

    // Platform-specific dependencies (C++ toolchain, CMake, Claude CLI, etc.)
    for spec in platform::required_dependencies() {
        let result = platform::check_dependency(&spec);
        deps.push(DependencyStatus {
            name: spec.name.to_string(),
            installed: result.is_some(),
            detail: result.clone(),
            version: result,
        });
    }

    let environment = build_environment::get_build_environment().await?;
    deps.push(DependencyStatus {
        name: "JUCE SDK".into(),
        installed: environment.juce_path.is_some(),
        detail: environment.juce_path.as_ref().map(|path| {
            match environment.juce_source.as_deref() {
                Some(source) => format!("{} ({})", path, source),
                None => path.clone(),
            }
        }),
        version: Some(environment.juce_version),
    });

    Ok(deps)
}

pub async fn install_juce() -> Result<build_environment::BuildEnvironmentStatus, String> {
    build_environment::install_managed_juce().await
}
