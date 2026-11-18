//! JMAP against a small server inside the test: just enough of RFC 8620
//! and RFC 8621 to answer what the engine asks.

use std::collections::{BTreeMap, BTreeSet};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use piuma_core::imap::FolderRole;
use piuma_core::jmap::{discover_at, Client, JmapConfig, JmapError};
use piuma_core::model::{Account, AccountId, AccountKind};
use piuma_core::remote::{Remote, Snapshot};
use piuma_core::space::{self, Device, Key};
use piuma_core::space_sync::{self, Me, Round};
use piuma_core::{Folder, Store};
use serde_json::{json, Value};
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::net::{TcpListener, TcpStream};

const USER: &str = "matteo@example.com";
const PASSWORD: &str = "secret";
/// One of the account's aliases, with an identity of its own.
const ALIAS: &str = "studio@example.com";
/// The server hands out ids two at a time, to make the engine page.
const QUERY_CAP: usize = 2;

#[derive(Default)]
struct Email {
    raw: Vec<u8>,
    mailboxes: BTreeSet<String>,
    keywords: BTreeSet<String>,
    received: String,
}

#[derive(Default)]
struct Server {
    mailboxes: Vec<(String, String, Option<String>)>,
    emails: BTreeMap<String, Email>,
    blobs: BTreeMap<String, Vec<u8>>,
    next: u32,
    sent: Vec<(String, Vec<String>)>,
    /// The identity and MAIL FROM of each submission, in order.
    senders: Vec<(String, String)>,
    changed: Arc<tokio::sync::Notify>,
    /// Whether `header:` properties are answered, as by servers that the
    /// engine asked before it read list headers.
    headers: bool,
    /// The away message (RFC 8621 section 8), on servers that keep one.
    vacation: Option<Value>,
    /// Folders inside others: child id to parent id.
    parents: BTreeMap<String, String>,
    /// Folders not subscribed to; the rest are.
    unsubscribed: BTreeSet<String>,
    /// Bytes used and allowed, on servers that keep quotas (RFC 9425).
    quota: Option<(u64, u64)>,
    /// The next submission is made, but its answer never arrives.
    drop_submission: bool,
    /// The next submission is refused (`notCreated`).
    refuse_submission: bool,
    /// The identities (id, address) when not the usual three; an address
    /// may be a wildcard, `*@domain`.
    identities: Option<Vec<(String, String)>>,
}

impl Server {
    /// The account's identities, as `Identity/get` lists them.
    fn identities(&self) -> Vec<(String, String)> {
        self.identities.clone().unwrap_or_else(|| {
            vec![
                ("other".into(), "someone@example.com".into()),
                ("me".into(), USER.into()),
                ("alias".into(), ALIAS.into()),
            ]
        })
    }

    fn add(&mut self, mailbox: &str, from: &str, subject: &str, day: u32, seen: bool) -> String {
        self.next += 1;
        let id = format!("M{}", self.next);
        let raw = format!(
            "From: {from}\r\nTo: Matteo <{USER}>\r\nSubject: {subject}\r\nMessage-ID: <{id}@example.org>\r\n\
             Content-Type: text/plain\r\n\r\nHello about {subject}.\r\n"
        );
        let mut keywords = BTreeSet::new();
        if seen {
            keywords.insert("$seen".to_owned());
        }
        self.emails.insert(
            id.clone(),
            Email {
                raw: raw.into_bytes(),
                mailboxes: [mailbox.to_owned()].into(),
                keywords,
                received: format!("2026-10-{day:02}T09:00:00Z"),
            },
        );
        self.changed.notify_waiters();
        id
    }

    fn add_raw(&mut self, mailbox: &str, raw: &str, day: u32) -> String {
        self.next += 1;
        let id = format!("M{}", self.next);
        self.emails.insert(
            id.clone(),
            Email {
                raw: raw.as_bytes().to_vec(),
                mailboxes: [mailbox.to_owned()].into(),
                received: format!("2026-10-{day:02}T09:00:00Z"),
                ..Email::default()
            },
        );
        id
    }

    /// One part of a message, by the blob id `email_json` gave it.
    fn part(&self, blob: &str) -> Option<Vec<u8>> {
        let (id, part) = blob.rsplit_once('-')?;
        let m = mail_parser::MessageParser::default().parse(&self.emails.get(id)?.raw)?;
        Some(m.part(part.parse().ok()?)?.decoded().to_vec())
    }

    fn email_json(&self, id: &str, properties: &[String]) -> Value {
        let e = &self.emails[id];
        let m = mail_parser::MessageParser::default().parse(&e.raw).unwrap();
        let addr = |list: Option<mail_parser::AddressList<'_>>| -> Value {
            list.map(|l| {
                l.mailboxes()
                    .map(|a| json!({ "name": a.name(), "email": a.address() }))
                    .collect::<Vec<_>>()
            })
            .map(Value::from)
            .unwrap_or(Value::Null)
        };
        let all = json!({
            "id": id,
            "blobId": format!("blob-{id}"),
            "mailboxIds": e.mailboxes.iter().map(|m| (m.clone(), json!(true))).collect::<serde_json::Map<_, _>>(),
            "keywords": e.keywords.iter().map(|k| (k.clone(), json!(true))).collect::<serde_json::Map<_, _>>(),
            "from": addr(m.from()),
            "to": addr(m.to()),
            "cc": addr(m.cc()),
            "replyTo": addr(m.reply_to()),
            "subject": m.subject(),
            "preview": m.body_preview(100),
            "receivedAt": e.received,
            "messageId": m.message_id().map(|i| vec![i]),
            "references": null,
            "inReplyTo": null,
        });
        let attachments: Vec<Value> = m
            .attachments()
            .map(|part| {
                let i = part.id();
                json!({
                    "blobId": format!("blob-{id}-{i}"),
                    "type": part.content_type().map(|t| match t.subtype() {
                        Some(sub) => format!("{}/{sub}", t.ctype()),
                        None => t.ctype().to_owned(),
                    }),
                    "name": part.attachment_name(),
                    "disposition": part.content_disposition().map(|d| d.ctype()),
                    "cid": part.content_id(),
                    "size": part.decoded().len(),
                })
            })
            .collect();
        let mut out = serde_json::Map::new();
        for p in properties {
            let value = match p.as_str() {
                "size" => json!(e.raw.len()),
                "attachments" => json!(attachments),
                header if header.starts_with("header:") && header.ends_with(":asAddresses") => {
                    let name = &header["header:".len()..header.len() - ":asAddresses".len()];
                    match m.headers().get(name) {
                        Some(h) if self.headers => {
                            let parsed = h.parse_as(mail_parser::HeaderForm::Addresses);
                            addr(parsed.value().as_address())
                        }
                        _ => Value::Null,
                    }
                }
                header if header.starts_with("header:") && self.headers => m
                    .headers()
                    .get(&header["header:".len()..])
                    .and_then(|h| std::str::from_utf8(h.raw_value()).ok())
                    .map_or(Value::Null, |v| json!(v)),
                _ => all.get(p).cloned().unwrap_or(Value::Null),
            };
            out.insert(p.clone(), value);
        }
        Value::Object(out)
    }

    fn patch(&mut self, id: &str, patch: &Value) {
        let e = self.emails.get_mut(id).unwrap();
        for (path, value) in patch.as_object().unwrap() {
            let (set, key) = path.split_once('/').unwrap();
            let target = if set == "keywords" {
                &mut e.keywords
            } else {
                &mut e.mailboxes
            };
            if value.as_bool() == Some(true) {
                target.insert(key.to_owned());
            } else {
                target.remove(key);
            }
        }
    }

    fn method(&mut self, name: &str, args: &Value) -> Vec<(String, Value)> {
        let one = |v: Value| vec![(name.to_owned(), v)];
        match name {
            "Mailbox/get" => one(json!({ "list": self.mailboxes.iter().map(|(id, name, role)|
                json!({ "id": id, "name": name, "role": role,
                        "parentId": self.parents.get(id),
                        "isSubscribed": !self.unsubscribed.contains(id),
                        "totalEmails": self.emails.values().filter(|e| e.mailboxes.contains(id)).count() }))
                .collect::<Vec<_>>() })),
            "Mailbox/set" => {
                let mut answer = json!({});
                if let Some(new) = args["create"].get("new") {
                    let id = match new["role"].as_str() {
                        Some(role) => format!("mb-{role}"),
                        None => format!("mb-{}", self.mailboxes.len() + 1),
                    };
                    self.mailboxes.push((
                        id.clone(),
                        new["name"].as_str().unwrap().into(),
                        new["role"].as_str().map(str::to_owned),
                    ));
                    answer["created"] = json!({ "new": { "id": id } });
                }
                let mut updated = serde_json::Map::new();
                for (id, patch) in args["update"].as_object().into_iter().flatten() {
                    let Some(m) = self.mailboxes.iter_mut().find(|(m, _, _)| m == id) else {
                        continue;
                    };
                    if let Some(name) = patch["name"].as_str() {
                        m.1 = name.into();
                    }
                    match patch["isSubscribed"].as_bool() {
                        Some(true) => {
                            self.unsubscribed.remove(id);
                        }
                        Some(false) => {
                            self.unsubscribed.insert(id.clone());
                        }
                        None => {}
                    }
                    updated.insert(id.clone(), Value::Null);
                }
                answer["updated"] = Value::Object(updated);
                let mut destroyed = Vec::new();
                let mut not = serde_json::Map::new();
                for id in args["destroy"].as_array().into_iter().flatten() {
                    let id = id.as_str().unwrap().to_owned();
                    let kept = args["onDestroyRemoveEmails"].as_bool() != Some(true);
                    if self.parents.values().any(|p| *p == id) {
                        not.insert(id, json!({ "type": "mailboxHasChild" }));
                    } else if kept && self.emails.values().any(|e| e.mailboxes.contains(&id)) {
                        not.insert(id, json!({ "type": "mailboxHasEmail" }));
                    } else {
                        self.mailboxes.retain(|(m, _, _)| *m != id);
                        self.parents.remove(&id);
                        destroyed.push(id);
                    }
                }
                answer["destroyed"] = json!(destroyed);
                answer["notDestroyed"] = Value::Object(not);
                one(answer)
            }
            "Quota/get" => {
                let (used, limit) = self.quota.unwrap();
                one(json!({ "list": [
                    { "id": "q0", "resourceType": "count", "scope": "account", "used": 3, "hardLimit": 50 },
                    { "id": "q1", "resourceType": "octets", "scope": "account", "used": used, "hardLimit": limit },
                ] }))
            }
            "Email/query" if args["filter"]["operator"].is_string() => {
                let ids: Vec<&String> = self
                    .emails
                    .iter()
                    .filter(|(_, e)| matches_filter(e, &args["filter"]))
                    .map(|(id, _)| id)
                    .collect();
                one(json!({ "ids": ids, "position": 0 }))
            }
            "EmailSubmission/query" => {
                let wanted: Vec<String> =
                    serde_json::from_value(args["filter"]["emailIds"].clone()).unwrap();
                let ids: Vec<String> = self
                    .sent
                    .iter()
                    .enumerate()
                    .filter(|(_, (email, _))| wanted.contains(email))
                    .map(|(i, _)| format!("S{}", i + 1))
                    .collect();
                one(json!({ "ids": ids }))
            }
            "Email/query" => {
                let mailbox = args["filter"]["inMailbox"].as_str().unwrap();
                let mut ids: Vec<(&String, &Email)> = self
                    .emails
                    .iter()
                    .filter(|(_, e)| e.mailboxes.contains(mailbox))
                    .collect();
                ids.sort_by(|a, b| b.1.received.cmp(&a.1.received));
                let total = ids.len();
                let position = args["position"].as_u64().unwrap() as usize;
                let limit = (args["limit"].as_u64().unwrap() as usize).min(QUERY_CAP);
                let page: Vec<&String> = ids
                    .iter()
                    .skip(position)
                    .take(limit)
                    .map(|(id, _)| *id)
                    .collect();
                one(json!({ "ids": page, "total": total, "position": position }))
            }
            "Email/get" => {
                let properties: Vec<String> =
                    serde_json::from_value(args["properties"].clone()).unwrap();
                let list: Vec<Value> = args["ids"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .filter_map(|id| id.as_str())
                    .filter(|id| self.emails.contains_key(*id))
                    .map(|id| self.email_json(id, &properties))
                    .collect();
                one(json!({ "list": list }))
            }
            "Email/set" => {
                let mut updated = serde_json::Map::new();
                for (id, patch) in args["update"].as_object().into_iter().flatten() {
                    self.patch(id, patch);
                    updated.insert(id.clone(), Value::Null);
                }
                let mut destroyed = Vec::new();
                for id in args["destroy"].as_array().into_iter().flatten() {
                    let id = id.as_str().unwrap();
                    if self.emails.remove(id).is_some() {
                        destroyed.push(id.to_owned());
                    }
                }
                one(json!({ "updated": updated, "destroyed": destroyed }))
            }
            "Email/import" => {
                let new = &args["emails"]["new"];
                let raw = self.blobs[new["blobId"].as_str().unwrap()].clone();
                self.next += 1;
                let id = format!("M{}", self.next);
                self.emails.insert(
                    id.clone(),
                    Email {
                        raw,
                        mailboxes: new["mailboxIds"]
                            .as_object()
                            .unwrap()
                            .keys()
                            .cloned()
                            .collect(),
                        keywords: new["keywords"]
                            .as_object()
                            .unwrap()
                            .keys()
                            .cloned()
                            .collect(),
                        // A second apart, as imports made one after another.
                        received: format!(
                            "2026-10-20T09:{:02}:{:02}Z",
                            self.next / 60,
                            self.next % 60
                        ),
                    },
                );
                one(json!({ "created": { "new": { "id": id } } }))
            }
            "VacationResponse/get" => {
                assert_eq!(args["ids"], json!(["singleton"]));
                one(json!({ "list": [self.vacation.clone().unwrap()] }))
            }
            "VacationResponse/set" => {
                let v = self.vacation.as_mut().unwrap();
                for (k, value) in args["update"]["singleton"].as_object().unwrap() {
                    v[k] = value.clone();
                }
                one(json!({ "updated": { "singleton": null } }))
            }
            "Identity/get" => one(json!({ "list": self
                .identities()
                .into_iter()
                .map(|(id, email)| json!({ "id": id, "email": email }))
                .collect::<Vec<_>>() })),
            "EmailSubmission/set" if self.refuse_submission => {
                self.refuse_submission = false;
                one(json!({ "notCreated": { "send": { "type": "forbiddenToSend" } } }))
            }
            "EmailSubmission/set" => {
                let send = &args["create"]["send"];
                let from = send["envelope"]["mailFrom"]["email"]
                    .as_str()
                    .unwrap()
                    .to_owned();
                let identity = send["identityId"].as_str().unwrap().to_owned();
                // As servers do: the envelope goes from the identity's
                // own address (any in its domain, for a wildcard), or
                // nothing goes.
                let own = self
                    .identities()
                    .into_iter()
                    .find(|(id, _)| *id == identity)
                    .map(|(_, email)| email)
                    .unwrap_or_default();
                let allowed = match own.strip_prefix("*@") {
                    Some(domain) => from.rsplit_once('@').is_some_and(|(_, d)| d == domain),
                    None => from == own,
                };
                if !allowed {
                    return one(json!({
                        "notCreated": { "send": { "type": "forbiddenMailFrom" } }
                    }));
                }
                self.senders.push((identity, from));
                let email = send["emailId"].as_str().unwrap().to_owned();
                let rcpt = send["envelope"]["rcptTo"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .map(|r| r["email"].as_str().unwrap().to_owned())
                    .collect();
                self.sent.push((email.clone(), rcpt));
                self.patch(&email, &args["onSuccessUpdateEmail"]["#send"]);
                vec![
                    (
                        name.to_owned(),
                        json!({ "created": { "send": { "id": "S1" } } }),
                    ),
                    (
                        "Email/set".to_owned(),
                        json!({ "updated": { email: null } }),
                    ),
                ]
            }
            other => vec![(
                "error".to_owned(),
                json!({ "type": "unknownMethod", "method": other }),
            )],
        }
    }
}

/// A JMAP filter (RFC 8621 4.4.1), as far as the engine uses one: a
/// header filter matches a part of the value, ignoring case, as servers do.
fn matches_filter(e: &Email, f: &Value) -> bool {
    if let Some(op) = f["operator"].as_str() {
        let mut each = f["conditions"]
            .as_array()
            .unwrap()
            .iter()
            .map(|c| matches_filter(e, c));
        return match op {
            "AND" => each.all(|m| m),
            "OR" => each.any(|m| m),
            _ => !each.any(|m| m),
        };
    }
    if let Some(mailbox) = f["inMailbox"].as_str() {
        return e.mailboxes.contains(mailbox);
    }
    if let Some(header) = f["header"].as_array() {
        let name = format!("{}:", header[0].as_str().unwrap().to_lowercase());
        let wanted = header[1].as_str().unwrap().to_lowercase();
        return String::from_utf8_lossy(&e.raw).lines().any(|l| {
            let l = l.to_lowercase();
            l.starts_with(&name) && l.contains(&wanted)
        });
    }
    true
}

async fn read_request(tcp: &mut TcpStream) -> Option<(String, String, Vec<u8>)> {
    let mut buf = Vec::new();
    let mut chunk = [0u8; 8192];
    let head_end = loop {
        if let Some(i) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
            break i + 4;
        }
        let n = tcp.read(&mut chunk).await.ok()?;
        if n == 0 {
            return None;
        }
        buf.extend_from_slice(&chunk[..n]);
    };
    let head = String::from_utf8_lossy(&buf[..head_end]).to_string();
    let length: usize = head
        .lines()
        .find_map(|l| {
            let (k, v) = l.split_once(':')?;
            k.eq_ignore_ascii_case("content-length")
                .then(|| v.trim().parse().ok())?
        })
        .unwrap_or(0);
    while buf.len() < head_end + length {
        let n = tcp.read(&mut chunk).await.ok()?;
        if n == 0 {
            return None;
        }
        buf.extend_from_slice(&chunk[..n]);
    }
    let first = head.lines().next()?.to_owned();
    let mut parts = first.split(' ');
    let (method, path) = (parts.next()?.to_owned(), parts.next()?.to_owned());
    let authorized = head.lines().any(|l| {
        l.to_ascii_lowercase().starts_with("authorization:")
            && l.ends_with("Basic bWF0dGVvQGV4YW1wbGUuY29tOnNlY3JldA==")
    });
    let path = match path.as_str() {
        "/.well-known/jmap" => path,
        p if !authorized && p.starts_with("/jmap/") => "/unauthorized".into(),
        _ => path,
    };
    Some((method, path, buf[head_end..head_end + length].to_vec()))
}

async fn respond(tcp: &mut TcpStream, status: &str, kind: &str, body: &[u8]) {
    let head = format!(
        "HTTP/1.1 {status}\r\nContent-Type: {kind}\r\nContent-Length: {}\r\n\r\n",
        body.len()
    );
    let _ = tcp.write_all(head.as_bytes()).await;
    let _ = tcp.write_all(body).await;
}

async fn serve(state: Arc<Mutex<Server>>, mut tcp: TcpStream, port: u16) {
    while let Some((method, path, body)) = read_request(&mut tcp).await {
        let base = format!("http://127.0.0.1:{port}");
        match (method.as_str(), path.as_str()) {
            (_, "/unauthorized") => {
                let _ = tcp
                    .write_all(
                        b"HTTP/1.1 401 Unauthorized\r\nWWW-Authenticate: Basic realm=\"mail\"\r\nContent-Length: 0\r\n\r\n",
                    )
                    .await;
            }
            ("GET", "/.well-known/jmap") => {
                let _ = tcp
                    .write_all(
                        b"HTTP/1.1 307 Temporary Redirect\r\nLocation: /jmap/session\r\nContent-Length: 0\r\n\r\n",
                    )
                    .await;
            }
            ("GET", "/jmap/session") => {
                let mut capabilities =
                    json!({ "urn:ietf:params:jmap:core": { "maxObjectsInGet": 3 } });
                if state.lock().unwrap().vacation.is_some() {
                    capabilities["urn:ietf:params:jmap:vacationresponse"] = json!({});
                }
                if state.lock().unwrap().quota.is_some() {
                    capabilities["urn:ietf:params:jmap:quota"] = json!({});
                }
                let session = json!({
                    "capabilities": capabilities,
                    "accounts": { "A1": { "name": USER } },
                    "primaryAccounts": { "urn:ietf:params:jmap:mail": "A1" },
                    "apiUrl": "/jmap/api",
                    "downloadUrl": format!("{base}/jmap/download/{{accountId}}/{{blobId}}/{{name}}?accept={{type}}"),
                    "uploadUrl": format!("{base}/jmap/upload/{{accountId}}/"),
                    "eventSourceUrl": format!("{base}/jmap/events?types={{types}}&closeafter={{closeafter}}&ping={{ping}}"),
                    "state": "s1",
                });
                respond(
                    &mut tcp,
                    "200 OK",
                    "application/json",
                    session.to_string().as_bytes(),
                )
                .await;
            }
            ("POST", "/jmap/api") => {
                let request: Value = serde_json::from_slice(&body).unwrap();
                let vacation = request["methodCalls"]
                    .as_array()
                    .unwrap()
                    .iter()
                    .any(|c| c[0].as_str().unwrap().starts_with("VacationResponse/"));
                let using = request["using"].as_array().unwrap();
                assert_eq!(
                    vacation,
                    using.contains(&json!("urn:ietf:params:jmap:vacationresponse"))
                );
                let mut responses = Vec::new();
                let lost = {
                    let mut s = state.lock().unwrap();
                    let submits = request["methodCalls"]
                        .as_array()
                        .unwrap()
                        .iter()
                        .any(|c| c[0] == "EmailSubmission/set");
                    for call in request["methodCalls"].as_array().unwrap() {
                        for (name, args) in s.method(call[0].as_str().unwrap(), &call[1]) {
                            responses.push(json!([name, args, call[2]]));
                        }
                    }
                    let lost = submits && s.drop_submission;
                    if lost {
                        s.drop_submission = false;
                    }
                    lost
                };
                if lost {
                    // Done, but the answer never makes it back.
                    return;
                }
                let answer = json!({ "methodResponses": responses, "sessionState": "s1" });
                respond(
                    &mut tcp,
                    "200 OK",
                    "application/json",
                    answer.to_string().as_bytes(),
                )
                .await;
            }
            ("POST", p) if p.starts_with("/jmap/upload/A1/") => {
                let blob = {
                    let mut s = state.lock().unwrap();
                    let blob = format!("up-{}", s.blobs.len() + 1);
                    s.blobs.insert(blob.clone(), body);
                    blob
                };
                let answer = json!({ "accountId": "A1", "blobId": blob, "type": "message/rfc822" });
                respond(
                    &mut tcp,
                    "201 Created",
                    "application/json",
                    answer.to_string().as_bytes(),
                )
                .await;
            }
            ("GET", p) if p.starts_with("/jmap/download/A1/blob-") => {
                let id = p["/jmap/download/A1/blob-".len()..]
                    .split('/')
                    .next()
                    .unwrap();
                let raw = {
                    let s = state.lock().unwrap();
                    s.emails
                        .get(id)
                        .map(|e| e.raw.clone())
                        .or_else(|| s.part(id))
                };
                match raw {
                    Some(raw) => respond(&mut tcp, "200 OK", "message/rfc822", &raw).await,
                    None => respond(&mut tcp, "404 Not Found", "text/plain", b"").await,
                }
            }
            ("GET", p) if p.starts_with("/jmap/events?types=Email,Mailbox&closeafter=state") => {
                let changed = state.lock().unwrap().changed.clone();
                let _ = tcp
                    .write_all(b"HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\n\r\n")
                    .await;
                let _ = tcp.write_all(b"event: ping\r\ndata: {}\r\n\r\n").await;
                changed.notified().await;
                let _ = tcp
                    .write_all(b"event: state\r\ndata: {\"changed\":{}}\r\n\r\n")
                    .await;
                return;
            }
            _ => respond(&mut tcp, "404 Not Found", "text/plain", b"").await,
        }
    }
}

async fn start() -> (Arc<Mutex<Server>>, JmapConfig) {
    let mut server = Server {
        mailboxes: vec![
            ("mb-in".into(), "Inbox".into(), Some("inbox".into())),
            ("mb-sent".into(), "Sent".into(), Some("sent".into())),
            ("mb-drafts".into(), "Drafts".into(), Some("drafts".into())),
            ("mb-misc".into(), "Receipts".into(), None),
        ],
        ..Server::default()
    };
    for (i, from) in [
        "Julia <julia@example.org>",
        "Ana <ana@example.org>",
        "Leo <leo@example.org>",
    ]
    .into_iter()
    .enumerate()
    {
        server.add(
            "mb-in",
            from,
            &format!("Note {}", i + 1),
            i as u32 + 1,
            i == 0,
        );
    }
    server.add("mb-in", "Shop <news@shop.it>", "Sale", 4, false);
    server.add("mb-in", "Julia <julia@example.org>", "Lunch", 5, false);
    server.add(
        "mb-sent",
        &format!("Matteo <{USER}>"),
        "Re: Note 1",
        2,
        true,
    );
    let state = Arc::new(Mutex::new(server));
    let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let shared = state.clone();
    tokio::spawn(async move {
        while let Ok((tcp, _)) = listener.accept().await {
            tokio::spawn(serve(shared.clone(), tcp, port));
        }
    });
    // The local server speaks plain http; the app never may.
    piuma_core::jmap::allow_loopback_http_for_tests();
    let cfg = JmapConfig {
        session_url: format!("http://127.0.0.1:{port}/jmap/session"),
        username: USER.into(),
        password: PASSWORD.into(),
    };
    (state, cfg)
}

fn store_with_account(cfg: &JmapConfig) -> (Arc<Mutex<Store>>, AccountId) {
    with_account(Store::open_in_memory().unwrap(), cfg)
}

fn with_account(store: Store, cfg: &JmapConfig) -> (Arc<Mutex<Store>>, AccountId) {
    let account = store
        .add_account(&Account {
            id: AccountId(0),
            name: "Home".into(),
            email: USER.into(),
            sender_name: "Matteo".into(),
            color: "#3451D1".into(),
            kind: AccountKind::Jmap {
                session_url: cfg.session_url.clone(),
                username: cfg.username.clone(),
            },
        })
        .unwrap();
    (Arc::new(Mutex::new(store)), account)
}

fn subjects(store: &Mutex<Store>, folder: Folder) -> Vec<String> {
    store
        .lock()
        .unwrap()
        .unified(folder, None, 50)
        .unwrap()
        .into_iter()
        .map(|m| m.subject)
        .collect()
}

#[tokio::test]
async fn a_wrong_password_is_refused() {
    let (_, mut cfg) = start().await;
    cfg.password = "wrong".into();
    assert!(matches!(Client::open(&cfg).await, Err(JmapError::Auth)));
}

#[tokio::test]
async fn mirrors_the_inbox_and_keeps_up_with_changes() {
    let (server, cfg) = start().await;
    let (store, account) = store_with_account(&cfg);
    let mut client = Client::open(&cfg).await.unwrap();

    let mut seen_progress = Vec::new();
    let report = client
        .sync_mailbox(&store, account, "INBOX", |done, total| {
            seen_progress.push((done, total))
        })
        .await
        .unwrap();
    assert_eq!(report.added, 5);
    assert!(report.arrived.is_empty(), "the first download is history");
    // maxObjectsInGet is 3: two rounds.
    assert_eq!(seen_progress, [(3, 5), (5, 5)]);
    assert_eq!(
        subjects(&store, Folder::Inbox),
        ["Lunch", "Sale", "Note 3", "Note 2", "Note 1"]
    );
    let first = store
        .lock()
        .unwrap()
        .unified(Folder::Inbox, None, 50)
        .unwrap();
    assert_eq!(first[0].from_email, "julia@example.org");
    assert_eq!(first[0].reply.message_id, "<M5@example.org>");
    assert!(first[4].flags.seen && !first[0].flags.seen);

    // On the server: one new, one read elsewhere, one deleted.
    {
        let mut s = server.lock().unwrap();
        s.add("mb-in", "Leo <leo@example.org>", "Tickets", 6, false);
        s.emails
            .get_mut("M2")
            .unwrap()
            .keywords
            .insert("$seen".into());
        s.emails.remove("M3");
    }
    let report = client
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert_eq!(
        (report.added, report.removed, report.flags_changed),
        (1, 1, 1)
    );
    assert_eq!(report.arrived.len(), 1);
    assert_eq!(report.arrived[0].summary.subject, "Tickets");
    assert!(!report.arrived[0].automated);
    assert_eq!(
        subjects(&store, Folder::Inbox),
        ["Tickets", "Lunch", "Sale", "Note 2", "Note 1"]
    );

    // Nothing changed: nothing to do.
    let report = client
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert!(!report.changed());
}

#[tokio::test]
async fn reads_marks_moves_and_finds_folders() {
    let (server, cfg) = start().await;
    let (store, account) = store_with_account(&cfg);
    let mut client = Client::open(&cfg).await.unwrap();
    client
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let lunch = store
        .lock()
        .unwrap()
        .unified(Folder::Inbox, None, 1)
        .unwrap()[0]
        .uid;

    let body = client
        .full_body(&store, account, "INBOX", lunch)
        .await
        .unwrap();
    assert_eq!(body.text, "Hello about Lunch.");
    assert!(store
        .lock()
        .unwrap()
        .full_body(account, "INBOX", lunch)
        .unwrap()
        .is_some());

    client
        .set_seen(&store, account, "INBOX", &[lunch], true)
        .await
        .unwrap();
    assert!(server.lock().unwrap().emails["M5"]
        .keywords
        .contains("$seen"));

    // No Archive yet: it is made, and the message moves there.
    let archive = client
        .move_messages(&store, account, "INBOX", &[lunch], FolderRole::Archive)
        .await
        .unwrap();
    assert_eq!(archive, "mb-archive");
    assert_eq!(
        server.lock().unwrap().emails["M5"].mailboxes,
        ["mb-archive".to_owned()].into()
    );
    assert!(!subjects(&store, Folder::Inbox).contains(&"Lunch".to_owned()));

    client.sync_folders(&store, account).await.unwrap();
    assert_eq!(subjects(&store, Folder::Archive), ["Lunch"]);
    assert_eq!(subjects(&store, Folder::Sent), ["Re: Note 1"]);
    assert_eq!(
        store
            .lock()
            .unwrap()
            .folder_mailbox(account, Folder::Sent)
            .unwrap()
            .as_deref(),
        Some("mb-sent")
    );
}

#[tokio::test]
async fn keeps_drafts_and_sends() {
    let (server, cfg) = start().await;
    let (store, account) = store_with_account(&cfg);
    let mut client = Client::open(&cfg).await.unwrap();
    let raw = format!(
        "From: Matteo <{USER}>\r\nTo: julia@example.org\r\nSubject: Plans\r\n\r\nSee you.\r\n"
    );

    let drafts = client.append_draft(raw.as_bytes()).await.unwrap();
    assert_eq!(drafts, "mb-drafts");
    client.sync_folders(&store, account).await.unwrap();
    assert_eq!(subjects(&store, Folder::Drafts), ["Plans"]);
    let uid = store
        .lock()
        .unwrap()
        .unified(Folder::Drafts, None, 1)
        .unwrap()[0]
        .uid;
    client
        .erase(&store, account, "mb-drafts", &[uid])
        .await
        .unwrap();
    assert!(subjects(&store, Folder::Drafts).is_empty());

    let sent = client
        .send(raw.as_bytes(), USER, &["julia@example.org".into()], "")
        .await
        .unwrap();
    assert_eq!(sent, "mb-sent");
    let s = server.lock().unwrap();
    let (email, rcpt) = &s.sent[0];
    assert_eq!(rcpt, &["julia@example.org".to_owned()]);
    assert_eq!(s.emails[email].mailboxes, ["mb-sent".to_owned()].into());
    assert!(!s.emails[email].keywords.contains("$draft"));
}

const ONCE: &str = "<once-1@example.com>";

fn once() -> String {
    format!(
        "From: Matteo <{USER}>\r\nTo: julia@example.org\r\nSubject: Once\r\nMessage-ID: {ONCE}\r\n\r\nOnce.\r\n"
    )
}

#[tokio::test]
async fn a_send_whose_answer_was_lost_is_not_sent_twice() {
    let (server, cfg) = start().await;
    let mut client = Client::open(&cfg).await.unwrap();
    let rcpt = ["julia@example.org".to_owned()];
    server.lock().unwrap().drop_submission = true;
    let err = client
        .send(once().as_bytes(), USER, &rcpt, ONCE)
        .await
        .unwrap_err();
    assert!(matches!(err, JmapError::Uncertain(_)), "{err:?}");
    assert_eq!(server.lock().unwrap().sent.len(), 1, "the server sent it");

    // The server can tell it went; sending again does nothing.
    let mut client = Client::open(&cfg).await.unwrap();
    assert!(client.sent_state(ONCE).await.unwrap().unwrap().submitted);
    let emails = server.lock().unwrap().emails.len();
    let sent = client
        .send(once().as_bytes(), USER, &rcpt, ONCE)
        .await
        .unwrap();
    assert_eq!(sent, "mb-sent");
    let s = server.lock().unwrap();
    assert_eq!(s.sent.len(), 1, "not sent twice");
    assert_eq!(s.emails.len(), emails, "no second copy");
}

#[tokio::test]
async fn a_send_tried_again_uses_the_copy_it_left_in_drafts() {
    let (server, cfg) = start().await;
    let mut client = Client::open(&cfg).await.unwrap();
    let rcpt = ["julia@example.org".to_owned()];
    assert_eq!(client.sent_state(ONCE).await.unwrap(), None);
    server.lock().unwrap().refuse_submission = true;
    client
        .send(once().as_bytes(), USER, &rcpt, ONCE)
        .await
        .unwrap_err();
    let emails = server.lock().unwrap().emails.len();
    let state = client.sent_state(ONCE).await.unwrap().unwrap();
    assert!(!state.submitted, "the server can tell it never went");
    assert!(state.draft.is_some());
    client
        .send(once().as_bytes(), USER, &rcpt, ONCE)
        .await
        .unwrap();
    let s = server.lock().unwrap();
    assert_eq!(s.sent.len(), 1);
    assert_eq!(s.emails.len(), emails, "the copy in Drafts was used again");
    let (email, _) = &s.sent[0];
    assert_eq!(s.emails[email].mailboxes, ["mb-sent".to_owned()].into());
}

#[tokio::test]
async fn a_message_id_that_only_contains_ours_is_not_taken_for_it() {
    let (server, cfg) = start().await;
    // Someone else's message in Drafts whose Message-ID contains ours, as
    // the header filter matches parts of values; and a sent one in another
    // case. Neither is this message.
    let (other, shouted) = {
        let mut s = server.lock().unwrap();
        let other = s.add_raw(
            "mb-drafts",
            "From: x@example.org\r\nTo: boss@example.org\r\nSubject: Private\r\n\
             Message-ID: <xonce-1@example.com.other>\r\n\r\nNot for Julia.\r\n",
            3,
        );
        let shouted = s.add_raw(
            "mb-sent",
            "From: x@example.org\r\nTo: a@example.org\r\nSubject: Loud\r\n\
             Message-ID: <ONCE-1@EXAMPLE.COM>\r\n\r\nHi.\r\n",
            3,
        );
        (other, shouted)
    };
    let mut client = Client::open(&cfg).await.unwrap();
    assert_eq!(client.sent_state(ONCE).await.unwrap(), None);
    let emails = server.lock().unwrap().emails.len();
    client
        .send(
            once().as_bytes(),
            USER,
            &["julia@example.org".to_owned()],
            ONCE,
        )
        .await
        .unwrap();
    let s = server.lock().unwrap();
    assert_eq!(s.emails.len(), emails + 1, "this message, imported fresh");
    let (email, _) = &s.sent[0];
    assert_ne!(email, &other);
    assert_ne!(email, &shouted);
    assert!(String::from_utf8_lossy(&s.emails[email].raw).contains("Once."));
}

#[tokio::test]
async fn keeps_every_recipient_and_redirects() {
    use piuma_core::envelope::{self, reply_recipients, Address, ReplyMode};
    let (server, cfg) = start().await;
    let (store, account) = store_with_account(&cfg);
    let id = {
        let mut s = server.lock().unwrap();
        s.headers = true;
        s.add_raw(
            "mb-in",
            &format!(
                "From: Anna <anna@x.it>\r\nReply-To: desk@x.it, Bo <bo@x.it>\r\n\
                 To: Matteo <{USER}>, Carla <carla@x.it>\r\nCc: dan@x.it\r\n\
                 Mail-Followup-To: team@x.it, Carla <carla@x.it>\r\n\
                 Subject: Plan for Friday\r\nMessage-ID: <plan@x.it>\r\n\
                 Content-Type: text/plain\r\n\r\nSee you at 20:30.\r\n"
            ),
            9,
        )
    };
    let mut client = Client::open(&cfg).await.unwrap();
    client
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let row = store
        .lock()
        .unwrap()
        .unified(Folder::Inbox, None, 50)
        .unwrap()
        .into_iter()
        .find(|m| m.subject == "Plan for Friday")
        .unwrap();
    let e = store
        .lock()
        .unwrap()
        .envelope(account, &row.mailbox, row.uid)
        .unwrap()
        .unwrap();
    let emails = |l: &[Address]| l.iter().map(|a| a.email.clone()).collect::<Vec<_>>();
    assert_eq!(emails(&e.reply_to), ["desk@x.it", "bo@x.it"]);
    assert_eq!(emails(&e.to), [USER, "carla@x.it"]);
    assert_eq!(emails(&e.cc), ["dan@x.it"]);
    assert_eq!(emails(&e.followup_to), ["team@x.it", "carla@x.it"]);
    let own = store.lock().unwrap().own_addresses(account).unwrap();
    let from = Address::new("Anna", "anna@x.it");
    let one = reply_recipients(&e, &from, &own, ReplyMode::Sender);
    assert_eq!(emails(&one.to), ["desk@x.it", "bo@x.it"]);
    let all = reply_recipients(&e, &from, &own, ReplyMode::All);
    assert_eq!(emails(&all.to), ["team@x.it", "carla@x.it"]);

    // Redirect, from an alias: the raw message from the server, resent
    // unchanged through the outbox, from the alias's identity.
    let mut remote = Remote::Jmap(client);
    let raw = remote
        .raw(&store, account, &row.mailbox, row.uid)
        .await
        .unwrap();
    assert_eq!(raw, server.lock().unwrap().emails[&id].raw);
    let to = vec!["Rossi, Mario <eve@x.it>".to_owned()];
    let own = vec![USER.to_owned(), ALIAS.to_owned()];
    let (draft, ready) = envelope::redirect(
        &raw,
        "Plan for Friday",
        Some(ALIAS),
        &own,
        &to,
        1_790_000_000,
    )
    .unwrap();
    let out = piuma_core::outbox::Outgoing {
        account,
        draft,
        ready,
        saved: None,
        send_at: None,
        undo: false,
        redirect: false,
    };
    let queued = store.lock().unwrap().queue_outgoing(&out, 0).unwrap();
    let account = store.lock().unwrap().account(account).unwrap().unwrap();
    let outcome = piuma_core::outbox::send_one(
        &store,
        queued,
        &mut piuma_core::remote::AccountCourier::new(&account, PASSWORD),
        "test",
    )
    .await
    .unwrap();
    assert!(
        matches!(outcome, piuma_core::outbox::Outcome::Sent(_)),
        "{outcome:?}"
    );
    {
        let s = server.lock().unwrap();
        let (email, rcpt) = s.sent.last().unwrap();
        assert_eq!(rcpt, &["eve@x.it".to_owned()]);
        assert_eq!(
            s.senders.last().unwrap(),
            &("alias".to_owned(), ALIAS.to_owned())
        );
        let sent = String::from_utf8_lossy(&s.emails[email].raw).into_owned();
        assert!(
            sent.starts_with(&format!("Resent-From: {ALIAS}\r\n")),
            "{sent}"
        );
        assert!(sent.contains("Resent-To: eve@x.it\r\n"), "{sent}");
        assert!(sent.contains("From: Anna <anna@x.it>\r\n"), "{sent}");
        assert!(sent.contains("Message-ID: <plan@x.it>\r\n"), "{sent}");
    }

    // From an alias the server has no identity for: the login's identity
    // sends it, with the envelope from that identity's address (the alias
    // would be forbiddenMailFrom); Resent-From still names the alias.
    let shop = "shop@example.com";
    let own = vec![USER.to_owned(), ALIAS.to_owned(), shop.to_owned()];
    let (draft, ready) = envelope::redirect(
        &raw,
        "Plan for Friday",
        Some(shop),
        &own,
        &to,
        1_790_000_100,
    )
    .unwrap();
    assert_eq!(ready.from, shop);
    let out = piuma_core::outbox::Outgoing {
        account: account.id,
        draft,
        ready,
        saved: None,
        send_at: None,
        undo: false,
        redirect: true,
    };
    let queued = store.lock().unwrap().queue_outgoing(&out, 0).unwrap();
    let outcome = piuma_core::outbox::send_one(
        &store,
        queued,
        &mut piuma_core::remote::AccountCourier::new(&account, PASSWORD),
        "test",
    )
    .await
    .unwrap();
    assert!(
        matches!(outcome, piuma_core::outbox::Outcome::Sent(_)),
        "{outcome:?}"
    );
    let s = server.lock().unwrap();
    assert_eq!(
        s.senders.last().unwrap(),
        &("me".to_owned(), USER.to_owned())
    );
    let (email, _) = s.sent.last().unwrap();
    let sent = String::from_utf8_lossy(&s.emails[email].raw).into_owned();
    assert!(
        sent.starts_with(&format!("Resent-From: {shop}\r\n")),
        "{sent}"
    );
}

/// Sends a redirect of a small message from `from` through the outbox, and
/// gives the identity and MAIL FROM the server saw.
async fn redirect_from(
    server: &Arc<Mutex<Server>>,
    cfg: &JmapConfig,
    from: &str,
    at: i64,
) -> (String, String) {
    use piuma_core::envelope;
    let (store, account) = store_with_account(cfg);
    let raw = b"From: Anna <anna@x.it>\r\nTo: team@x.it\r\nSubject: Hi\r\n\
                Message-ID: <hi@x.it>\r\nContent-Type: text/plain\r\n\r\nHi.\r\n";
    let own = vec![USER.to_owned(), from.to_owned()];
    let to = vec!["eve@x.it".to_owned()];
    let (draft, ready) = envelope::redirect(raw, "Hi", Some(from), &own, &to, at).unwrap();
    assert_eq!(ready.from, from);
    let out = piuma_core::outbox::Outgoing {
        account,
        draft,
        ready,
        saved: None,
        send_at: None,
        undo: false,
        redirect: true,
    };
    let queued = store.lock().unwrap().queue_outgoing(&out, 0).unwrap();
    let account = store.lock().unwrap().account(account).unwrap().unwrap();
    let outcome = piuma_core::outbox::send_one(
        &store,
        queued,
        &mut piuma_core::remote::AccountCourier::new(&account, PASSWORD),
        "test",
    )
    .await
    .unwrap();
    assert!(
        matches!(outcome, piuma_core::outbox::Outcome::Sent(_)),
        "{outcome:?}"
    );
    server.lock().unwrap().senders.last().unwrap().clone()
}

#[tokio::test]
async fn sends_through_a_wildcard_identity() {
    let (server, cfg) = start().await;
    // The login is covered only by a wildcard identity for its domain;
    // another identity has an address of its own, elsewhere.
    server.lock().unwrap().identities = Some(vec![
        ("other".into(), "someone@example.org".into()),
        ("wild".into(), "*@example.com".into()),
    ]);
    // An alias the wildcard covers: it sends, and the envelope keeps the
    // alias as it is.
    assert_eq!(
        redirect_from(&server, &cfg, ALIAS, 1_790_000_000).await,
        ("wild".to_owned(), ALIAS.to_owned())
    );
    // An address no identity covers: the login's identity, the wildcard,
    // sends it, with the envelope from the login (the wildcard has no
    // address of its own).
    assert_eq!(
        redirect_from(&server, &cfg, "shop@elsewhere.net", 1_790_000_100).await,
        ("wild".to_owned(), USER.to_owned())
    );
}

#[tokio::test]
async fn hears_about_new_mail_without_asking() {
    let (server, cfg) = start().await;
    let mut client = Client::open(&cfg).await.unwrap();
    // Nothing happens: the wait runs out.
    assert!(!client
        .wait_for_change(Duration::from_millis(300))
        .await
        .unwrap());
    let later = server.clone();
    tokio::spawn(async move {
        tokio::time::sleep(Duration::from_millis(200)).await;
        later
            .lock()
            .unwrap()
            .add("mb-in", "Ana <ana@example.org>", "Hi", 9, false);
    });
    assert!(client
        .wait_for_change(Duration::from_secs(5))
        .await
        .unwrap());
}

#[tokio::test]
async fn finds_a_session_from_the_well_known_address() {
    let (_, cfg) = start().await;
    let well_known = cfg
        .session_url
        .replace("/jmap/session", "/.well-known/jmap");
    assert_eq!(
        discover_at(&well_known).await,
        Some(cfg.session_url.clone())
    );
    let nothing = cfg.session_url.replace("/jmap/session", "/nothing");
    assert_eq!(discover_at(&nothing).await, None);
}

#[tokio::test]
async fn sorts_older_mail_and_lists_files_and_cards() {
    let (server, cfg) = start().await;
    let path = std::env::temp_dir().join(format!("piuma-jmap-{}.db", std::process::id()));
    let (store, account) = with_account(Store::open(&path).unwrap(), &cfg);
    let (news, invoice, files) = {
        let mut s = server.lock().unwrap();
        let news = s.add_raw(
            "mb-in",
            "From: Weekly <hello@weekly.example>\r\nSubject: Issue 12\r\n\
             List-Unsubscribe: <https://weekly.example/u>\r\nMessage-ID: <n12@weekly.example>\r\n\
             Content-Type: text/plain\r\n\r\nThis week.\r\n",
            6,
        );
        let invoice = s.add_raw(
            "mb-in",
            "From: Power Co <bills@power.example>\r\nSubject: Your invoice for October\r\n\
             Message-ID: <i10@power.example>\r\nContent-Type: text/plain\r\n\r\n\
             Amount due: EUR 42.00 by 30 October 2026.\r\n",
            7,
        );
        let files = s.add_raw(
            "mb-in",
            "From: Ana <ana@example.org>\r\nSubject: The lease\r\nMessage-ID: <l1@example.org>\r\n\
             Content-Type: multipart/mixed; boundary=x\r\n\r\n\
             --x\r\nContent-Type: multipart/related; boundary=y\r\n\r\n\
             --y\r\nContent-Type: text/html\r\n\r\n<p>Here <img src=\"cid:logo\"></p>\r\n\
             --y\r\nContent-Type: image/png\r\nContent-ID: <logo>\r\n\
             Content-Transfer-Encoding: base64\r\n\r\niVBORw0KGgo=\r\n--y--\r\n\
             --x\r\nContent-Type: application/pdf; name=lease.pdf\r\n\
             Content-Disposition: attachment; filename=lease.pdf\r\n\
             Content-Transfer-Encoding: base64\r\n\r\nJVBERi0xLjQK\r\n--x--\r\n",
            8,
        );
        (news, invoice, files)
    };
    let mut client = Client::open(&cfg).await.unwrap();

    // A first look, from a server that keeps the list headers back, like
    // mail cached by an earlier version. Bills and files are found anyway.
    let first = client
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert!(subjects(&store, Folder::Inbox).contains(&"Issue 12".to_owned()));
    assert_eq!((first.carded, first.listed), (1, 1));

    // Mail cached before list headers were read is marked for a look.
    rusqlite::Connection::open(&path)
        .unwrap()
        .execute("UPDATE message SET list_checked = 0", [])
        .unwrap();
    server.lock().unwrap().headers = true;
    let report = client
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert_eq!(report.filed, 1);
    assert_eq!(subjects(&store, Folder::Newsletters), ["Issue 12"]);

    let listed = {
        let s = store.lock().unwrap();
        let uid = |id: &str| {
            (1..20)
                .find(|&u| s.jmap_id(account, "INBOX", u).unwrap().as_deref() == Some(id))
                .unwrap()
        };
        assert!(s.full_body(account, "INBOX", uid(&news)).unwrap().is_some());
        assert!(s
            .full_body(account, "INBOX", uid(&invoice))
            .unwrap()
            .is_some());
        let listed = s.files(Some(account), 10).unwrap();
        assert_eq!(listed.len(), 1, "the inline logo is not a file");
        let (message, _, pdf) = &listed[0];
        assert_eq!(message.uid, uid(&files));
        assert_eq!(
            (pdf.name.as_str(), pdf.mime.as_str()),
            ("lease.pdf", "application/pdf")
        );
        listed
    };

    // A listed file comes down alone, decoded.
    let data = client
        .blob(listed[0].2.section.as_deref().unwrap())
        .await
        .unwrap();
    assert_eq!(data, b"%PDF-1.4\n");
    drop(store);
    for end in ["", "-wal", "-shm"] {
        std::fs::remove_file(format!("{}{end}", path.display())).ok();
    }
}

fn me(name: &str, kind: &str) -> Me {
    let secret = Key::generate();
    Me {
        device: Device {
            id: space::new_device_id(),
            name: name.into(),
            kind: kind.into(),
            last_seen: 0,
            public: space::public_key(&secret),
        },
        secret,
    }
}

#[tokio::test]
async fn keeps_the_sync_space_in_a_hidden_folder() {
    let (state, cfg) = start().await;
    let (mac_store, account) = store_with_account(&cfg);
    mac_store
        .lock()
        .unwrap()
        .set_setting("notify.mode", "all")
        .unwrap();
    let pw = || vec![(USER.to_owned(), PASSWORD.to_owned())];
    let mac = me("Matteo's MacBook", "laptop");
    let mut mac_jmap = Remote::Jmap(Client::open(&cfg).await.unwrap());
    let recovery = space_sync::create(&mut mac_jmap, USER, &mac_store, pw(), &mac)
        .await
        .unwrap();
    assert_eq!(recovery.phrase().split(' ').count(), 24);

    // The folder is made once, and stays out of the account's folders.
    let (mut client, (phone_store, _)) =
        (Client::open(&cfg).await.unwrap(), store_with_account(&cfg));
    client.sync_folders(&mac_store, account).await.unwrap();
    let folders = mac_store.lock().unwrap().account_folders(account).unwrap();
    assert_eq!(
        folders.iter().map(|f| f.name.as_str()).collect::<Vec<_>>(),
        ["Receipts"]
    );
    assert_eq!(
        state
            .lock()
            .unwrap()
            .mailboxes
            .iter()
            .filter(|m| m.1 == space::FOLDER)
            .count(),
        1
    );

    // A phone pairs with a code.
    let phone = me("Pixel 8", "phone");
    let mut phone_jmap = Remote::Jmap(Client::open(&cfg).await.unwrap());
    assert!(space_sync::found(&mut phone_jmap).await.unwrap());
    let code = space::pair_code();
    let pairing = space_sync::request(&mut phone_jmap, USER, &code, &phone)
        .await
        .unwrap();
    let waiting = space_sync::requests(&mut mac_jmap).await.unwrap();
    assert_eq!(waiting.len(), 1);
    space_sync::approve_waiting(&mut mac_jmap, USER, &waiting[0].id, &code, &mac)
        .await
        .unwrap();
    let (space, _) = space_sync::join(
        &mut phone_jmap,
        USER,
        pairing,
        &phone_store,
        &phone,
        Duration::from_millis(50),
    )
    .await
    .unwrap();
    assert_eq!(space.content.devices.len(), 2);
    assert_eq!(
        phone_store
            .lock()
            .unwrap()
            .setting("notify.mode")
            .unwrap()
            .as_deref(),
        Some("all")
    );
    assert!(space_sync::requests(&mut mac_jmap)
        .await
        .unwrap()
        .is_empty());

    // A change on the Mac reaches the phone, and only one copy of the
    // space stays behind.
    let mac_space = space_sync::open(&mut mac_jmap, &mac).await.unwrap();
    let mac_seen = space_sync::seen(&mac_store, pw(), &mac, &mac_space).unwrap();
    let phone_seen = space_sync::seen(&phone_store, pw(), &phone, &space).unwrap();
    mac_store
        .lock()
        .unwrap()
        .set_setting("notify.mode", "people")
        .unwrap();
    let Round::Pushed(..) =
        space_sync::round(&mut mac_jmap, USER, &mac_store, pw(), &mac, &mac_seen)
            .await
            .unwrap()
    else {
        panic!("the Mac should push");
    };
    let Round::Took(..) = space_sync::round(
        &mut phone_jmap,
        USER,
        &phone_store,
        pw(),
        &phone,
        &phone_seen,
    )
    .await
    .unwrap() else {
        panic!("the phone should take");
    };
    assert_eq!(
        phone_store
            .lock()
            .unwrap()
            .setting("notify.mode")
            .unwrap()
            .as_deref(),
        Some("people")
    );
    let s = state.lock().unwrap();
    let folder = &s.mailboxes.iter().find(|m| m.1 == space::FOLDER).unwrap().0;
    assert_eq!(
        s.emails
            .values()
            .filter(|e| e.mailboxes.contains(folder))
            .count(),
        1
    );
}

#[tokio::test]
async fn labels_are_keywords_on_the_server() {
    let (server, cfg) = start().await;
    let (store, account) = store_with_account(&cfg);
    let mut client = Client::open(&cfg).await.unwrap();
    server
        .lock()
        .unwrap()
        .emails
        .get_mut("M4")
        .unwrap()
        .keywords
        .insert("invoices".into());
    client
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    let rows = store
        .lock()
        .unwrap()
        .unified(Folder::Inbox, None, 50)
        .unwrap();
    let (lunch, m4) = (rows[0].uid, rows[1].uid);
    assert_eq!(
        store
            .lock()
            .unwrap()
            .message_labels(account, "INBOX", m4)
            .unwrap(),
        ["invoices"]
    );

    let worksite = store.lock().unwrap().add_label("Worksite", "").unwrap();
    client
        .set_keyword(&store, account, "INBOX", &[lunch], &worksite.keyword, true)
        .await
        .unwrap();
    assert!(server.lock().unwrap().emails["M5"]
        .keywords
        .contains("worksite"));
    // Taken off elsewhere: the next sync takes it off here.
    server
        .lock()
        .unwrap()
        .emails
        .get_mut("M5")
        .unwrap()
        .keywords
        .remove("worksite");
    {
        let s = store.lock().unwrap();
        s.label_message(account, "INBOX", lunch, &worksite.keyword, true)
            .unwrap();
        // Sent already, as above.
        let sent: Vec<i64> = s
            .pending_changes(account)
            .unwrap()
            .iter()
            .map(|p| p.id)
            .collect();
        s.drop_changes(&sent).unwrap();
    }
    client
        .sync_mailbox(&store, account, "INBOX", |_, _| {})
        .await
        .unwrap();
    assert!(store
        .lock()
        .unwrap()
        .message_labels(account, "INBOX", lunch)
        .unwrap()
        .is_empty());
}

#[tokio::test]
async fn keeps_the_away_message_on_the_server() {
    use piuma_core::away::{self, AwayMessage, AwayServer, Outcome};
    let (state, cfg) = start().await;
    let server = AwayServer::Jmap(cfg.clone());
    // Without the capability there is no away message to set.
    assert_eq!(away::status(&server, 60).await.unwrap(), None);

    state.lock().unwrap().vacation = Some(json!({
        "id": "singleton", "isEnabled": false, "fromDate": null, "toDate": null,
        "subject": null, "textBody": null, "htmlBody": null,
    }));
    let status = away::status(&server, 60).await.unwrap().unwrap();
    assert!(status.dates);
    assert!(!status.placed);
    assert!(!status.message.unwrap().on);

    let day = |s: &str| away::parse_iso(s).unwrap();
    let m = AwayMessage {
        on: true,
        start: Some(day("2026-10-27")),
        end: Some(day("2026-11-02")),
        subject: "Away until 3 November".into(),
        body: "Hi, I'm away.".into(),
    };
    let (outcome, dates) = away::apply(&server, &m, &[], 60, day("2026-10-21"))
        .await
        .unwrap();
    assert_eq!(outcome, Outcome::Placed);
    assert!(dates);
    {
        let s = state.lock().unwrap();
        let v = s.vacation.as_ref().unwrap();
        assert_eq!(v["isEnabled"], true);
        // Midnight in Rome, in UTC; the reply stops when the 3rd begins.
        assert_eq!(v["fromDate"], "2026-10-26T23:00:00Z");
        assert_eq!(v["toDate"], "2026-11-02T23:00:00Z");
        assert_eq!(v["subject"], "Away until 3 November");
        assert_eq!(v["textBody"], "Hi, I'm away.");
    }
    let status = away::status(&server, 60).await.unwrap().unwrap();
    assert_eq!(status.message, Some(m.clone()));
    assert!(status.placed);

    let off = AwayMessage { on: false, ..m };
    let (outcome, _) = away::apply(&server, &off, &[], 60, day("2026-10-28"))
        .await
        .unwrap();
    assert_eq!(outcome, Outcome::Removed);
    assert_eq!(
        state.lock().unwrap().vacation.as_ref().unwrap()["isEnabled"],
        false
    );
}

#[tokio::test]
async fn the_sync_space_moves_to_another_mailbox() {
    let (old_state, old_cfg) = start().await;
    let (new_state, new_cfg) = start().await;
    const OTHER: &str = "matteo@work.example";
    let (mac_store, _) = store_with_account(&old_cfg);
    let (phone_store, _) = store_with_account(&old_cfg);
    let pw = || vec![(USER.to_owned(), PASSWORD.to_owned())];
    let (mac, phone) = (me("Matteo's MacBook", "laptop"), me("Pixel 8", "phone"));
    let mut mac_old = Remote::Jmap(Client::open(&old_cfg).await.unwrap());
    let recovery = space_sync::create(&mut mac_old, USER, &mac_store, pw(), &mac)
        .await
        .unwrap();
    let mut phone_old = Remote::Jmap(Client::open(&old_cfg).await.unwrap());
    let (space, _) = space_sync::recover(
        &mut phone_old,
        USER,
        &recovery.phrase(),
        &phone_store,
        &phone,
    )
    .await
    .unwrap();
    let phone_seen = space_sync::seen(&phone_store, pw(), &phone, &space).unwrap();

    // The Mac moves it: same devices, no pairing again.
    let mut mac_new = Remote::Jmap(Client::open(&new_cfg).await.unwrap());
    let moved = space_sync::relocate(&mut mac_old, USER, &mut mac_new, OTHER, &mac)
        .await
        .unwrap();
    assert_eq!(moved.content.devices.len(), 2);
    assert!(space_sync::found(&mut mac_new).await.unwrap());
    assert!(!space_sync::found(&mut mac_old).await.unwrap());

    // The phone finds the note and follows; there it opens the space.
    let Round::Moved(to) = space_sync::round(
        &mut phone_old,
        USER,
        &phone_store,
        pw(),
        &phone,
        &phone_seen,
    )
    .await
    .unwrap() else {
        panic!("the phone should be told where the space went");
    };
    assert_eq!(to, OTHER);
    let mut phone_new = Remote::Jmap(Client::open(&new_cfg).await.unwrap());
    let Round::Same(..) = space_sync::round(
        &mut phone_new,
        OTHER,
        &phone_store,
        pw(),
        &phone,
        &phone_seen,
    )
    .await
    .unwrap() else {
        panic!("nothing changed, so nothing to do");
    };

    // The old folder keeps only the note; the new one the space.
    for (state, left) in [(old_state, 1), (new_state, 1)] {
        let s = state.lock().unwrap();
        let folder = &s.mailboxes.iter().find(|m| m.1 == space::FOLDER).unwrap().0;
        assert_eq!(
            s.emails
                .values()
                .filter(|e| e.mailboxes.contains(folder))
                .count(),
            left
        );
    }

    // Moving back clears that note.
    space_sync::relocate(&mut mac_new, OTHER, &mut mac_old, USER, &mac)
        .await
        .unwrap();
    assert!(space_sync::found(&mut mac_old).await.unwrap());
    let Round::Same(..) = space_sync::round(
        &mut phone_old,
        USER,
        &phone_store,
        pw(),
        &phone,
        &phone_seen,
    )
    .await
    .unwrap() else {
        panic!("back home, the phone reads it again");
    };
}

#[tokio::test]
async fn a_phone_pairs_by_scanning_the_invite() {
    let (_state, cfg) = start().await;
    let (mac_store, _) = store_with_account(&cfg);
    let (phone_store, _) = store_with_account(&cfg);
    let pw = || vec![(USER.to_owned(), PASSWORD.to_owned())];
    let mac = me("Matteo's MacBook", "laptop");
    let mut mac_jmap = Remote::Jmap(Client::open(&cfg).await.unwrap());
    space_sync::create(&mut mac_jmap, USER, &mac_store, pw(), &mac)
        .await
        .unwrap();

    // The Mac shows an invite, then a newer one (the panel opened anew);
    // the phone scanned the first and asks with its code.
    let code = piuma_core::pair_qr::invite_code();
    let newer = piuma_core::pair_qr::invite_code();
    let codes = [code.clone(), newer];
    let phone = me("Pixel 8", "phone");
    let mut phone_jmap = Remote::Jmap(Client::open(&cfg).await.unwrap());
    let pairing = space_sync::request_qr(&mut phone_jmap, USER, &code, &phone)
        .await
        .unwrap();
    // Nobody is asked for digits.
    assert!(space_sync::requests(&mut mac_jmap)
        .await
        .unwrap()
        .is_empty());
    let answered = space_sync::answer_invite(&mut mac_jmap, USER, &codes, &mac)
        .await
        .unwrap();
    assert_eq!(answered, ["Pixel 8"]);
    let (space, _) = space_sync::join(
        &mut phone_jmap,
        USER,
        pairing,
        &phone_store,
        &phone,
        Duration::from_millis(50),
    )
    .await
    .unwrap();
    assert_eq!(space.content.devices.len(), 2);

    // Someone who copies the invite's tag but has not the code gets an
    // answer they can't open.
    let stranger = me("Unknown", "phone");
    let mut s_jmap = Remote::Jmap(Client::open(&cfg).await.unwrap());
    let mut guess = space::pair_start("111111111111111111111111", &stranger.device);
    guess.request.invite = Some(space::invite_tag(&code));
    s_jmap
        .space_put(&space::Note::Request(guess.request.clone()).to_message(USER, space::now()))
        .await
        .unwrap();
    space_sync::answer_invite(&mut mac_jmap, USER, &codes, &mac)
        .await
        .unwrap();
    let (s_store, _) = store_with_account(&cfg);
    assert!(space_sync::join(
        &mut s_jmap,
        USER,
        guess,
        &s_store,
        &stranger,
        Duration::from_millis(50),
    )
    .await
    .is_err());
}

/// Managing the mailbox over JMAP: stars, copies, deleting for good in
/// Trash, Empty Trash, folders renamed, hidden and deleted, a folder of
/// the person's choice for a job, and quota.
#[tokio::test]
async fn manages_the_mailbox() {
    let (server, cfg) = start().await;
    {
        let mut s = server.lock().unwrap();
        s.mailboxes
            .push(("mb-trash".into(), "Trash".into(), Some("trash".into())));
        s.mailboxes.push(("mb-old".into(), "Old".into(), None));
        s.mailboxes.push(("mb-sub".into(), "2026".into(), None));
        s.mailboxes.push(("mb-bin".into(), "Bin".into(), None));
        s.parents.insert("mb-sub".into(), "mb-misc".into());
        s.unsubscribed.insert("mb-old".into());
        s.add("mb-trash", "Ana <ana@example.org>", "Old news", 1, true);
        s.add("mb-trash", "Ana <ana@example.org>", "Older news", 1, true);
        s.add("mb-sub", "Leo <leo@example.org>", "Plans", 1, true);
        s.quota = Some((900, 1000));
    }
    let (store, account) = store_with_account(&cfg);
    let mut remote = Remote::Jmap(Client::open(&cfg).await.unwrap());
    remote.sync_folders(&store, account).await.unwrap();
    remote.sync_mailbox(&store, account, "INBOX").await.unwrap();
    remote
        .sync_mailbox(&store, account, "mb-trash")
        .await
        .unwrap();
    {
        let s = store.lock().unwrap();
        assert_eq!(
            s.trash_mailbox(account).unwrap().as_deref(),
            Some("mb-trash")
        );
        let folders: Vec<(String, u32, bool)> = s
            .account_folders(account)
            .unwrap()
            .into_iter()
            .map(|f| (f.mailbox, f.depth, f.subscribed))
            .collect();
        assert!(folders.contains(&("mb-old".into(), 0, false)));
        assert!(folders.contains(&("mb-sub".into(), 1, true)));
    }
    let lunch = store
        .lock()
        .unwrap()
        .unified(Folder::Inbox, None, 1)
        .unwrap()[0]
        .uid;
    let trashed: Vec<u32> = store.lock().unwrap().uids(account, "mb-trash").unwrap();
    {
        let s = store.lock().unwrap();
        s.queue_flags(&[(account, "INBOX".into(), lunch)], true)
            .unwrap();
        s.queue_change(
            account,
            "INBOX",
            lunch,
            piuma_core::pending::Change::CopyTo("mb-misc".into()),
        )
        .unwrap();
        s.queue_erase(account, "mb-trash", &trashed[..1]).unwrap();
        s.rename_folder(account, "mb-misc", "Paperwork").unwrap();
        s.subscribe_folder(account, "mb-old", true).unwrap();
    }
    assert_eq!(remote.send_pending(&store, account).await.unwrap(), 0);
    {
        let s = server.lock().unwrap();
        let lunch = &s.emails["M5"];
        assert!(lunch.keywords.contains("$flagged"));
        // One email, now in two folders.
        assert!(lunch.mailboxes.contains("mb-in") && lunch.mailboxes.contains("mb-misc"));
        assert_eq!(
            s.emails
                .values()
                .filter(|e| e.mailboxes.contains("mb-trash"))
                .count(),
            1
        );
        assert!(s
            .mailboxes
            .iter()
            .any(|(id, name, _)| id == "mb-misc" && name == "Paperwork"));
        assert!(!s.unsubscribed.contains("mb-old"));
    }
    // JMAP names folders by id: the rename keeps every name here.
    assert_eq!(
        store
            .lock()
            .unwrap()
            .account_folder(account, "mb-misc")
            .unwrap()
            .unwrap()
            .name,
        "Paperwork"
    );
    assert!(store
        .lock()
        .unwrap()
        .pending_changes(account)
        .unwrap()
        .is_empty());

    // Deleted with its subfolder: their email goes to Trash first.
    assert!(store
        .lock()
        .unwrap()
        .delete_folder(account, "mb-misc")
        .unwrap()
        .is_some());
    assert_eq!(remote.send_pending(&store, account).await.unwrap(), 0);
    {
        let s = server.lock().unwrap();
        assert!(!s
            .mailboxes
            .iter()
            .any(|(id, _, _)| id == "mb-misc" || id == "mb-sub"));
        // Plans goes to Trash; the copy of Lunch only leaves the folder,
        // as it is in the inbox too.
        assert_eq!(
            s.emails
                .values()
                .filter(|e| e.mailboxes.contains("mb-trash"))
                .count(),
            2
        );
        assert_eq!(s.emails["M5"].mailboxes, ["mb-in".to_owned()].into());
    }

    // Empty Trash keeps to what was counted: mail that came after stays.
    let (n, upto) = remote.count("mb-trash").await.unwrap();
    assert_eq!(n, 2);
    let late = server
        .lock()
        .unwrap()
        .add("mb-trash", "Ana <ana@example.org>", "Late", 3, true);
    assert_eq!(
        remote
            .empty(&store, account, "mb-trash", &upto)
            .await
            .unwrap(),
        2
    );
    {
        let s = server.lock().unwrap();
        let left: Vec<&String> = s
            .emails
            .iter()
            .filter(|(_, e)| e.mailboxes.contains("mb-trash"))
            .map(|(id, _)| id)
            .collect();
        assert_eq!(left, [&late]);
    }

    // Counted with the server out of reach: only what is here goes, and
    // Late isn't here yet, so it stays (re-check finding 1).
    let here = Snapshot::here(&store, account, "mb-trash").unwrap();
    remote
        .empty(&store, account, "mb-trash", &here)
        .await
        .unwrap();
    assert!(server.lock().unwrap().emails.contains_key(&late));

    // A move to Trash of mail already there does nothing: deleting for
    // good is only ever asked for by name.
    remote
        .sync_mailbox(&store, account, "mb-trash")
        .await
        .unwrap();
    let again = store.lock().unwrap().uids(account, "mb-trash").unwrap();
    remote
        .move_messages(&store, account, "mb-trash", &again, FolderRole::Trash)
        .await
        .unwrap();
    assert!(server.lock().unwrap().emails.contains_key(&late));

    // A folder of the person's choice for Trash.
    store
        .lock()
        .unwrap()
        .set_role_choice(account, FolderRole::Trash, Some("mb-bin"))
        .unwrap();
    remote.sync_folders(&store, account).await.unwrap();
    {
        let s = store.lock().unwrap();
        assert_eq!(s.trash_mailbox(account).unwrap().as_deref(), Some("mb-bin"));
        assert!(s.account_folder(account, "mb-bin").unwrap().is_none());
    }
    remote
        .move_messages(&store, account, "INBOX", &[lunch], FolderRole::Trash)
        .await
        .unwrap();
    assert!(server.lock().unwrap().emails["M5"]
        .mailboxes
        .contains("mb-bin"));

    assert_eq!(remote.quota().await.unwrap(), Some((900, 1000)));
}

/// Deleting for good an email that is in another folder too only takes it
/// out of Trash (review finding 5); a folder holding the folder chosen as
/// Trash is refused for good, not tried again for a day (finding 3).
#[tokio::test]
async fn deleting_keeps_what_lives_elsewhere_and_trash_itself() {
    let (server, cfg) = start().await;
    let both = {
        let mut s = server.lock().unwrap();
        s.mailboxes
            .push(("mb-trash".into(), "Trash".into(), Some("trash".into())));
        s.mailboxes.push(("mb-bin".into(), "Bin".into(), None));
        s.parents.insert("mb-bin".into(), "mb-misc".into());
        let id = s.add("mb-trash", "Ana <ana@example.org>", "Both", 1, true);
        s.emails
            .get_mut(&id)
            .unwrap()
            .mailboxes
            .insert("mb-in".into());
        id
    };
    let (store, account) = store_with_account(&cfg);
    let mut remote = Remote::Jmap(Client::open(&cfg).await.unwrap());
    remote.sync_folders(&store, account).await.unwrap();
    remote
        .sync_mailbox(&store, account, "mb-trash")
        .await
        .unwrap();
    let uids = store.lock().unwrap().uids(account, "mb-trash").unwrap();
    store
        .lock()
        .unwrap()
        .queue_erase(account, "mb-trash", &uids)
        .unwrap();
    assert_eq!(remote.send_pending(&store, account).await.unwrap(), 0);
    assert_eq!(
        server.lock().unwrap().emails[&both].mailboxes,
        ["mb-in".to_owned()].into()
    );

    // Bin, inside Receipts, becomes Trash.
    store
        .lock()
        .unwrap()
        .set_role_choice(account, FolderRole::Trash, Some("mb-bin"))
        .unwrap();
    remote.sync_folders(&store, account).await.unwrap();
    {
        let s = store.lock().unwrap();
        assert!(s.protected_inside(account, "mb-misc").unwrap().is_some());
        assert_eq!(s.delete_folder(account, "mb-misc").unwrap(), None);
        s.queue_change(
            account,
            "mb-misc",
            0,
            piuma_core::pending::Change::Folder(piuma_core::pending::FolderChange::Delete),
        )
        .unwrap();
    }
    let mut dropped = 0;
    for _ in 0..piuma_core::pending::REFUSED_ATTEMPTS {
        dropped += remote.send_pending(&store, account).await.unwrap();
        store.lock().unwrap().retry_changes_now(account).unwrap();
    }
    assert_eq!(dropped, 1);
    let s = server.lock().unwrap();
    assert!(s.mailboxes.iter().any(|(id, _, _)| id == "mb-misc"));
    assert!(s.mailboxes.iter().any(|(id, _, _)| id == "mb-bin"));
}
