//! Links from an email, as the browser will read them.

use flutter_rust_bridge::frb;

/// [host] in the ASCII form a browser goes to (UTS #46, then punycode),
/// or null when it isn't a host a browser would open. See
/// `piuma_core::reading::link_host_ascii`.
#[frb(sync)]
pub fn link_host_ascii(host: String) -> Option<String> {
    piuma_core::reading::link_host_ascii(&host)
}
