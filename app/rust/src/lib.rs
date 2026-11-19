//! Bridge between the engine (`piuma-core`) and the Flutter app.

// `EngineError::new` writes to the recent log a report carries: built
// eagerly (`ok_or(EngineError::new(..))`) it logs even when nothing went
// wrong ("Other: unknown account" at every message opened).
#![deny(clippy::or_fun_call)]

#[cfg(target_os = "android")]
mod android;
pub mod api;
pub mod background;
mod clipboard;
mod credentials;
mod frb_generated;
mod login;
pub mod watch;
