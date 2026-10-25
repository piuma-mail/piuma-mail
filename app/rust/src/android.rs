//! Android start-up: `MainActivity` hands the engine the app context before
//! Flutter starts. Crates that ask Android for system settings through JNI,
//! such as the DNS resolver reading the phone's DNS servers, find it with
//! `ndk_context` and panic without it.

use std::sync::Once;
use std::time::Duration;

use jni::errors::{Error, ThrowRuntimeExAndDefault};
use jni::jni_mangle;
use jni::objects::{JClass, JObject, JString};
use jni::sys::{jboolean, jint, jlong};
use jni::{Env, EnvUnowned};
use piuma_core::AccountId;

static INIT: Once = Once::new();

#[jni_mangle("mail.piuma.piuma_mail.MainActivity")]
pub fn init<'caller>(
    mut unowned_env: EnvUnowned<'caller>,
    _class: JClass<'caller>,
    context: JObject<'caller>,
) {
    unowned_env
        .with_env(|env| init_context(env, &context))
        .resolve::<ThrowRuntimeExAndDefault>();
}

fn init_context(env: &mut Env<'_>, context: &JObject<'_>) -> Result<(), Error> {
    if INIT.is_completed() {
        return Ok(());
    }
    let vm = env.get_java_vm()?;
    // The global reference is never freed: the context is used for the
    // whole life of the process.
    let context = std::mem::ManuallyDrop::new(env.new_global_ref(context)?);
    INIT.call_once(|| unsafe {
        ndk_context::initialize_android_context(vm.get_raw().cast(), context.as_raw().cast());
    });
    Ok(())
}

// The background service (`MailNative.kt`). Failures come back as empty
// strings: the service stays quiet rather than crash.

/// Opens the engine on `db_path`; returns the accounts' ids, comma
/// separated, or "" when it can't.
#[jni_mangle("mail.piuma.piuma_mail.MailNative")]
pub fn open<'caller>(
    mut unowned_env: EnvUnowned<'caller>,
    _class: JClass<'caller>,
    context: JObject<'caller>,
    db_path: JString<'caller>,
) -> JString<'caller> {
    unowned_env
        .with_env(|env| -> Result<_, Error> {
            init_context(env, &context)?;
            let path = db_path.try_to_string(env)?;
            let ids = crate::background::open(&path).unwrap_or_default();
            let ids: Vec<String> = ids.iter().map(ToString::to_string).collect();
            JString::from_str(env, ids.join(","))
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

/// Hands over one account's password, from the Android Keystore.
#[jni_mangle("mail.piuma.piuma_mail.MailNative")]
pub fn remember<'caller>(
    mut unowned_env: EnvUnowned<'caller>,
    _class: JClass<'caller>,
    account_id: jlong,
    password: JString<'caller>,
) {
    unowned_env
        .with_env(|env| -> Result<(), Error> {
            crate::credentials::remember(AccountId(account_id), &password.try_to_string(env)?);
            Ok(())
        })
        .resolve::<ThrowRuntimeExAndDefault>();
}

/// Follows every account, with the notices for the service.
#[jni_mangle("mail.piuma.piuma_mail.MailNative")]
pub fn start<'caller>(mut unowned_env: EnvUnowned<'caller>, _class: JClass<'caller>) {
    unowned_env
        .with_env(|_env| -> Result<(), Error> {
            crate::background::start(&[]).ok();
            Ok(())
        })
        .resolve::<ThrowRuntimeExAndDefault>();
}

/// The notices that came, as JSON, waiting at most `timeout_ms` for one.
/// `minute` is the local time in minutes since Monday 00:00, for the
/// quiet hours.
#[jni_mangle("mail.piuma.piuma_mail.MailNative")]
pub fn next<'caller>(
    mut unowned_env: EnvUnowned<'caller>,
    _class: JClass<'caller>,
    minute: jint,
    timeout_ms: jlong,
) -> JString<'caller> {
    unowned_env
        .with_env(|env| -> Result<_, Error> {
            let notices = crate::background::wait(Duration::from_millis(timeout_ms.max(0) as u64));
            let notices = crate::background::quiet(notices, minute as u16);
            JString::from_str(env, crate::background::to_json(&notices))
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

/// One look at every inbox, for "Every 15 minutes"; the notices as JSON.
#[jni_mangle("mail.piuma.piuma_mail.MailNative")]
pub fn check_once<'caller>(
    mut unowned_env: EnvUnowned<'caller>,
    _class: JClass<'caller>,
    minute: jint,
) -> JString<'caller> {
    unowned_env
        .with_env(|env| -> Result<_, Error> {
            let notices = crate::background::check_once(&[]).unwrap_or_default();
            let notices = crate::background::quiet(notices, minute as u16);
            JString::from_str(env, crate::background::to_json(&notices))
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

/// The device moved to another network: the watchers start over on it.
#[jni_mangle("mail.piuma.piuma_mail.MailNative")]
pub fn network_changed<'caller>(_unowned_env: EnvUnowned<'caller>, _class: JClass<'caller>) {
    piuma_core::network::changed();
}

/// A button on a notice: "archive", "snooze" (until `until`, Unix
/// seconds) or "reply" with `text`. False when it could not be done.
#[jni_mangle("mail.piuma.piuma_mail.MailNative")]
pub fn act<'caller>(
    mut unowned_env: EnvUnowned<'caller>,
    _class: JClass<'caller>,
    payload: JString<'caller>,
    action: JString<'caller>,
    until: jlong,
    text: JString<'caller>,
) -> jboolean {
    unowned_env
        .with_env(|env| -> Result<_, Error> {
            use crate::background::NoticeAction;
            let payload = payload.try_to_string(env)?;
            let action = match action.try_to_string(env)?.as_str() {
                "archive" => NoticeAction::Archive,
                "snooze" => NoticeAction::Snooze(until),
                "reply" => NoticeAction::Reply(text.try_to_string(env)?),
                _ => return Ok(false),
            };
            Ok(crate::background::act(&payload, action).is_ok())
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

/// The Vault notices due now, and "While you were away" once quiet hours
/// end, as JSON like [next]'s; `offset_minutes` is
/// the local time zone, east of UTC.
#[jni_mangle("mail.piuma.piuma_mail.MailNative")]
pub fn reminders<'caller>(
    mut unowned_env: EnvUnowned<'caller>,
    _class: JClass<'caller>,
    offset_minutes: jint,
    minute: jint,
) -> JString<'caller> {
    unowned_env
        .with_env(|env| -> Result<_, Error> {
            let notices = crate::api::engine::vault_reminders(offset_minutes).unwrap_or_default();
            let notices = crate::background::quiet(notices, minute as u16);
            JString::from_str(env, crate::background::to_json(&notices))
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}

/// The accounts that can't sign in, as JSON, each told once.
#[jni_mangle("mail.piuma.piuma_mail.MailNative")]
pub fn sign_in_notices<'caller>(
    mut unowned_env: EnvUnowned<'caller>,
    _class: JClass<'caller>,
) -> JString<'caller> {
    unowned_env
        .with_env(|env| -> Result<_, Error> {
            JString::from_str(env, crate::background::sign_in_notices())
        })
        .resolve::<ThrowRuntimeExAndDefault>()
}
