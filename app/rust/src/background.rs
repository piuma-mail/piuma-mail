//! Android's background service (`AndroidBackground`): the engine keeps
//! running with no app on screen, and the service shows the notices
//! itself. Its Kotlin side waits on [`wait`] in a thread of its own; the
//! JNI wrappers are in `android.rs`, so this file builds and tests
//! everywhere.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Condvar, Mutex};
use std::time::Duration;

use piuma_core::outbox;
use piuma_core::remote::Remote;
use piuma_core::{AccountId, Store};

use crate::api::engine::{self, MailNotice};
use crate::credentials;

/// Whether the service shows the notices.
static ON: AtomicBool = AtomicBool::new(false);
static QUEUE: Mutex<Vec<MailNotice>> = Mutex::new(Vec::new());
static ARRIVED: Condvar = Condvar::new();
/// Accounts whose server refused the password, for [`sign_in_notices`].
static FAILED: Mutex<Vec<SignInNotice>> = Mutex::new(Vec::new());

/// "Tell me when it can't sign in", with the app closed: one notice the
/// first time an account's password is refused, until it signs in again.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SignInNotice {
    pub account_id: i64,
    pub name: String,
    pub cancelled: bool,
}

/// From now on notices wait for [`wait`] instead of going to the app.
pub fn enable() {
    ON.store(true, Ordering::SeqCst);
}

pub fn enabled() -> bool {
    ON.load(Ordering::SeqCst)
}

/// Keeps notices for the service, while it is on.
pub(crate) fn push(notices: &[MailNotice]) {
    if !enabled() || notices.is_empty() {
        return;
    }
    QUEUE
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .extend_from_slice(notices);
    ARRIVED.notify_all();
}

/// The notices that came since the last call, waiting at most `timeout`
/// for one; empty when none came.
pub fn wait(timeout: Duration) -> Vec<MailNotice> {
    let queue = QUEUE.lock().unwrap_or_else(|e| e.into_inner());
    let (mut queue, _) = ARRIVED
        .wait_timeout_while(queue, timeout, |q| {
            q.is_empty() && FAILED.lock().unwrap_or_else(|e| e.into_inner()).is_empty()
        })
        .unwrap_or_else(|e| e.into_inner());
    std::mem::take(&mut *queue)
}

/// Where an account is marked as told, so the notice comes once even
/// when Android starts the process again. Kept on this device.
fn told_key(account: AccountId) -> String {
    format!("sign_in.told.{}", account.0)
}

/// The account's server refused its password: keeps a notice for the
/// service, unless the app shows its own, the person turned it off, or
/// it was given already.
pub(crate) fn sign_in_failed(account: AccountId) {
    if enabled() {
        tell(account);
    }
}

fn tell(account: AccountId) {
    let Ok(engine) = engine::engine() else { return };
    let store = engine.store.lock().unwrap_or_else(|e| e.into_inner());
    let notice = told(&store, account);
    let Some(notice) = notice else { return };
    FAILED
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .push(notice);
    drop(store);
    // Taken while wait() looks, so the wake-up isn't lost.
    drop(QUEUE.lock().unwrap_or_else(|e| e.into_inner()));
    ARRIVED.notify_all();
}

/// The notice to give for an account that can't sign in, marking it as
/// given; None when it's turned off or was given already.
fn told(store: &Store, account: AccountId) -> Option<SignInNotice> {
    // As `sign_in_alert`: on unless turned off.
    let alert = store
        .setting(&format!("account.{}.sign_in_alert", account.0))
        .ok()
        .flatten();
    if alert.as_deref() == Some("off") || is_told(store, account) {
        return None;
    }
    let a = store
        .accounts()
        .ok()?
        .into_iter()
        .find(|a| a.id == account)?;
    store.set_setting(&told_key(account), "1").ok()?;
    Some(SignInNotice {
        account_id: account.0,
        name: a.name,
        cancelled: false,
    })
}

fn is_told(store: &Store, account: AccountId) -> bool {
    store
        .setting(&told_key(account))
        .ok()
        .flatten()
        .is_some_and(|v| !v.is_empty())
}

/// The account reached its server again: the next refusal is told anew.
pub(crate) fn signed_in(account: AccountId) {
    let Ok(engine) = engine::engine() else { return };
    let store = engine.store.lock().unwrap_or_else(|e| e.into_inner());
    let mut failed = FAILED.lock().unwrap_or_else(|e| e.into_inner());
    recover_sign_in(&store, account, &mut failed);
    drop(failed);
    drop(store);
    drop(QUEUE.lock().unwrap_or_else(|e| e.into_inner()));
    ARRIVED.notify_all();
}

fn recover_sign_in(store: &Store, account: AccountId, pending: &mut Vec<SignInNotice>) {
    if is_told(store, account) {
        store.set_setting(&told_key(account), "").ok();
        // Replace an undelivered failure, or withdraw a notice already posted.
        pending.retain(|n| n.account_id != account.0);
        pending.push(SignInNotice {
            account_id: account.0,
            name: String::new(),
            cancelled: true,
        });
    }
}

/// The sign-in notices kept since the last call, as JSON: each with the
/// notification's id, the account's name and the payload that opens its
/// details.
pub fn sign_in_notices() -> String {
    let failed = std::mem::take(&mut *FAILED.lock().unwrap_or_else(|e| e.into_inner()));
    let items: Vec<String> = failed
        .iter()
        .map(|n| {
            if n.cancelled {
                return format!(r#"{{"id":{},"cancel":true}}"#, sign_in_id(n.account_id));
            }
            format!(
                r#"{{"id":{},"name":{},"payload":{}}}"#,
                sign_in_id(n.account_id),
                quote(&n.name),
                quote(&format!("account\n{}", n.account_id)),
            )
        })
        .collect();
    format!("[{}]", items.join(","))
}

/// One notification per account, apart from its mail's.
fn sign_in_id(account_id: i64) -> i32 {
    let mut hash: u32 = 0x811c_9dc5;
    for b in format!("sign-in\n{account_id}").bytes() {
        hash ^= u32::from(b);
        hash = hash.wrapping_mul(0x0100_0193);
    }
    ((hash & 0x7fff_ffff) | 2) as i32
}

/// Opens the engine on its database. Returns every account's id, to hand
/// their passwords to [`start`].
pub fn open(db_path: &str) -> Result<Vec<i64>, engine::EngineError> {
    engine::open_engine(db_path.to_owned())?;
    Ok(engine::accounts()?.into_iter().map(|a| a.id).collect())
}

/// Follows every account, as the app does, with the notices for the
/// service. Safe to call when the app already follows them.
pub fn start(passwords: &[(i64, String)]) -> Result<(), engine::EngineError> {
    remember(passwords);
    enable();
    let accounts = engine::engine()?
        .store
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .accounts()?;
    for account in accounts {
        engine::watch_account(account)?;
    }
    Ok(())
}

/// One look at every inbox, for "Every 15 minutes": new mail, and the
/// outbox. Accounts already followed are left alone. Returns the notices.
pub fn check_once(passwords: &[(i64, String)]) -> Result<Vec<MailNotice>, engine::EngineError> {
    remember(passwords);
    let engine = engine::engine()?;
    let accounts = engine
        .store
        .lock()
        .unwrap_or_else(|e| e.into_inner())
        .accounts()?;
    let mut notices = Vec::new();
    for account in accounts {
        let followed = engine::WATCHED
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .contains(&account.id.0);
        let Ok(password) = credentials::load(account.id) else {
            continue;
        };
        if followed {
            continue;
        }
        let store = engine.store.clone();
        let arrived = engine.runtime.block_on(async {
            outbox::send(&store, &account, &password).await.ok();
            let mut conn = match Remote::open(&account, &password).await {
                Ok(conn) => conn,
                Err(e) => {
                    if e.is_auth() {
                        tell(account.id);
                    }
                    return None;
                }
            };
            signed_in(account.id);
            let report = conn.sync_mailbox(&store, account.id, "INBOX").await.ok();
            conn.close().await;
            report.map(|r| r.arrived)
        });
        if let Some(arrived) = arrived {
            notices.extend(engine::notices_for(&arrived, &engine.store));
        }
    }
    Ok(notices)
}

/// What a button on a notice asks for (`Notifications`): the message is
/// the notice's payload, "account\nmailbox\nuid".
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum NoticeAction {
    Archive,
    /// Until this time, in Unix seconds.
    Snooze(i64),
    /// A short reply typed on the notice, sent from the message's account.
    Reply(String),
}

pub(crate) fn message_of(payload: &str) -> Option<engine::MessageRef> {
    let mut parts = payload.splitn(3, '\n');
    let account_id = parts.next()?.parse().ok()?;
    let mailbox = parts.next()?.to_owned();
    let uid = parts.next()?.parse().ok()?;
    Some(engine::MessageRef {
        account_id,
        mailbox,
        uid,
    })
}

/// "Re: " before a subject that doesn't have it yet.
fn reply_subject(subject: &str) -> String {
    if subject.trim_start().to_lowercase().starts_with("re:") {
        subject.to_owned()
    } else {
        format!("Re: {subject}")
    }
}

/// Does what a notice's button asks, as the app would: the message is
/// read, then archived, snoozed or answered. A server that can't be
/// reached gets it later, from the pending queue or the outbox.
pub fn act(payload: &str, action: NoticeAction) -> Result<(), engine::EngineError> {
    let bad = || engine::EngineError::new(engine::ErrorKind::Other, "unknown message");
    let message = message_of(payload).ok_or_else(bad)?;
    let engine = engine::engine()?;
    engine::set_messages_seen(vec![message.clone()], true)?;
    engine
        .runtime
        .block_on(engine::push_messages_seen(vec![message.clone()], true))
        .ok();
    match action {
        NoticeAction::Archive => engine.runtime.block_on(engine::apply_message_action(
            vec![message],
            engine::MessageAction::Archive,
        )),
        NoticeAction::Snooze(until) => {
            engine
                .runtime
                .block_on(engine::snooze_messages(vec![message], until, false))
        }
        NoticeAction::Reply(text) => {
            let (row, signature) = {
                let store = engine.store.lock().unwrap_or_else(|e| e.into_inner());
                let account = AccountId(message.account_id);
                let row = store
                    .message(account, &message.mailbox, message.uid)?
                    .ok_or_else(bad)?;
                let signature = store
                    .signatures()?
                    .into_iter()
                    .find(|s| s.account == account && s.for_replies)
                    .map(|s| s.id);
                (row, signature)
            };
            let to = if row.reply.reply_to.is_empty() {
                row.from_email.clone()
            } else {
                row.reply.reply_to.clone()
            };
            let mut references: Vec<String> = row
                .reply
                .references
                .split_whitespace()
                .map(str::to_owned)
                .collect();
            let in_reply_to = (!row.reply.message_id.is_empty()).then(|| {
                references.push(row.reply.message_id.clone());
                row.reply.message_id.clone()
            });
            engine
                .runtime
                .block_on(engine::send_message(engine::OutgoingMessage {
                    account_id: message.account_id,
                    from_email: crate::api::groups::reply_from(
                        message.account_id,
                        message.mailbox.clone(),
                        message.uid,
                    )
                    .ok()
                    .flatten(),
                    files: Vec::new(),
                    to: vec![to],
                    cc: Vec::new(),
                    bcc: Vec::new(),
                    subject: reply_subject(&row.subject),
                    body: text,
                    in_reply_to,
                    references,
                    signature_id: signature,
                    signature_picked: false,
                    draft: None,
                    remind_at: None,
                    marks: Vec::new(),
                }))
                .map(|_| ())
        }
    }
}

/// Android's passwords come from its Keystore, by way of the service;
/// elsewhere the engine reads the system keychain itself.
fn remember(passwords: &[(i64, String)]) {
    #[cfg(target_os = "android")]
    for (id, password) in passwords {
        credentials::remember(AccountId(*id), password);
    }
    #[cfg(not(target_os = "android"))]
    let _ = passwords;
}

/// Notices as the service reads them: a JSON array, each with the
/// notification's id, who and what, the payload the app opens, and
/// whether it is silent (see [`quiet`]).
pub fn to_json(notices: &[MailNotice]) -> String {
    let items: Vec<String> = notices
        .iter()
        .map(|n| {
            let vault = n.reminder.as_ref().map_or(String::new(), |r| {
                format!(
                    r#","vault":{{"dueIn":{},"merchant":{},"title":{},"time":{},"amount":{},"currency":{}}}"#,
                    r.due_in.map_or(-1, i64::from),
                    quote(&r.merchant),
                    quote(&r.title),
                    quote(&r.time),
                    r.amount.unwrap_or(-1),
                    quote(&r.currency),
                )
            });
            let away = n.away.as_ref().map_or(String::new(), |a| {
                let names: Vec<String> = a.names.iter().map(|n| quote(n)).collect();
                format!(
                    r#","away":{{"emails":{},"people":{},"names":[{}]}}"#,
                    a.emails,
                    a.people,
                    names.join(",")
                )
            });
            let no_reply = n.no_reply.as_ref().map_or(String::new(), |r| {
                format!(r#","noReply":{{"sentDaysAgo":{}}}"#, r.sent_days_ago)
            });
            format!(
                r#"{{"id":{},"sender":{},"count":{},"subject":{},"preview":{},"payload":{},"silent":{}{}{}{}}}"#,
                notice_id(n),
                quote(&n.sender),
                n.count,
                quote(&n.subject),
                quote(&n.preview),
                quote(&if n.away.is_some() {
                    // Opens the inbox.
                    "inbox".to_owned()
                } else {
                    format!("{}\n{}\n{}", n.account_id, n.mailbox, n.uid)
                }),
                n.silent,
                vault,
                away,
                no_reply
            )
        })
        .collect();
    format!("[{}]", items.join(","))
}

/// `notices` as the quiet hours leave them at `week_minute` (minutes
/// since Monday 00:00, local time); unchanged if the engine can't say.
pub fn quiet(notices: Vec<MailNotice>, week_minute: u16) -> Vec<MailNotice> {
    engine::quiet_notices(notices.clone(), week_minute).unwrap_or(notices)
}

/// One notification per sender and account: a newer one replaces it;
/// a Vault notice, one per card; a reminder, one per sent email; "While
/// you were away", always the same.
fn notice_id(n: &MailNotice) -> i32 {
    let key = match &n.reminder {
        Some(r) => format!("vault\n{}", r.key),
        None if n.away.is_some() => "away".to_owned(),
        None if n.no_reply.is_some() => {
            format!("no-reply\n{}\n{}\n{}", n.account_id, n.mailbox, n.uid)
        }
        None => format!("{}\n{}", n.account_id, n.sender_email.to_lowercase()),
    };
    // FNV-1a: stable across runs, unlike the std hasher.
    let mut hash: u32 = 0x811c_9dc5;
    for b in key.bytes() {
        hash ^= u32::from(b);
        hash = hash.wrapping_mul(0x0100_0193);
    }
    // Id 1 is the service's own notice.
    ((hash & 0x7fff_ffff) | 2) as i32
}

/// A JSON string.
pub(crate) fn quote(s: &str) -> String {
    let mut out = String::with_capacity(s.len() + 2);
    out.push('"');
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            '\r' => out.push_str("\\r"),
            '\t' => out.push_str("\\t"),
            c if (c as u32) < 0x20 => out.push_str(&format!("\\u{:04x}", c as u32)),
            c => out.push(c),
        }
    }
    out.push('"');
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    fn notice(sender_email: &str, subject: &str) -> MailNotice {
        MailNotice {
            account_id: 2,
            mailbox: "INBOX".into(),
            uid: 41,
            sender: "Sara \"S\" Conti".into(),
            sender_email: sender_email.into(),
            subject: subject.into(),
            preview: "Line one\nline two".into(),
            count: 2,
            reminder: None,
            people: true,
            silent: false,
            away: None,
            no_reply: None,
        }
    }

    #[test]
    fn a_notice_payload_names_its_message() {
        let m = message_of("2\nINBOX/Work\n41").unwrap();
        assert_eq!(
            (m.account_id, m.mailbox.as_str(), m.uid),
            (2, "INBOX/Work", 41)
        );
        assert!(message_of("2\nINBOX").is_none());
        assert!(message_of("x\nINBOX\n1").is_none());
        assert_eq!(reply_subject("Dinner on Friday?"), "Re: Dinner on Friday?");
        assert_eq!(reply_subject("RE: Quote"), "RE: Quote");
    }

    #[test]
    fn notices_wait_for_the_service_only_once_it_is_on() {
        push(&[notice("sara@studio.it", "Off")]);
        assert!(wait(Duration::from_millis(10)).is_empty());
        enable();
        push(&[notice("sara@studio.it", "On")]);
        let got = wait(Duration::from_millis(10));
        assert_eq!(got.len(), 1);
        assert_eq!(got[0].subject, "On");
        assert!(wait(Duration::from_millis(10)).is_empty());
    }

    #[test]
    fn json_escapes_and_keeps_one_id_per_sender() {
        let a = notice("Sara@Studio.it", "Quote \\ “print”");
        let b = notice("sara@studio.it", "Other");
        assert_eq!(notice_id(&a), notice_id(&b));
        assert_ne!(notice_id(&a), notice_id(&notice("luca@studio.it", "x")));
        assert!(notice_id(&a) > 1);
        let json = to_json(&[a]);
        assert!(json.starts_with(r#"[{"id":"#));
        assert!(json.contains(r#""sender":"Sara \"S\" Conti""#));
        assert!(json.contains(r#""subject":"Quote \\ “print”""#));
        assert!(json.contains(r#""preview":"Line one\nline two""#));
        assert!(json.contains(r#""payload":"2\nINBOX\n41""#));
        assert!(json.contains(r#""count":2"#));
        assert!(json.ends_with(r#""silent":false}]"#));
    }

    #[test]
    fn a_vault_notice_carries_its_card() {
        let mut n = notice("", "Desk lamp");
        n.reminder = Some(engine::VaultReminder {
            due_in: None,
            merchant: "Corriere Rapido".into(),
            title: "Desk lamp".into(),
            time: "10:00".into(),
            amount: None,
            currency: String::new(),
            key: "TRK123".into(),
        });
        let json = to_json(std::slice::from_ref(&n));
        assert!(json.contains(
            r#""vault":{"dueIn":-1,"merchant":"Corriere Rapido","title":"Desk lamp","time":"10:00","amount":-1,"currency":""}}]"#
        ));
        assert_ne!(notice_id(&n), notice_id(&notice("", "Desk lamp")));
    }

    #[test]
    fn a_reminder_says_how_long_it_has_waited() {
        let mut n = notice("", "Quote for the Acme site");
        n.sender = "Luca".into();
        n.no_reply = Some(engine::NoReplyInfo { sent_days_ago: 3 });
        let json = to_json(std::slice::from_ref(&n));
        assert!(json.ends_with(r#""silent":false,"noReply":{"sentDaysAgo":3}}]"#));
        assert_ne!(
            notice_id(&n),
            notice_id(&notice("", "Quote for the Acme site"))
        );
    }

    #[test]
    fn while_you_were_away_names_who_wrote() {
        let mut n = notice("", "");
        n.silent = true;
        n.away = Some(engine::AwayInfo {
            emails: 12,
            people: 3,
            names: vec!["Sara Conti".into(), "Dad".into()],
        });
        let json = to_json(std::slice::from_ref(&n));
        assert!(json.contains(r#""silent":true"#));
        assert!(json.contains(r#""away":{"emails":12,"people":3,"names":["Sara Conti","Dad"]}}]"#));
        let mut other = notice("x@y.it", "");
        other.away = n.away.clone();
        assert_eq!(notice_id(&n), notice_id(&other));
    }

    #[test]
    fn a_refused_password_is_told_once_until_it_signs_in() {
        let store = Store::open_in_memory().unwrap();
        let id = store
            .add_account(&piuma_core::Account {
                id: AccountId(0),
                name: "Work \"W\"".into(),
                email: "matteo@studio.it".into(),
                sender_name: "Matteo".into(),
                color: "#3451D1".into(),
                kind: piuma_core::AccountKind::Jmap {
                    session_url: "https://jmap.studio.it/session".into(),
                    username: "matteo".into(),
                },
            })
            .unwrap();
        let notice = told(&store, id).unwrap();
        assert_eq!(notice.name, "Work \"W\"");
        assert_eq!(told(&store, id), None);
        let other = SignInNotice {
            account_id: id.0 + 1,
            name: "Other".into(),
            cancelled: false,
        };
        let mut pending = vec![notice.clone(), other.clone()];
        recover_sign_in(&store, id, &mut pending);
        assert_eq!(pending[0], other);
        assert_eq!(pending[1].account_id, id.0);
        assert!(pending[1].cancelled);
        assert!(!is_told(&store, id));
        recover_sign_in(&store, id, &mut pending);
        assert_eq!(pending.len(), 2); // Repeated success is quiet.
        assert!(told(&store, id).is_some()); // A genuine new refusal still alerts.
        let mut delivered = Vec::new();
        recover_sign_in(&store, id, &mut delivered);
        // Withdraw even after the queue was drained.
        assert!(delivered[0].cancelled);
        // Signed in again, then refused again.
        store.set_setting(&told_key(id), "").unwrap();
        assert!(told(&store, id).is_some());
        store.set_setting(&told_key(id), "").unwrap();
        store
            .set_setting(&format!("account.{}.sign_in_alert", id.0), "off")
            .unwrap();
        assert_eq!(told(&store, id), None);

        FAILED.lock().unwrap().push(notice);
        // Waiting wakes for it, with no mail.
        assert!(wait(Duration::from_secs(5)).is_empty());
        let json = sign_in_notices();
        assert_eq!(
            json,
            format!(
                r#"[{{"id":{},"name":"Work \"W\"","payload":"account\n{}"}}]"#,
                sign_in_id(id.0),
                id.0
            )
        );
        assert_ne!(sign_in_id(id.0), sign_in_id(id.0 + 1));
        assert_eq!(sign_in_notices(), "[]");
        FAILED.lock().unwrap().extend(delivered);
        assert_eq!(
            sign_in_notices(),
            format!(r#"[{{"id":{},"cancel":true}}]"#, sign_in_id(id.0))
        );
        assert_eq!(sign_in_notices(), "[]");
    }
}
