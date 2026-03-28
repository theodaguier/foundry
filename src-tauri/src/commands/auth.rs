use crate::state::AppState;
use crate::services::telemetry_service;
use tauri::{command, State};

#[command]
pub async fn check_session(state: State<'_, AppState>) -> Result<Option<String>, String> {
    let user_id = state.auth.check_session().await?;
    if user_id.is_some() {
        telemetry_service::sync_local_backlog(&state.auth);
    }
    Ok(user_id)
}

#[command]
pub async fn send_otp(email: String, state: State<'_, AppState>) -> Result<(), String> {
    log::info!("Sending OTP to {}", email);
    state.auth.send_otp(&email).await
}

#[command]
pub async fn verify_otp(
    email: String,
    code: String,
    is_signup: bool,
    state: State<'_, AppState>,
) -> Result<(), String> {
    log::info!("Verifying OTP for {} (signup: {})", email, is_signup);
    state.auth.verify_otp(&email, &code, is_signup).await?;
    telemetry_service::sync_local_backlog(&state.auth);
    Ok(())
}

#[command]
pub async fn sign_up(
    email: String,
    password: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    log::info!("Signing up {}", email);
    state.auth.sign_up(&email, &password).await?;
    telemetry_service::sync_local_backlog(&state.auth);
    Ok(())
}

#[command]
pub async fn sign_out(state: State<'_, AppState>) -> Result<(), String> {
    state.auth.sign_out().await
}

#[command]
pub async fn get_profile(
    user_id: String,
    state: State<'_, AppState>,
) -> Result<Option<serde_json::Value>, String> {
    state.auth.get_profile(&user_id).await
}

#[command]
pub async fn update_card_variant(
    user_id: String,
    variant: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    state.auth.update_card_variant(&user_id, &variant).await
}

#[command]
pub async fn assign_card_variant_batch(
    emails: Vec<String>,
    variant: String,
    state: State<'_, AppState>,
) -> Result<u32, String> {
    state.auth.assign_card_variant_batch(emails, &variant).await
}
