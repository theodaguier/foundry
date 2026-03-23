use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::path::PathBuf;
use std::sync::{Mutex, LazyLock};

static SUPABASE_URL_DEFAULT: &str = "https://bpqqfpdaigphewgobmpe.supabase.co";
static SUPABASE_ANON_KEY_DEFAULT: &str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJwcXFmcGRhaWdwaGV3Z29ibXBlIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQwODc3NTYsImV4cCI6MjA4OTY2Mzc1Nn0.YKFmmJk39st-P68Dvztn9YHSCteXWGAvMNyM3hNofy4";

pub static SUPABASE_URL: LazyLock<String> = LazyLock::new(|| {
    std::env::var("SUPABASE_URL").unwrap_or_else(|_| SUPABASE_URL_DEFAULT.to_string())
});

pub static SUPABASE_ANON_KEY: LazyLock<String> = LazyLock::new(|| {
    std::env::var("SUPABASE_ANON_KEY").unwrap_or_else(|_| SUPABASE_ANON_KEY_DEFAULT.to_string())
});

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AuthSession {
    pub access_token: String,
    pub refresh_token: String,
    pub user_id: String,
    pub email: String,
}

#[derive(Debug, Deserialize)]
struct SupabaseAuthResponse {
    access_token: Option<String>,
    refresh_token: Option<String>,
    user: Option<SupabaseUser>,
}

#[derive(Debug, Deserialize)]
struct SupabaseUser {
    id: String,
    email: Option<String>,
}

#[derive(Debug, Deserialize)]
struct SupabaseErrorResponse {
    #[serde(default)]
    msg: Option<String>,
    #[serde(default)]
    error_description: Option<String>,
    #[serde(default)]
    message: Option<String>,
}

pub struct SupabaseAuth {
    client: Client,
    session: Mutex<Option<AuthSession>>,
}

impl SupabaseAuth {
    pub fn new() -> Self {
        let client = Client::new();
        let auth = Self {
            client,
            session: Mutex::new(None),
        };
        // Try to load persisted session on creation
        if let Ok(session) = Self::load_session_from_disk() {
            *auth.session.lock().unwrap() = Some(session);
        }
        auth
    }

    fn session_file_path() -> PathBuf {
        let mut path = dirs::home_dir().unwrap_or_default();
        path.push("Library/Application Support/Foundry");
        path.push("auth_session.json");
        path
    }

    fn persist_session(session: &AuthSession) -> Result<(), String> {
        let path = Self::session_file_path();
        if let Some(parent) = path.parent() {
            std::fs::create_dir_all(parent).map_err(|e| format!("Failed to create dir: {}", e))?;
        }
        let json = serde_json::to_string_pretty(session)
            .map_err(|e| format!("Failed to serialize session: {}", e))?;
        std::fs::write(&path, json).map_err(|e| format!("Failed to write session: {}", e))?;
        Ok(())
    }

    fn load_session_from_disk() -> Result<AuthSession, String> {
        let path = Self::session_file_path();
        let data =
            std::fs::read_to_string(&path).map_err(|e| format!("Failed to read session: {}", e))?;
        let session: AuthSession =
            serde_json::from_str(&data).map_err(|e| format!("Failed to parse session: {}", e))?;
        Ok(session)
    }

    fn clear_session_file() {
        let path = Self::session_file_path();
        let _ = std::fs::remove_file(&path);
    }

    fn extract_error(body: &str) -> String {
        if let Ok(err) = serde_json::from_str::<SupabaseErrorResponse>(body) {
            if let Some(msg) = err.msg {
                return msg;
            }
            if let Some(msg) = err.error_description {
                return msg;
            }
            if let Some(msg) = err.message {
                return msg;
            }
        }
        body.to_string()
    }

    /// Get the current session (if any).
    pub fn get_session(&self) -> Option<AuthSession> {
        self.session.lock().unwrap().clone()
    }

    pub async fn sign_up(&self, email: &str, password: &str) -> Result<(), String> {
        let url = format!("{}/auth/v1/signup", *SUPABASE_URL);
        let body = serde_json::json!({
            "email": email,
            "password": password,
        });

        let resp = self
            .client
            .post(&url)
            .header("apikey", SUPABASE_ANON_KEY.as_str())
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| format!("Failed to read response: {}", e))?;

        if !status.is_success() {
            return Err(Self::extract_error(&text));
        }

        // If the response contains a session (email confirmation disabled), store it
        if let Ok(auth_resp) = serde_json::from_str::<SupabaseAuthResponse>(&text) {
            if let (Some(access_token), Some(refresh_token), Some(user)) = (
                auth_resp.access_token,
                auth_resp.refresh_token,
                auth_resp.user,
            ) {
                let session = AuthSession {
                    access_token,
                    refresh_token,
                    user_id: user.id,
                    email: user.email.unwrap_or_else(|| email.to_string()),
                };
                Self::persist_session(&session)?;
                *self.session.lock().unwrap() = Some(session);
            }
        }

        Ok(())
    }

    pub async fn send_otp(&self, email: &str) -> Result<(), String> {
        let url = format!("{}/auth/v1/otp", *SUPABASE_URL);
        let body = serde_json::json!({
            "email": email,
        });

        let resp = self
            .client
            .post(&url)
            .header("apikey", SUPABASE_ANON_KEY.as_str())
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        let status = resp.status();
        if !status.is_success() {
            let text = resp
                .text()
                .await
                .map_err(|e| format!("Failed to read response: {}", e))?;
            return Err(Self::extract_error(&text));
        }

        Ok(())
    }

    pub async fn verify_otp(&self, email: &str, code: &str, is_signup: bool) -> Result<(), String> {
        let url = format!("{}/auth/v1/verify", *SUPABASE_URL);
        let otp_type = if is_signup { "signup" } else { "email" };
        let body = serde_json::json!({
            "email": email,
            "token": code,
            "type": otp_type,
        });

        let resp = self
            .client
            .post(&url)
            .header("apikey", SUPABASE_ANON_KEY.as_str())
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| format!("Failed to read response: {}", e))?;

        if !status.is_success() {
            return Err(Self::extract_error(&text));
        }

        let auth_resp: SupabaseAuthResponse = serde_json::from_str(&text)
            .map_err(|e| format!("Failed to parse auth response: {}", e))?;

        let access_token = auth_resp
            .access_token
            .ok_or_else(|| "No access token in response".to_string())?;
        let refresh_token = auth_resp
            .refresh_token
            .ok_or_else(|| "No refresh token in response".to_string())?;
        let user = auth_resp
            .user
            .ok_or_else(|| "No user in response".to_string())?;

        let session = AuthSession {
            access_token,
            refresh_token,
            user_id: user.id,
            email: user.email.unwrap_or_else(|| email.to_string()),
        };

        Self::persist_session(&session)?;
        *self.session.lock().unwrap() = Some(session);

        Ok(())
    }

    pub async fn sign_out(&self) -> Result<(), String> {
        let session = self.session.lock().unwrap().clone();
        if let Some(session) = session {
            let url = format!("{}/auth/v1/logout", *SUPABASE_URL);
            // Best-effort sign out on server
            let _ = self
                .client
                .post(&url)
                .header("apikey", SUPABASE_ANON_KEY.as_str())
                .header("Authorization", format!("Bearer {}", session.access_token))
                .send()
                .await;
        }

        *self.session.lock().unwrap() = None;
        Self::clear_session_file();
        Ok(())
    }

    pub async fn check_session(&self) -> Result<Option<String>, String> {
        let stored = self.session.lock().unwrap().clone();
        let session = match stored {
            Some(s) => s,
            None => return Ok(None),
        };

        // Try to refresh the token to validate the session
        let url = format!("{}/auth/v1/token?grant_type=refresh_token", *SUPABASE_URL);
        let body = serde_json::json!({
            "refresh_token": session.refresh_token,
        });

        let resp = self
            .client
            .post(&url)
            .header("apikey", SUPABASE_ANON_KEY.as_str())
            .header("Content-Type", "application/json")
            .json(&body)
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| format!("Failed to read response: {}", e))?;

        if !status.is_success() {
            // Session is invalid, clear it
            *self.session.lock().unwrap() = None;
            Self::clear_session_file();
            return Ok(None);
        }

        let auth_resp: SupabaseAuthResponse = serde_json::from_str(&text)
            .map_err(|e| format!("Failed to parse refresh response: {}", e))?;

        if let (Some(access_token), Some(refresh_token), Some(user)) = (
            auth_resp.access_token,
            auth_resp.refresh_token,
            auth_resp.user,
        ) {
            let new_session = AuthSession {
                access_token,
                refresh_token,
                user_id: user.id.clone(),
                email: user.email.unwrap_or(session.email),
            };
            Self::persist_session(&new_session)?;
            *self.session.lock().unwrap() = Some(new_session);
            Ok(Some(user.id))
        } else {
            *self.session.lock().unwrap() = None;
            Self::clear_session_file();
            Ok(None)
        }
    }

    pub async fn get_profile(&self, user_id: &str) -> Result<Option<serde_json::Value>, String> {
        let session = self.session.lock().unwrap().clone();
        let session = match session {
            Some(s) => s,
            None => return Err("Not authenticated".to_string()),
        };

        let url = format!(
            "{}/rest/v1/profiles?id=eq.{}&select=*",
            *SUPABASE_URL, user_id
        );

        let resp = self
            .client
            .get(&url)
            .header("apikey", SUPABASE_ANON_KEY.as_str())
            .header("Authorization", format!("Bearer {}", session.access_token))
            .header("Content-Type", "application/json")
            .send()
            .await
            .map_err(|e| format!("Request failed: {}", e))?;

        let status = resp.status();
        let text = resp
            .text()
            .await
            .map_err(|e| format!("Failed to read response: {}", e))?;

        if !status.is_success() {
            return Err(Self::extract_error(&text));
        }

        let profiles: Vec<serde_json::Value> =
            serde_json::from_str(&text).map_err(|e| format!("Failed to parse profiles: {}", e))?;

        Ok(profiles.into_iter().next())
    }
}
