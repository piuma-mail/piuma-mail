//! Calendars the person already uses, reached over CalDAV or as a
//! read-only .ics feed. Piuma has no calendar of its own: it reads when
//! you are busy, to show it on invites, and puts the invites you accept
//! in the calendar you chose. Events stay on their server.

use std::time::Duration;

use reqwest::{Method, StatusCode};
use roxmltree::{Document, Node};
use url::Url;

use crate::invite::{self, Invite};

const DAV: &str = "DAV:";
const CALDAV: &str = "urn:ietf:params:xml:ns:caldav";
const APPLE: &str = "http://apple.com/ns/ical/";

#[derive(Debug, thiserror::Error)]
pub enum CalendarError {
    #[error("wrong user name or password")]
    WrongPassword,
    #[error("no calendar server found for {0}")]
    NotFound(String),
    #[error("can't reach {url}: {detail}")]
    Connect { url: String, detail: String },
    #[error("the server answered {status} for {url}")]
    Status { url: String, status: u16 },
    #[error("unexpected answer: {0}")]
    Protocol(String),
}

pub type Result<T> = std::result::Result<T, CalendarError>;

/// A calendar the server offers.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RemoteCalendar {
    /// Its address on the server.
    pub url: String,
    pub name: String,
    /// "#RRGGBB" when the server keeps one.
    pub color: Option<String>,
    /// You may read it but not add events to it.
    pub read_only: bool,
}

/// What signing in to a CalDAV server found.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Found {
    /// Where the calendars live, to look again later.
    pub home: String,
    pub calendars: Vec<RemoteCalendar>,
}

/// Signs in to a CalDAV account.
pub struct CalDav {
    http: reqwest::Client,
    authorization: String,
}

/// Where to start looking for an address: a URL as it is, the servers
/// big providers use, then the domain's well-known address.
pub fn starts(address: &str) -> Vec<String> {
    let address = address.trim();
    if address.starts_with("https://") || address.starts_with("http://") {
        return vec![address.to_owned()];
    }
    let domain = address
        .rsplit_once('@')
        .map_or(address, |(_, d)| d)
        .trim_end_matches('/')
        .to_ascii_lowercase();
    match domain.as_str() {
        "icloud.com" | "me.com" | "mac.com" => vec!["https://caldav.icloud.com/".into()],
        "fastmail.com" | "fastmail.fm" | "messagingengine.com" => {
            vec!["https://caldav.fastmail.com/".into()]
        }
        "" => vec![],
        _ => vec![
            format!("https://{domain}/.well-known/caldav"),
            format!("https://caldav.{domain}/.well-known/caldav"),
            format!("https://caldav.{domain}/"),
        ],
    }
}

/// True when an email address belongs to a provider known to give a
/// calendar with the same password.
pub fn offers_calendar(email: &str) -> bool {
    let domain = email
        .rsplit_once('@')
        .map_or("", |(_, d)| d)
        .to_ascii_lowercase();
    matches!(
        domain.as_str(),
        "icloud.com" | "me.com" | "mac.com" | "fastmail.com" | "fastmail.fm"
    )
}

impl CalDav {
    pub fn new(username: &str, password: &str) -> Result<Self> {
        use base64::Engine;
        let http = crate::tls::http_client()
            .timeout(Duration::from_secs(30))
            // Redirects are followed here, keeping PROPFIND a PROPFIND.
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .map_err(|e| CalendarError::Protocol(e.to_string()))?;
        let pair = format!("{username}:{password}");
        Ok(Self {
            http,
            authorization: format!(
                "Basic {}",
                base64::engine::general_purpose::STANDARD.encode(pair)
            ),
        })
    }

    /// Finds the calendars of an address: an email address or a server.
    pub async fn discover(&self, address: &str) -> Result<Found> {
        let mut last = CalendarError::NotFound(address.trim().to_owned());
        for start in starts(address) {
            match self.discover_from(&start).await {
                Ok(found) => return Ok(found),
                Err(CalendarError::WrongPassword) => return Err(CalendarError::WrongPassword),
                Err(e) => last = e,
            }
        }
        Err(last)
    }

    async fn discover_from(&self, start: &str) -> Result<Found> {
        let (at, body) = self
            .dav(
                "PROPFIND",
                start,
                "0",
                r#"<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><d:current-user-principal/><c:calendar-home-set/></d:prop></d:propfind>"#,
            )
            .await?;
        let doc = parse(&body)?;
        let mut home = href_in(&doc, CALDAV, "calendar-home-set").map(|h| join(&at, &h));
        if home.is_none() {
            let principal = href_in(&doc, DAV, "current-user-principal")
                .map(|h| join(&at, &h))
                .unwrap_or_else(|| at.clone());
            let (at, body) = self
                .dav(
                    "PROPFIND",
                    &principal,
                    "0",
                    r#"<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-home-set/></d:prop></d:propfind>"#,
                )
                .await?;
            home = href_in(&parse(&body)?, CALDAV, "calendar-home-set").map(|h| join(&at, &h));
        }
        let home = home.ok_or_else(|| CalendarError::NotFound(start.to_owned()))?;
        let calendars = self.calendars(&home).await?;
        Ok(Found { home, calendars })
    }

    /// The calendars in a calendar home, those that hold events.
    pub async fn calendars(&self, home: &str) -> Result<Vec<RemoteCalendar>> {
        let (at, body) = self
            .dav(
                "PROPFIND",
                home,
                "1",
                r#"<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:a="http://apple.com/ns/ical/"><d:prop><d:resourcetype/><d:displayname/><a:calendar-color/><d:current-user-privilege-set/><c:supported-calendar-component-set/></d:prop></d:propfind>"#,
            )
            .await?;
        let doc = parse(&body)?;
        let mut out = Vec::new();
        for response in children(doc.root_element(), DAV, "response") {
            let Some(href) = child(response, DAV, "href").and_then(|h| h.text()) else {
                continue;
            };
            let Some(prop) = ok_prop(response) else {
                continue;
            };
            let is_calendar = child(prop, DAV, "resourcetype")
                .is_some_and(|t| child(t, CALDAV, "calendar").is_some());
            if !is_calendar {
                continue;
            }
            let components: Vec<String> = child(prop, CALDAV, "supported-calendar-component-set")
                .map(|set| {
                    children(set, CALDAV, "comp")
                        .filter_map(|c| c.attribute("name"))
                        .map(str::to_ascii_uppercase)
                        .collect()
                })
                .unwrap_or_default();
            if !components.is_empty() && !components.iter().any(|c| c == "VEVENT") {
                continue;
            }
            let read_only = child(prop, DAV, "current-user-privilege-set").is_some_and(|set| {
                !set.descendants().any(|n| {
                    n.tag_name().namespace() == Some(DAV)
                        && matches!(n.tag_name().name(), "write" | "write-content" | "all")
                })
            });
            let color = child(prop, APPLE, "calendar-color")
                .and_then(|c| c.text())
                .map(str::trim)
                .filter(|c| c.starts_with('#') && c.len() >= 7)
                .map(|c| c[..7].to_ascii_uppercase());
            let url = join(&at, href.trim());
            let name = child(prop, DAV, "displayname")
                .and_then(|n| n.text())
                .map(str::trim)
                .filter(|n| !n.is_empty())
                .map(str::to_owned)
                .unwrap_or_else(|| last_segment(&url));
            out.push(RemoteCalendar {
                url,
                name,
                color,
                read_only,
            });
        }
        Ok(out)
    }

    /// The events of a calendar between two times (Unix seconds), with
    /// repeating ones expanded by the server.
    pub async fn events(&self, calendar: &str, from: i64, to: i64) -> Result<Vec<Invite>> {
        let (from, to) = (utc(from), utc(to));
        let query = format!(
            r#"<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop><c:calendar-data><c:expand start="{from}" end="{to}"/></c:calendar-data></d:prop><c:filter><c:comp-filter name="VCALENDAR"><c:comp-filter name="VEVENT"><c:time-range start="{from}" end="{to}"/></c:comp-filter></c:comp-filter></c:filter></c:calendar-query>"#
        );
        let (_, body) = self.dav("REPORT", calendar, "1", &query).await?;
        let doc = parse(&body)?;
        Ok(doc
            .descendants()
            .filter(|n| {
                n.tag_name().namespace() == Some(CALDAV) && n.tag_name().name() == "calendar-data"
            })
            .filter_map(|n| n.text())
            .flat_map(invite::events)
            .collect())
    }

    /// Puts an event in a calendar, unless one with its UID is there.
    pub async fn add(&self, calendar: &str, uid: &str, ics: &str) -> Result<()> {
        let name: String = uid
            .chars()
            .map(|c| {
                if c.is_ascii_alphanumeric() || "-_.".contains(c) {
                    c
                } else {
                    '-'
                }
            })
            .collect();
        let url = join(&ensure_slash(calendar), &format!("{name}.ics"));
        let response = self
            .http
            .put(&url)
            .header(reqwest::header::AUTHORIZATION, &self.authorization)
            .header(
                reqwest::header::CONTENT_TYPE,
                "text/calendar; charset=utf-8",
            )
            .header(reqwest::header::IF_NONE_MATCH, "*")
            .body(ics.to_owned())
            .send()
            .await
            .map_err(|e| connect(&url, e))?;
        match response.status() {
            s if s.is_success() => Ok(()),
            // Already there: the organizer's server may have put it.
            StatusCode::PRECONDITION_FAILED => Ok(()),
            StatusCode::UNAUTHORIZED => Err(CalendarError::WrongPassword),
            s => Err(CalendarError::Status {
                url,
                status: s.as_u16(),
            }),
        }
    }

    /// A WebDAV request, following redirects with the same method. Gives
    /// the address that answered and the body.
    async fn dav(
        &self,
        method: &str,
        url: &str,
        depth: &str,
        body: &str,
    ) -> Result<(String, String)> {
        let method = Method::from_bytes(method.as_bytes())
            .map_err(|e| CalendarError::Protocol(e.to_string()))?;
        let origin = Url::parse(url)
            .map_err(|e| CalendarError::Protocol(e.to_string()))?
            .origin();
        let mut send_authorization = true;
        let mut url = url.to_owned();
        for _ in 0..6 {
            let mut request = self
                .http
                .request(method.clone(), &url)
                .header("Depth", depth)
                .header(
                    reqwest::header::CONTENT_TYPE,
                    "application/xml; charset=utf-8",
                )
                .body(body.to_owned());
            if send_authorization {
                request = request.header(reqwest::header::AUTHORIZATION, &self.authorization);
            }
            let response = request.send().await.map_err(|e| connect(&url, e))?;
            let status = response.status();
            if status.is_redirection() {
                let Some(next) = response
                    .headers()
                    .get(reqwest::header::LOCATION)
                    .and_then(|l| l.to_str().ok())
                else {
                    break;
                };
                let next = response
                    .url()
                    .join(next)
                    .map_err(|e| CalendarError::Protocol(e.to_string()))?;
                // Never forward credentials across a change of scheme,
                // host or port, or restore them later in the chain.
                send_authorization &= next.origin() == origin;
                url = next.into();
                continue;
            }
            return match status {
                StatusCode::MULTI_STATUS | StatusCode::OK => {
                    let text = response.text().await.map_err(|e| connect(&url, e))?;
                    Ok((url, text))
                }
                StatusCode::UNAUTHORIZED | StatusCode::FORBIDDEN => {
                    Err(CalendarError::WrongPassword)
                }
                s => Err(CalendarError::Status {
                    url,
                    status: s.as_u16(),
                }),
            };
        }
        Err(CalendarError::Protocol(format!(
            "too many redirects from {url}"
        )))
    }
}

/// What an .ics feed holds.
#[derive(Debug, Clone)]
pub struct Feed {
    /// The name it gives itself, if any.
    pub name: Option<String>,
    pub events: Vec<Invite>,
    /// How often it asks to be read again, in seconds, if it says.
    pub refresh: Option<i64>,
}

/// Reads an .ics feed.
pub async fn feed(url: &str) -> Result<Feed> {
    let url = feed_url(url);
    let http = crate::tls::http_client()
        .timeout(Duration::from_secs(30))
        .build()
        .map_err(|e| CalendarError::Protocol(e.to_string()))?;
    let response = http.get(&url).send().await.map_err(|e| connect(&url, e))?;
    let status = response.status();
    if !status.is_success() {
        return Err(CalendarError::Status {
            url,
            status: status.as_u16(),
        });
    }
    let text = response.text().await.map_err(|e| connect(&url, e))?;
    if !text.contains("BEGIN:VCALENDAR") {
        return Err(CalendarError::Protocol("not an .ics calendar".into()));
    }
    Ok(Feed {
        name: invite::calendar_name(&text),
        events: invite::events(&text),
        refresh: invite::refresh_interval(&text),
    })
}

/// The host of an address, to name a server or a feed.
pub fn host(url: &str) -> Option<String> {
    Url::parse(url).ok()?.host_str().map(str::to_owned)
}

/// webcal:// is how calendar links are often shared: it is plain HTTPS.
pub fn feed_url(url: &str) -> String {
    let url = url.trim();
    match url.strip_prefix("webcal://") {
        Some(rest) => format!("https://{rest}"),
        None => url.to_owned(),
    }
}

fn connect(url: &str, e: reqwest::Error) -> CalendarError {
    CalendarError::Connect {
        url: url.to_owned(),
        detail: e.to_string(),
    }
}

fn parse(body: &str) -> Result<Document<'_>> {
    Document::parse(body).map_err(|e| CalendarError::Protocol(e.to_string()))
}

fn child<'a, 'i>(node: Node<'a, 'i>, ns: &str, name: &str) -> Option<Node<'a, 'i>> {
    node.children()
        .find(|n| n.tag_name().namespace() == Some(ns) && n.tag_name().name() == name)
}

fn children<'a, 'i: 'a>(
    node: Node<'a, 'i>,
    ns: &'a str,
    name: &'a str,
) -> impl Iterator<Item = Node<'a, 'i>> + 'a {
    node.children()
        .filter(move |n| n.tag_name().namespace() == Some(ns) && n.tag_name().name() == name)
}

/// The first href inside a property, wherever it is in the answer.
fn href_in(doc: &Document, ns: &str, property: &str) -> Option<String> {
    doc.descendants()
        .filter(|n| n.tag_name().namespace() == Some(ns) && n.tag_name().name() == property)
        .find_map(|p| child(p, DAV, "href").and_then(|h| h.text()))
        .map(|h| h.trim().to_owned())
        .filter(|h| !h.is_empty())
}

/// The prop of a response's "200 OK" propstat.
fn ok_prop<'a, 'i>(response: Node<'a, 'i>) -> Option<Node<'a, 'i>> {
    children(response, DAV, "propstat")
        .find(|p| {
            child(*p, DAV, "status")
                .and_then(|s| s.text())
                .is_none_or(|s| s.contains(" 200"))
        })
        .and_then(|p| child(p, DAV, "prop"))
}

fn join(base: &str, href: &str) -> String {
    match Url::parse(base).and_then(|b| b.join(href)) {
        Ok(u) => u.to_string(),
        Err(_) => href.to_owned(),
    }
}

fn ensure_slash(url: &str) -> String {
    if url.ends_with('/') {
        url.to_owned()
    } else {
        format!("{url}/")
    }
}

fn last_segment(url: &str) -> String {
    url.trim_end_matches('/')
        .rsplit('/')
        .next()
        .unwrap_or_default()
        .to_owned()
}

/// Unix seconds as a CalDAV UTC time.
fn utc(unix: i64) -> String {
    let (y, m, d) = invite::civil(unix.div_euclid(86_400));
    let s = unix.rem_euclid(86_400);
    format!(
        "{y:04}{m:02}{d:02}T{:02}{:02}{:02}Z",
        s / 3600,
        s / 60 % 60,
        s % 60
    )
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};
    use tokio::net::TcpListener;

    /// A CalDAV server that answers each request from a list, by method
    /// and path, and keeps what it was sent.
    async fn server(
        routes: Vec<(&'static str, &'static str, u16, String)>,
    ) -> (String, std::sync::Arc<std::sync::Mutex<Vec<String>>>) {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let seen = std::sync::Arc::new(std::sync::Mutex::new(Vec::new()));
        let kept = seen.clone();
        tokio::spawn(async move {
            loop {
                let Ok((mut socket, _)) = listener.accept().await else {
                    return;
                };
                let mut buf = Vec::new();
                let mut chunk = [0u8; 4096];
                // Read the head, then as much body as it announces.
                loop {
                    let n = socket.read(&mut chunk).await.unwrap_or(0);
                    if n == 0 {
                        break;
                    }
                    buf.extend_from_slice(&chunk[..n]);
                    let text = String::from_utf8_lossy(&buf);
                    if let Some(end) = text.find("\r\n\r\n") {
                        let length = text[..end]
                            .lines()
                            .find_map(|l| {
                                l.to_ascii_lowercase()
                                    .strip_prefix("content-length:")
                                    .map(|v| v.trim().parse::<usize>().unwrap_or(0))
                            })
                            .unwrap_or(0);
                        if buf.len() >= end + 4 + length {
                            break;
                        }
                    }
                }
                let request = String::from_utf8_lossy(&buf).to_string();
                let mut first = request.lines().next().unwrap_or("").split(' ');
                let (method, path) = (first.next().unwrap_or(""), first.next().unwrap_or(""));
                kept.lock().unwrap().push(request.clone());
                let (status, body) = routes
                    .iter()
                    .find(|(m, p, _, _)| *m == method && *p == path)
                    .map_or((404, String::new()), |(_, _, s, b)| (*s, b.clone()));
                let response = if status == 301 {
                    format!("HTTP/1.1 301 X\r\nLocation: {body}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                } else {
                    format!(
                        "HTTP/1.1 {status} X\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
                        body.len()
                    )
                };
                let _ = socket.write_all(response.as_bytes()).await;
            }
        });
        (base, seen)
    }

    #[tokio::test]
    async fn same_origin_redirects_keep_authorization_and_method() {
        let (base, seen) = server(vec![
            ("PROPFIND", "/start", 301, "/calendar".into()),
            ("PROPFIND", "/calendar", 207, "calendar".into()),
        ])
        .await;
        let dav = CalDav::new("user", "password").unwrap();
        let result = dav
            .dav("PROPFIND", &format!("{base}/start"), "1", "body")
            .await;
        assert_eq!(
            result.unwrap(),
            (format!("{base}/calendar"), "calendar".into())
        );
        let requests = seen.lock().unwrap();
        assert_eq!(requests.len(), 2);
        for request in requests.iter() {
            assert!(request.starts_with("PROPFIND "));
            assert!(request.contains(&format!("authorization: {}", dav.authorization)));
            assert!(request.contains("depth: 1"));
            assert!(request.ends_with("body"));
        }
    }

    #[tokio::test]
    async fn cross_origin_redirects_strip_authorization_for_the_entire_chain() {
        for change_host in [false, true] {
            // A different port is a different origin, even on the same host.
            let (target, target_seen) = server(vec![
                ("REPORT", "/redirect", 301, "/calendar".into()),
                ("REPORT", "/calendar", 207, "calendar".into()),
            ])
            .await;
            let target = if change_host {
                target.replace("127.0.0.1", "localhost")
            } else {
                target
            };
            let (base, seen) = server(vec![(
                "REPORT",
                "/start",
                301,
                format!("{target}/redirect"),
            )])
            .await;
            let dav = CalDav::new("user", "password").unwrap();
            let result = dav
                .dav("REPORT", &format!("{base}/start"), "1", "body")
                .await;
            assert_eq!(
                result.unwrap(),
                (format!("{target}/calendar"), "calendar".into())
            );
            assert!(seen.lock().unwrap()[0].contains("authorization: Basic "));
            let requests = target_seen.lock().unwrap();
            assert_eq!(requests.len(), 2);
            for request in requests.iter() {
                assert!(!request.to_ascii_lowercase().contains("authorization:"));
                assert!(request.starts_with("REPORT "));
                assert!(request.ends_with("body"));
            }
        }
    }

    #[tokio::test]
    async fn returning_to_the_original_origin_does_not_restore_authorization() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let port = listener.local_addr().unwrap().port();
        let base = format!("http://127.0.0.1:{port}");
        let destination = format!("{base}/return");
        let task = tokio::spawn(async move {
            let mut requests = Vec::new();
            for location in [
                Some(format!("http://localhost:{port}/redirect")),
                Some(destination),
                None,
            ] {
                let (mut socket, _) = listener.accept().await.unwrap();
                let mut request = Vec::new();
                loop {
                    let mut chunk = [0; 4096];
                    let n = socket.read(&mut chunk).await.unwrap();
                    assert_ne!(n, 0);
                    request.extend_from_slice(&chunk[..n]);
                    if request.windows(4).any(|w| w == b"\r\n\r\n") {
                        break;
                    }
                }
                requests.push(String::from_utf8(request).unwrap());
                let response = match location {
                    Some(url) => format!("HTTP/1.1 301 X\r\nLocation: {url}\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"),
                    None => "HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".into(),
                };
                socket.write_all(response.as_bytes()).await.unwrap();
            }
            requests
        });
        let dav = CalDav::new("user", "password").unwrap();
        let result = dav
            .dav("PROPFIND", &format!("{base}/start"), "0", "")
            .await
            .unwrap();
        assert_eq!(result, (format!("{base}/return"), String::new()));
        let requests = task.await.unwrap();
        assert!(requests[0].contains("authorization: Basic "));
        assert!(!requests[1].contains("authorization:"));
        assert!(!requests[2].contains("authorization:"));
    }

    #[tokio::test]
    async fn finds_the_calendars_reads_the_busy_times_and_adds_an_event() {
        let principal = r#"<d:multistatus xmlns:d="DAV:"><d:response><d:href>/dav/</d:href><d:propstat><d:prop><d:current-user-principal><d:href>/principals/teo/</d:href></d:current-user-principal></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>"#;
        let home = r#"<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:href>/principals/teo/</d:href><d:propstat><d:prop><c:calendar-home-set><d:href>/cal/teo/</d:href></c:calendar-home-set></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>"#;
        let list = r##"<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:a="http://apple.com/ns/ical/">
<d:response><d:href>/cal/teo/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
<d:response><d:href>/cal/teo/personal/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/><c:calendar/></d:resourcetype><d:displayname>Personal</d:displayname><a:calendar-color>#E0782FFF</a:calendar-color><d:current-user-privilege-set><d:privilege><d:read/></d:privilege><d:privilege><d:write/></d:privilege></d:current-user-privilege-set><c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
<d:response><d:href>/cal/teo/family/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/><c:calendar/></d:resourcetype><d:displayname>Family</d:displayname><d:current-user-privilege-set><d:privilege><d:read/></d:privilege></d:current-user-privilege-set></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
<d:response><d:href>/cal/teo/tasks/</d:href><d:propstat><d:prop><d:resourcetype><d:collection/><c:calendar/></d:resourcetype><d:displayname>Tasks</d:displayname><c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
</d:multistatus>"##;
        let events = r#"<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:response><d:href>/cal/teo/personal/1.ics</d:href><d:propstat><d:prop><c:calendar-data>BEGIN:VCALENDAR
BEGIN:VEVENT
UID:1
DTSTART:20261023T133000Z
DTEND:20261023T143000Z
SUMMARY:Dentist
END:VEVENT
END:VCALENDAR
</c:calendar-data></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response></d:multistatus>"#;
        let (base, seen) = server(vec![
            ("PROPFIND", "/.well-known/caldav", 301, "/dav/".into()),
            ("PROPFIND", "/dav/", 207, principal.into()),
            ("PROPFIND", "/principals/teo/", 207, home.into()),
            ("PROPFIND", "/cal/teo/", 207, list.into()),
            ("REPORT", "/cal/teo/personal/", 207, events.into()),
            (
                "PUT",
                "/cal/teo/personal/x-1-example.org.ics",
                201,
                String::new(),
            ),
        ])
        .await;
        let dav = CalDav::new("teo", "secret").unwrap();
        let found = dav
            .discover(&format!("{base}/.well-known/caldav"))
            .await
            .unwrap();
        assert_eq!(found.home, format!("{base}/cal/teo/"));
        assert_eq!(
            found.calendars,
            vec![
                RemoteCalendar {
                    url: format!("{base}/cal/teo/personal/"),
                    name: "Personal".into(),
                    color: Some("#E0782F".into()),
                    read_only: false,
                },
                RemoteCalendar {
                    url: format!("{base}/cal/teo/family/"),
                    name: "Family".into(),
                    color: None,
                    read_only: true,
                },
            ]
        );
        let busy = dav
            .events(&found.calendars[0].url, 1_792_800_000, 1_793_000_000)
            .await
            .unwrap();
        assert_eq!(busy.len(), 1);
        assert_eq!(busy[0].summary, "Dentist");
        dav.add(
            &found.calendars[0].url,
            "x/1@example.org",
            "BEGIN:VCALENDAR\r\nEND:VCALENDAR\r\n",
        )
        .await
        .unwrap();
        let seen = seen.lock().unwrap();
        assert!(seen
            .iter()
            .all(|r| r.contains("authorization: Basic dGVvOnNlY3JldA==")));
        assert!(seen
            .iter()
            .any(|r| r.contains("<c:expand start=\"20261024T000000Z\"")));
        assert!(seen.last().unwrap().contains("if-none-match: *"));
    }

    #[tokio::test]
    async fn a_wrong_password_is_said_so() {
        let (base, _) = server(vec![("PROPFIND", "/dav/", 401, String::new())]).await;
        let dav = CalDav::new("teo", "nope").unwrap();
        assert!(matches!(
            dav.discover(&format!("{base}/dav/")).await,
            Err(CalendarError::WrongPassword)
        ));
    }

    #[test]
    fn where_to_look() {
        assert_eq!(starts("teo@icloud.com"), ["https://caldav.icloud.com/"]);
        assert_eq!(
            starts("https://cloud.example.com/dav"),
            ["https://cloud.example.com/dav"]
        );
        assert_eq!(
            starts("m@studio.it")[0],
            "https://studio.it/.well-known/caldav"
        );
        assert_eq!(
            feed_url("webcal://example.com/h.ics"),
            "https://example.com/h.ics"
        );
        assert!(offers_calendar("Teo@iCloud.com"));
        assert!(!offers_calendar("matteo@posta.it"));
        assert_eq!(utc(0), "19700101T000000Z");
    }
}
