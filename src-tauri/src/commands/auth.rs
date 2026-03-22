use tauri::command;

#[command]
pub async fn check_session() -> Result<Option<String>, String> {
    Ok(None)
}

#[command]
pub async fn send_otp(email: String) -> Result<(), String> {
    log::info!("Sending OTP to {}", email);
    Ok(())
}

#[command]
pub async fn verify_otp(email: String, _code: String, is_signup: bool) -> Result<(), String> {
    log::info!("Verifying OTP for {} (signup: {})", email, is_signup);
    Ok(())
}

#[command]
pub async fn sign_up(email: String, _password: String) -> Result<(), String> {
    log::info!("Signing up {}", email);
    Ok(())
}

#[command]
pub async fn sign_out() -> Result<(), String> {
    Ok(())
}

#[command]
pub async fn get_profile(_user_id: String) -> Result<Option<serde_json::Value>, String> {
    Ok(None)
}
