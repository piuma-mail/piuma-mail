//! The away message against a small ManageSieve server (RFC 5804) inside
//! the test: just enough to answer what the engine asks, with literals
//! the way real servers send them.

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex};

use piuma_core::away::{self, AwayMessage, AwayServer, Outcome, SCRIPT};
use piuma_core::sieve::{self, SieveConfig, SieveError};
use piuma_core::Security;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

const USER: &str = "matteo";
const PASSWORD: &str = "secret";

#[derive(Default)]
struct Server {
    scripts: BTreeMap<String, String>,
    active: Option<String>,
    /// Sieve extensions offered.
    extensions: String,
    /// Every command, in order, without its literal.
    log: Vec<String>,
}

async fn start(extensions: &str) -> (Arc<Mutex<Server>>, SieveConfig) {
    let state = Arc::new(Mutex::new(Server {
        extensions: extensions.into(),
        ..Server::default()
    }));
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let shared = state.clone();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            tokio::spawn(serve(shared.clone(), tcp));
        }
    });
    let cfg = SieveConfig {
        host: "127.0.0.1".into(),
        port,
        security: Security::None,
        username: USER.into(),
        password: PASSWORD.into(),
    };
    (state, cfg)
}

/// Reads a command line, and the literal it ends with, if any.
async fn command(tcp: &mut TcpStream, buf: &mut Vec<u8>) -> Option<(String, Option<String>)> {
    let mut chunk = [0u8; 4096];
    loop {
        if let Some(i) = buf.windows(2).position(|w| w == b"\r\n") {
            let line = String::from_utf8_lossy(&buf[..i]).to_string();
            if let Some(open) = line.rfind('{').filter(|_| line.ends_with("+}")) {
                let n: usize = line[open + 1..line.len() - 2].parse().unwrap();
                while buf.len() < i + 2 + n + 2 {
                    let got = tcp.read(&mut chunk).await.ok()?;
                    if got == 0 {
                        return None;
                    }
                    buf.extend_from_slice(&chunk[..got]);
                }
                let literal = String::from_utf8_lossy(&buf[i + 2..i + 2 + n]).to_string();
                buf.drain(..i + 2 + n + 2);
                return Some((line[..open].trim().to_owned(), Some(literal)));
            }
            buf.drain(..i + 2);
            return Some((line, None));
        }
        let got = tcp.read(&mut chunk).await.ok()?;
        if got == 0 {
            return None;
        }
        buf.extend_from_slice(&chunk[..got]);
    }
}

/// The quoted arguments of a command line.
fn args(line: &str) -> Vec<String> {
    let mut out = Vec::new();
    let mut chars = line.chars();
    while let Some(c) = chars.next() {
        if c != '"' {
            continue;
        }
        let mut s = String::new();
        while let Some(c) = chars.next() {
            match c {
                '\\' => s.push(chars.next().unwrap()),
                '"' => break,
                c => s.push(c),
            }
        }
        out.push(s);
    }
    out
}

async fn serve(state: Arc<Mutex<Server>>, mut tcp: TcpStream) {
    let caps = {
        let s = state.lock().unwrap();
        format!(
            "\"IMPLEMENTATION\" \"Fake Sieve\"\r\n\"SIEVE\" \"{}\"\r\n\"SASL\" \"PLAIN\"\r\n\"VERSION\" \"1.0\"\r\nOK \"ready\"\r\n",
            s.extensions
        )
    };
    tcp.write_all(caps.as_bytes()).await.unwrap();
    let mut buf = Vec::new();
    let mut authed = false;
    while let Some((line, literal)) = command(&mut tcp, &mut buf).await {
        let verb = line.split(' ').next().unwrap().to_ascii_uppercase();
        let a = args(&line);
        let reply = {
            let mut s = state.lock().unwrap();
            s.log.push(line.clone());
            match verb.as_str() {
                "AUTHENTICATE" => {
                    use base64::Engine;
                    let pair = base64::engine::general_purpose::STANDARD
                        .decode(&a[1])
                        .unwrap();
                    if pair == format!("\0{USER}\0{PASSWORD}").as_bytes() {
                        authed = true;
                        "OK \"logged in\"\r\n".to_owned()
                    } else {
                        "NO \"wrong password\"\r\n".to_owned()
                    }
                }
                "LOGOUT" => "OK \"bye\"\r\n".to_owned(),
                _ if !authed => "NO \"log in first\"\r\n".to_owned(),
                "LISTSCRIPTS" => {
                    let mut out = String::new();
                    for name in s.scripts.keys() {
                        let active = s.active.as_deref() == Some(name.as_str());
                        // One name as a literal, as servers may send them.
                        if name.contains(' ') {
                            out.push_str(&format!("{{{}}}\r\n{name}", name.len()));
                        } else {
                            out.push_str(&format!("\"{name}\""));
                        }
                        out.push_str(if active { " ACTIVE\r\n" } else { "\r\n" });
                    }
                    out + "OK\r\n"
                }
                "GETSCRIPT" => match s.scripts.get(&a[0]) {
                    Some(text) => format!("{{{}}}\r\n{text}\r\nOK\r\n", text.len()),
                    None => "NO (NONEXISTENT) \"no such script\"\r\n".to_owned(),
                },
                "PUTSCRIPT" => {
                    let text = literal.unwrap();
                    if text.contains("vacation") && !s.extensions.contains("vacation") {
                        "NO \"unknown extension vacation\"\r\n".to_owned()
                    } else {
                        s.scripts.insert(a[0].clone(), text);
                        "OK\r\n".to_owned()
                    }
                }
                "SETACTIVE" => {
                    if a[0].is_empty() {
                        s.active = None;
                        "OK\r\n".to_owned()
                    } else if s.scripts.contains_key(&a[0]) {
                        s.active = Some(a[0].clone());
                        "OK\r\n".to_owned()
                    } else {
                        "NO (NONEXISTENT) \"no such script\"\r\n".to_owned()
                    }
                }
                "DELETESCRIPT" => {
                    if s.active.as_deref() == Some(a[0].as_str()) {
                        "NO (ACTIVE) \"active\"\r\n".to_owned()
                    } else if s.scripts.remove(&a[0]).is_some() {
                        "OK\r\n".to_owned()
                    } else {
                        "NO (NONEXISTENT) \"no such script\"\r\n".to_owned()
                    }
                }
                _ => "NO \"unknown command\"\r\n".to_owned(),
            }
        };
        tcp.write_all(reply.as_bytes()).await.unwrap();
        if verb == "LOGOUT" {
            return;
        }
    }
}

fn day(s: &str) -> i64 {
    away::parse_iso(s).unwrap()
}

fn message() -> AwayMessage {
    AwayMessage {
        on: true,
        start: Some(day("2026-10-27")),
        end: Some(day("2026-11-02")),
        subject: "Away until 3 November".into(),
        body: "Hi, I'm away until Monday 3 November.\nMatteo".into(),
    }
}

fn addresses() -> Vec<String> {
    vec!["matteo@studio.it".into(), "m@studio.it".into()]
}

#[tokio::test]
async fn logs_in_and_lists_scripts() {
    let (state, cfg) = start("fileinto vacation date relational").await;
    state
        .lock()
        .unwrap()
        .scripts
        .insert("my filters".into(), "keep;".into());
    let mut c = sieve::Client::open(&cfg).await.unwrap();
    assert!(c.capabilities().has("vacation"));
    assert!(c.capabilities().dates());
    assert_eq!(c.capabilities().implementation, "Fake Sieve");
    let scripts = c.list().await.unwrap();
    assert_eq!(scripts.len(), 1);
    assert_eq!(scripts[0].name, "my filters");
    assert!(!scripts[0].active);
    assert_eq!(c.get("my filters").await.unwrap().as_deref(), Some("keep;"));
    assert_eq!(c.get("nothing").await.unwrap(), None);
    c.logout().await;

    let wrong = SieveConfig {
        password: "nope".into(),
        ..cfg
    };
    assert!(matches!(
        sieve::Client::open(&wrong).await,
        Err(SieveError::Auth)
    ));
}

#[tokio::test]
async fn turns_on_and_off_with_dates_on_the_server() {
    let (state, cfg) = start("fileinto vacation date relational").await;
    let server = AwayServer::Sieve(cfg);
    let today = day("2026-10-21");

    let status = away::status(&server, 60).await.unwrap().unwrap();
    assert!(status.dates);
    assert_eq!(status.message, None);
    assert!(!status.placed);

    // A first day still to come is the server's to keep.
    let (outcome, dates) = away::apply(&server, &message(), &addresses(), 60, today)
        .await
        .unwrap();
    assert_eq!(outcome, Outcome::Placed);
    assert!(dates);
    {
        let s = state.lock().unwrap();
        assert_eq!(s.active.as_deref(), Some(SCRIPT));
        let script = &s.scripts[SCRIPT];
        assert!(script.contains("vacation :days 7"));
        assert!(script.contains(":addresses [\"matteo@studio.it\", \"m@studio.it\"]"));
        assert!(script.contains("\"ge\" \"date\" \"2026-10-27\""));
    }

    let status = away::status(&server, 60).await.unwrap().unwrap();
    assert_eq!(status.message, Some(message()));
    assert!(status.placed);

    // Changing it replaces it in place, still active.
    let mut changed = message();
    changed.body = "Back on Tuesday.".into();
    away::apply(&server, &changed, &addresses(), 60, today)
        .await
        .unwrap();
    assert!(state.lock().unwrap().scripts[SCRIPT].contains("Back on Tuesday."));
    assert_eq!(
        state
            .lock()
            .unwrap()
            .log
            .iter()
            .filter(|l| l.starts_with("SETACTIVE"))
            .count(),
        1
    );

    let off = AwayMessage {
        on: false,
        ..changed
    };
    let (outcome, _) = away::apply(&server, &off, &addresses(), 60, today)
        .await
        .unwrap();
    assert_eq!(outcome, Outcome::Removed);
    let s = state.lock().unwrap();
    assert!(s.scripts.is_empty());
    assert_eq!(s.active, None);
}

#[tokio::test]
async fn never_touches_the_persons_own_filters() {
    let (state, cfg) = start("fileinto vacation date relational").await;
    {
        let mut s = state.lock().unwrap();
        s.scripts
            .insert("roundcube".into(), "require \"fileinto\";".into());
        s.active = Some("roundcube".into());
    }
    let server = AwayServer::Sieve(cfg);
    let status = away::status(&server, 0).await.unwrap().unwrap();
    assert!(status.other_filters);

    let (outcome, _) = away::apply(&server, &message(), &addresses(), 0, day("2026-10-28"))
        .await
        .unwrap();
    assert_eq!(outcome, Outcome::OtherFilters);
    {
        let s = state.lock().unwrap();
        assert_eq!(s.active.as_deref(), Some("roundcube"));
        assert_eq!(s.scripts.len(), 1);
        assert!(!s.log.iter().any(|l| l.starts_with("PUTSCRIPT")
            || l.starts_with("SETACTIVE")
            || l.starts_with("DELETESCRIPT")));
    }

    // Turning off with only their filters there leaves them be.
    let off = AwayMessage {
        on: false,
        ..message()
    };
    away::apply(&server, &off, &addresses(), 0, day("2026-10-28"))
        .await
        .unwrap();
    let s = state.lock().unwrap();
    assert_eq!(s.active.as_deref(), Some("roundcube"));
    assert_eq!(s.scripts.len(), 1);
}

#[tokio::test]
async fn an_inactive_script_of_theirs_stays_too() {
    let (state, cfg) = start("vacation").await;
    state
        .lock()
        .unwrap()
        .scripts
        .insert("old one".into(), "keep;".into());
    let server = AwayServer::Sieve(cfg);
    let (outcome, _) = away::apply(&server, &message(), &addresses(), 0, day("2026-10-28"))
        .await
        .unwrap();
    assert_eq!(outcome, Outcome::Placed);
    let off = AwayMessage {
        on: false,
        ..message()
    };
    away::apply(&server, &off, &addresses(), 0, day("2026-10-29"))
        .await
        .unwrap();
    let s = state.lock().unwrap();
    assert_eq!(s.scripts.keys().collect::<Vec<_>>(), ["old one"]);
    assert_eq!(s.active, None);
}

#[tokio::test]
async fn without_dates_the_device_waits_for_the_first_day() {
    let (state, cfg) = start("fileinto vacation").await;
    let server = AwayServer::Sieve(cfg);

    let (outcome, dates) = away::apply(&server, &message(), &addresses(), 0, day("2026-10-21"))
        .await
        .unwrap();
    assert_eq!(outcome, Outcome::Waiting);
    assert!(!dates);
    assert!(state.lock().unwrap().scripts.is_empty());

    let (outcome, _) = away::apply(&server, &message(), &addresses(), 0, day("2026-10-27"))
        .await
        .unwrap();
    assert_eq!(outcome, Outcome::Placed);
    let script = state.lock().unwrap().scripts[SCRIPT].clone();
    assert!(script.contains("require [\"vacation\"];"));
    assert!(!script.contains("currentdate"));
}

#[tokio::test]
async fn a_server_without_vacation_or_sieve_has_no_away_message() {
    let (_, cfg) = start("fileinto").await;
    let server = AwayServer::Sieve(cfg.clone());
    assert_eq!(away::status(&server, 0).await.unwrap(), None);
    let (outcome, _) = away::apply(&server, &message(), &addresses(), 0, day("2026-10-28"))
        .await
        .unwrap();
    assert_eq!(outcome, Outcome::Unsupported);

    // Nothing listening on the port: simply not there.
    let closed = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = closed.local_addr().unwrap().port();
    drop(closed);
    let nowhere = AwayServer::Sieve(SieveConfig { port, ..cfg });
    assert_eq!(away::status(&nowhere, 0).await.unwrap(), None);
}
