use crate::state::AppState;
use tauri::{command, State};

#[command]
pub async fn check_session(state: State<'_, AppState>) -> Result<Option<String>, String> {
    state.auth.check_session().await
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
    state.auth.verify_otp(&email, &code, is_signup).await
}

#[command]
pub async fn sign_up(
    email: String,
    password: String,
    state: State<'_, AppState>,
) -> Result<(), String> {
    log::info!("Signing up {}", email);
    state.auth.sign_up(&email, &password).await
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
