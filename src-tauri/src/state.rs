use crate::models::plugin::Plugin;
use crate::services::auth_service::SupabaseAuth;
use std::sync::Mutex;

pub struct AppState {
    pub plugins: Mutex<Vec<Plugin>>,
    pub build_cancel_token: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
    pub auth: SupabaseAuth,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            plugins: Mutex::new(Vec::new()),
            build_cancel_token: Mutex::new(None),
            auth: SupabaseAuth::new(),
        }
    }
}
