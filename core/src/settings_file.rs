//! Settings in a file, to set up Piuma on another computer or keep a
//! copy: the accounts' servers, usernames and names, the signatures and
//! the appearance. Never a password, token or key: those stay in the
//! system keychain, and an imported account asks for its sign-in again.
//!
//! The file is JSON with a format name and a version. A newer version
//! than this one reads is refused rather than half understood. Read back,
//! the file is untrusted: sizes are capped, unknown values fall back to
//! the defaults, and an account's settings only fill the add-account form,
//! where the person sees them before anything connects.

use base64::Engine as _;
use serde::{Deserialize, Serialize};

use crate::model::{AccountId, AccountKind, Security, Server};
use crate::signature::{Accent, Signature, Template};
use crate::store::{Store, StoreError};

/// What the file says it is.
pub const FORMAT: &str = "piuma-settings";
/// The version written, and the newest read.
pub const VERSION: u32 = 1;
/// The largest settings file read.
pub const FILE_MAX: u64 = 4 * 1024 * 1024;
/// Most accounts or signatures read from one file.
const ITEMS_MAX: usize = 100;
/// Longest text value kept.
const TEXT_MAX: usize = 2_000;

#[derive(Debug, thiserror::Error)]
pub enum SettingsFileError {
    #[error("the file is not a Piuma settings file")]
    NotSettings,
    #[error("the file was made by a newer Piuma (version {0})")]
    Newer(u32),
    #[error("the file is too large")]
    TooLarge,
    #[error(transparent)]
    Store(#[from] StoreError),
}

/// The whole file.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SettingsFile {
    pub format: String,
    pub version: u32,
    #[serde(default)]
    pub accounts: Vec<AccountSettings>,
    #[serde(default)]
    pub signatures: Vec<SignatureSettings>,
    #[serde(default)]
    pub appearance: Option<Appearance>,
}

/// One account, without its password.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct AccountSettings {
    pub email: String,
    /// What the account is called in the app.
    #[serde(default)]
    pub name: String,
    /// The person's name in From.
    #[serde(default)]
    pub sender_name: String,
    #[serde(default)]
    pub color: String,
    /// `imap` or `jmap`.
    pub kind: String,
    #[serde(default)]
    pub username: String,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub imap: Option<ServerSettings>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub smtp: Option<ServerSettings>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub jmap_url: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ServerSettings {
    pub host: String,
    pub port: u16,
    /// `tls` or `starttls`.
    pub security: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SignatureSettings {
    /// The address of the account it belongs to.
    pub account: String,
    #[serde(default)]
    pub label: String,
    #[serde(default)]
    pub template: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub role: String,
    #[serde(default)]
    pub company: String,
    #[serde(default)]
    pub phone: String,
    #[serde(default)]
    pub website: String,
    #[serde(default)]
    pub accent: String,
    /// The logo, base64.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub logo: Option<String>,
    #[serde(default)]
    pub for_new: bool,
    #[serde(default)]
    pub for_replies: bool,
}

/// Settings › Appearance, as the setting keys hold it.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Appearance {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub theme: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub compact: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub preview_lines: Option<u8>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub translate_into: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub open_original: Option<bool>,
}

const THEME: &str = "appearance.theme";
const COMPACT: &str = "appearance.compact";
const PREVIEW_LINES: &str = "appearance.preview_lines";
const TRANSLATE_INTO: &str = "appearance.translate_into";
const LANGUAGE: &str = "appearance.language";
const OPEN_IN: &str = "appearance.open_in";

fn text(s: &str) -> String {
    s.chars()
        .filter(|c| {
            !c.is_control() && !matches!(c, '\u{202A}'..='\u{202E}' | '\u{2066}'..='\u{2069}')
        })
        .take(TEXT_MAX)
        .collect::<String>()
        .trim()
        .to_owned()
}

/// A language code as the app keeps them: two or three letters.
fn language(s: &str) -> Option<String> {
    let s = s.trim().to_ascii_lowercase();
    (2..=3)
        .contains(&s.len())
        .then_some(())
        .and(s.bytes().all(|b| b.is_ascii_lowercase()).then_some(s))
}

fn server(s: &Server) -> ServerSettings {
    ServerSettings {
        host: s.host.clone(),
        port: s.port,
        security: s.security.tag().to_owned(),
    }
}

/// Everything there is to write, from the store.
pub fn collect(store: &Store) -> Result<SettingsFile, StoreError> {
    let accounts = store.accounts()?;
    let email_of = |id: AccountId| {
        accounts
            .iter()
            .find(|a| a.id == id)
            .map(|a| a.email.clone())
    };
    let setting = |k: &str| store.setting(k).ok().flatten().filter(|v| !v.is_empty());
    Ok(SettingsFile {
        format: FORMAT.into(),
        version: VERSION,
        accounts: accounts
            .iter()
            .map(|a| match &a.kind {
                AccountKind::Imap {
                    imap,
                    smtp,
                    username,
                } => AccountSettings {
                    email: a.email.clone(),
                    name: a.name.clone(),
                    sender_name: a.sender_name.clone(),
                    color: a.color.clone(),
                    kind: "imap".into(),
                    username: username.clone(),
                    imap: Some(server(imap)),
                    smtp: Some(server(smtp)),
                    jmap_url: None,
                },
                AccountKind::Jmap {
                    session_url,
                    username,
                } => AccountSettings {
                    email: a.email.clone(),
                    name: a.name.clone(),
                    sender_name: a.sender_name.clone(),
                    color: a.color.clone(),
                    kind: "jmap".into(),
                    username: username.clone(),
                    imap: None,
                    smtp: None,
                    jmap_url: Some(session_url.clone()),
                },
            })
            .collect(),
        signatures: store
            .signatures()?
            .into_iter()
            .filter_map(|s| {
                Some(SignatureSettings {
                    account: email_of(s.account)?,
                    label: s.label,
                    template: s.template.tag().into(),
                    name: s.name,
                    role: s.role,
                    company: s.company,
                    phone: s.phone,
                    website: s.website,
                    accent: s.accent.tag().into(),
                    logo: s
                        .logo
                        .map(|l| base64::engine::general_purpose::STANDARD.encode(l.data)),
                    for_new: s.for_new,
                    for_replies: s.for_replies,
                })
            })
            .collect(),
        appearance: Some(Appearance {
            theme: setting(THEME),
            compact: setting(COMPACT).map(|v| v == "true"),
            preview_lines: setting(PREVIEW_LINES).and_then(|v| v.parse().ok()),
            translate_into: setting(TRANSLATE_INTO),
            language: setting(LANGUAGE),
            open_original: setting(OPEN_IN).map(|v| v == "original"),
        }),
    })
}

/// The file's text: pretty JSON.
pub fn write(file: &SettingsFile) -> String {
    serde_json::to_string_pretty(file).unwrap_or_default()
}

/// Reads a settings file's bytes, cleaned: unknown kinds and servers
/// without a host are left out, values are trimmed and capped.
pub fn read(data: &[u8]) -> Result<SettingsFile, SettingsFileError> {
    if data.len() as u64 > FILE_MAX {
        return Err(SettingsFileError::TooLarge);
    }
    let mut file: SettingsFile =
        serde_json::from_slice(data).map_err(|_| SettingsFileError::NotSettings)?;
    if file.format != FORMAT {
        return Err(SettingsFileError::NotSettings);
    }
    if file.version > VERSION {
        return Err(SettingsFileError::Newer(file.version));
    }
    let clean_server = |s: Option<ServerSettings>| {
        s.map(|s| ServerSettings {
            host: text(&s.host)
                .chars()
                .filter(|c| !c.is_whitespace())
                .collect(),
            port: s.port,
            // Never plain text from a file: the form starts encrypted.
            security: if s.security == "starttls" {
                "starttls".into()
            } else {
                "tls".into()
            },
        })
        .filter(|s| !s.host.is_empty() && s.port != 0)
    };
    file.accounts = file
        .accounts
        .into_iter()
        .take(ITEMS_MAX)
        .filter_map(|a| {
            let email = text(&a.email);
            if !email.contains('@') {
                return None;
            }
            let base = AccountSettings {
                email,
                name: text(&a.name),
                sender_name: text(&a.sender_name),
                color: Some(text(&a.color))
                    .filter(|c| {
                        c.len() == 7
                            && c.starts_with('#')
                            && c[1..].bytes().all(|b| b.is_ascii_hexdigit())
                    })
                    .unwrap_or_default(),
                kind: a.kind.clone(),
                username: text(&a.username),
                imap: None,
                smtp: None,
                jmap_url: None,
            };
            match a.kind.as_str() {
                "imap" => Some(AccountSettings {
                    imap: clean_server(a.imap),
                    smtp: clean_server(a.smtp),
                    ..base
                }),
                "jmap" => Some(AccountSettings {
                    jmap_url: a
                        .jmap_url
                        .map(|u| text(&u))
                        .filter(|u| u.starts_with("https://")),
                    ..base
                }),
                _ => None,
            }
        })
        .collect();
    file.signatures = file
        .signatures
        .into_iter()
        .take(ITEMS_MAX)
        .map(|s| SignatureSettings {
            account: text(&s.account),
            label: text(&s.label),
            template: Template::from_tag(&s.template).tag().into(),
            name: text(&s.name),
            role: text(&s.role),
            company: text(&s.company),
            phone: text(&s.phone),
            website: text(&s.website),
            accent: Accent::from_tag(&s.accent).tag().into(),
            logo: s.logo,
            for_new: s.for_new,
            for_replies: s.for_replies,
        })
        .collect();
    file.appearance = file.appearance.map(|a| Appearance {
        theme: a
            .theme
            .filter(|t| matches!(t.as_str(), "light" | "dark" | "automatic")),
        compact: a.compact,
        preview_lines: a.preview_lines.filter(|n| matches!(n, 1 | 2)),
        translate_into: a.translate_into.as_deref().and_then(language),
        language: a.language.as_deref().and_then(language),
        open_original: a.open_original,
    });
    Ok(file)
}

/// Puts the file's appearance into the store.
pub fn apply_appearance(store: &Store, a: &Appearance) -> Result<(), StoreError> {
    if let Some(t) = &a.theme {
        store.set_setting(THEME, t)?;
    }
    if let Some(c) = a.compact {
        store.set_setting(COMPACT, if c { "true" } else { "false" })?;
    }
    if let Some(n) = a.preview_lines {
        store.set_setting(PREVIEW_LINES, &n.to_string())?;
    }
    if let Some(l) = &a.translate_into {
        store.set_setting(TRANSLATE_INTO, l)?;
    }
    if let Some(l) = &a.language {
        store.set_setting(LANGUAGE, l)?;
    }
    if let Some(o) = a.open_original {
        store.set_setting(OPEN_IN, if o { "original" } else { "clean" })?;
    }
    Ok(())
}

/// Adds the file's signatures of the accounts this device has, leaving
/// out any whose account already has a signature with that label (so
/// applying the file again changes nothing). Returns how many were added
/// and how many wait for an account not added yet.
pub fn apply_signatures(store: &mut Store, file: &SettingsFile) -> Result<(u32, u32), StoreError> {
    let accounts = store.accounts()?;
    let mut existing = store.signatures()?;
    let (mut added, mut waiting) = (0, 0);
    for s in &file.signatures {
        let Some(account) = accounts
            .iter()
            .find(|a| a.email.eq_ignore_ascii_case(&s.account))
        else {
            waiting += 1;
            continue;
        };
        if existing
            .iter()
            .any(|e| e.account == account.id && e.label == s.label)
        {
            continue;
        }
        let logo = s
            .logo
            .as_deref()
            .and_then(|b| base64::engine::general_purpose::STANDARD.decode(b).ok())
            .and_then(|data| crate::signature::shrink_logo(&data).ok());
        let signature = Signature {
            id: 0,
            account: account.id,
            label: s.label.clone(),
            template: Template::from_tag(&s.template),
            name: s.name.clone(),
            role: s.role.clone(),
            company: s.company.clone(),
            phone: s.phone.clone(),
            website: s.website.clone(),
            accent: Accent::from_tag(&s.accent),
            logo,
            for_new: s.for_new,
            for_replies: s.for_replies,
        };
        let id = store.save_signature(&signature)?;
        existing.push(Signature { id, ..signature });
        added += 1;
    }
    Ok((added, waiting))
}

/// An imported account's servers, for the add-account form.
pub fn security_of(s: &ServerSettings) -> Security {
    Security::from_tag(&s.security)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::Account;

    fn store_with_accounts() -> Store {
        let store = Store::open_in_memory().unwrap();
        store
            .add_account(&Account {
                id: AccountId(0),
                name: "Work".into(),
                email: "me@example.org".into(),
                sender_name: "Matteo Neri".into(),
                color: "#2F8F83".into(),
                kind: AccountKind::Imap {
                    imap: Server {
                        host: "imap.example.org".into(),
                        port: 993,
                        security: Security::Tls,
                    },
                    smtp: Server {
                        host: "smtp.example.org".into(),
                        port: 587,
                        security: Security::StartTls,
                    },
                    username: "me".into(),
                },
            })
            .unwrap();
        store
            .add_account(&Account {
                id: AccountId(0),
                name: "Fastmail".into(),
                email: "me@fastmail.example".into(),
                sender_name: String::new(),
                color: "#C0603C".into(),
                kind: AccountKind::Jmap {
                    session_url: "https://api.fastmail.example/jmap/session".into(),
                    username: "me@fastmail.example".into(),
                },
            })
            .unwrap();
        store
    }

    #[test]
    fn written_and_read_back_without_secrets() {
        let mut store = store_with_accounts();
        let work = store.accounts().unwrap()[0].id;
        store
            .save_signature(&Signature {
                account: work,
                label: "Work".into(),
                name: "Matteo".into(),
                ..Default::default()
            })
            .unwrap();
        store.set_setting(THEME, "dark").unwrap();
        let text = write(&collect(&store).unwrap());
        for secret in ["password", "token", "secret", "refresh"] {
            assert!(!text.to_lowercase().contains(secret), "{secret} in {text}");
        }
        let back = read(text.as_bytes()).unwrap();
        assert_eq!(back.version, VERSION);
        assert_eq!(back.accounts.len(), 2);
        assert_eq!(
            back.accounts[0].imap.as_ref().unwrap().host,
            "imap.example.org"
        );
        assert_eq!(back.accounts[0].smtp.as_ref().unwrap().security, "starttls");
        assert_eq!(
            back.accounts[1].jmap_url.as_deref(),
            Some("https://api.fastmail.example/jmap/session")
        );
        assert_eq!(back.signatures[0].account, "me@example.org");
        assert_eq!(
            back.appearance.as_ref().unwrap().theme.as_deref(),
            Some("dark")
        );

        // On another device: appearance at once, signatures once their
        // account is there, and only once.
        let mut other = Store::open_in_memory().unwrap();
        apply_appearance(&other, back.appearance.as_ref().unwrap()).unwrap();
        assert_eq!(other.setting(THEME).unwrap().as_deref(), Some("dark"));
        assert_eq!(apply_signatures(&mut other, &back).unwrap(), (0, 1));
        let mut other = store_with_accounts();
        assert_eq!(apply_signatures(&mut other, &back).unwrap(), (1, 0));
        assert_eq!(apply_signatures(&mut other, &back).unwrap(), (0, 0));
    }

    #[test]
    fn untrusted_files_are_cleaned_or_refused() {
        assert!(matches!(read(b"{}"), Err(SettingsFileError::NotSettings)));
        assert!(matches!(
            read(b"\x00\xff"),
            Err(SettingsFileError::NotSettings)
        ));
        assert!(matches!(
            read(br#"{"format":"piuma-settings","version":99}"#),
            Err(SettingsFileError::Newer(99))
        ));
        let file = br##"{"format":"piuma-settings","version":1,
          "accounts":[
            {"email":"a@b.c","kind":"imap","color":"red\u202e",
             "imap":{"host":" imap .b.c","port":143,"security":"none"},
             "smtp":{"host":"","port":25,"security":"tls"}},
            {"email":"x@y.z","kind":"jmap","jmap_url":"http://plain.example/jmap"},
            {"email":"nobody","kind":"imap"},
            {"email":"q@r.s","kind":"pop3"}],
          "appearance":{"theme":"neon","preview_lines":9,"language":"../../x"}}"##;
        let f = read(file).unwrap();
        assert_eq!(f.accounts.len(), 2);
        let imap = f.accounts[0].imap.as_ref().unwrap();
        assert_eq!(imap.host, "imap.b.c");
        assert_eq!(imap.security, "tls");
        assert!(f.accounts[0].smtp.is_none());
        assert_eq!(f.accounts[0].color, "");
        assert!(f.accounts[1].jmap_url.is_none());
        let a = f.appearance.unwrap();
        assert!(a.theme.is_none() && a.preview_lines.is_none() && a.language.is_none());
        let big = vec![b' '; FILE_MAX as usize + 1];
        assert!(matches!(read(&big), Err(SettingsFileError::TooLarge)));
    }
}
