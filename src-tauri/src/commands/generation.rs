use crate::models::config::{GenerationConfig, RefineConfig};
use crate::services::{build_environment, generation_pipeline};
use crate::state::AppState;
use tauri::{command, AppHandle, State};

#[command]
pub async fn start_generation(
    config: GenerationConfig,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let environment = build_environment::prepare_build_environment(true, None).await?;
    if environment.state != "ready" {
        return Err(build_environment::format_blocked_message(&environment));
    }

    let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel();
    {
        let mut token = state.build_cancel_token.lock().map_err(|e| e.to_string())?;
        *token = Some(cancel_tx);
    }
    let handle = app.clone();
    tauri::async_runtime::spawn(async move {
        generation_pipeline::run_generation(config, handle, cancel_rx).await;
    });
    Ok(())
}

#[command]
pub async fn start_refine(
    config: RefineConfig,
    app: AppHandle,
    state: State<'_, AppState>,
) -> Result<(), String> {
    let environment = build_environment::prepare_build_environment(true, None).await?;
    if environment.state != "ready" {
        return Err(build_environment::format_blocked_message(&environment));
    }

    let (cancel_tx, cancel_rx) = tokio::sync::oneshot::channel();
    {
        let mut token = state.build_cancel_token.lock().map_err(|e| e.to_string())?;
        *token = Some(cancel_tx);
    }
    let handle = app.clone();
    tauri::async_runtime::spawn(async move {
        generation_pipeline::run_refine(config, handle, cancel_rx).await;
    });
    Ok(())
}

#[command]
pub async fn cancel_build(state: State<'_, AppState>) -> Result<(), String> {
    let mut token = state.build_cancel_token.lock().map_err(|e| e.to_string())?;
    if let Some(tx) = token.take() {
        let _ = tx.send(());
    }
    Ok(())
}
