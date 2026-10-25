//! Bridge between the engine (`piuma-core`) and the Flutter app.

#[cfg(target_os = "android")]
mod android;
pub mod api;
pub mod background;
mod credentials;
mod frb_generated;
