use std::sync::Mutex;
use crate::models::plugin::Plugin;

pub struct AppState {
    pub plugins: Mutex<Vec<Plugin>>,
    pub build_cancel_token: Mutex<Option<tokio::sync::oneshot::Sender<()>>>,
}

impl AppState {
    pub fn new() -> Self {
        Self {
            plugins: Mutex::new(Vec::new()),
            build_cancel_token: Mutex::new(None),
        }
    }
}
