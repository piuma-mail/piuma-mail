//! Reading a domain's autoconfig file over HTTP, from a server inside the test.

use piuma_core::autoconfig::{from_url, Source};
use piuma_core::Security;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::TcpListener;

const XML: &str = r#"<clientConfig version="1.1"><emailProvider id="studio.it">
<incomingServer type="imap"><hostname>imap.studio.it</hostname><port>993</port>
<socketType>SSL</socketType><username>%EMAILADDRESS%</username></incomingServer>
<outgoingServer type="smtp"><hostname>smtp.studio.it</hostname><port>465</port>
<socketType>SSL</socketType><username>%EMAILADDRESS%</username></outgoingServer>
</emailProvider></clientConfig>"#;

/// Answers every request with `status` and `body`.
async fn http_server(status: &'static str, body: &'static str) -> u16 {
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    tokio::spawn(async move {
        while let Ok((mut tcp, _)) = listener.accept().await {
            let mut buf = [0u8; 4096];
            let _ = tcp.read(&mut buf).await;
            let reply = format!(
                "HTTP/1.1 {status}\r\nContent-Type: text/xml\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                body.len()
            );
            let _ = tcp.write_all(reply.as_bytes()).await;
        }
    });
    port
}

#[tokio::test]
async fn reads_a_published_config() {
    let port = http_server("200 OK", XML).await;
    let s = from_url(
        &format!("http://127.0.0.1:{port}/mail/config-v1.1.xml"),
        "matteo@studio.it",
    )
    .await
    .unwrap();
    assert_eq!(s.source, Source::Published);
    assert_eq!(s.imap.host, "imap.studio.it");
    assert_eq!(s.smtp.security, Security::Tls);
    assert_eq!(s.username, "matteo@studio.it");
}

#[tokio::test]
async fn a_missing_file_finds_nothing() {
    let port = http_server("404 Not Found", "").await;
    let url = format!("http://127.0.0.1:{port}/mail/config-v1.1.xml");
    assert_eq!(from_url(&url, "matteo@studio.it").await, None);
}
