//! How every connection checks the server's certificate: the system's
//! own check, except on Android, where it needs the app to hand it Java's
//! context first; there Mozilla's list of authorities is used instead.

use tokio_rustls::rustls::ClientConfig;

/// Names the cryptography every TLS connection in the process uses
/// (aws-lc-rs), before the first one. Without it rustls refuses to pick
/// when another library also brings its `ring` (Velopack on Windows), and
/// every connection panics. Safe to call any number of times.
pub fn use_one_crypto_provider() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        let _ = tokio_rustls::rustls::crypto::aws_lc_rs::default_provider().install_default();
    });
}

#[cfg(not(target_os = "android"))]
pub fn client_config() -> Result<ClientConfig, String> {
    use rustls_platform_verifier::ConfigVerifierExt;
    use_one_crypto_provider();
    ClientConfig::with_platform_verifier().map_err(|e| e.to_string())
}

#[cfg(target_os = "android")]
pub fn client_config() -> Result<ClientConfig, String> {
    use_one_crypto_provider();
    let roots = tokio_rustls::rustls::RootCertStore {
        roots: webpki_roots::TLS_SERVER_ROOTS.to_vec(),
    };
    Ok(ClientConfig::builder()
        .with_root_certificates(roots)
        .with_no_client_auth())
}

/// A web client that checks certificates the same way.
pub fn http_client() -> reqwest::ClientBuilder {
    let builder = reqwest::Client::builder();
    match client_config() {
        Ok(config) => builder.tls_backend_preconfigured(config),
        Err(_) => builder,
    }
}

#[cfg(test)]
mod tests {
    // The tests build rustls with `ring` as well as aws-lc-rs (see the
    // dev-dependencies), as on Windows, where Velopack adds it.
    #[test]
    fn connections_work_with_two_crypto_libraries_built_in() {
        assert!(super::client_config().is_ok());
        assert!(super::http_client().build().is_ok());
    }
}
