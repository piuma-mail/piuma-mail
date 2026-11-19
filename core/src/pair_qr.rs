//! Pairing with a QR code, as on `QrPairToApprove`: a linked device shows
//! an invite, the new phone scans it. The invite names the mailbox that
//! holds the space and how to reach it, so the phone only asks for its
//! password, and carries a long one-time code that stands in for the six
//! digits: the linked device answers a request made with it on its own.
//! No password ever travels in the code.
//!
//! Anyone can print a code, so what it says about servers is only a hint:
//! a code that asks for a connection without encryption is no invite, the
//! address's own known or published settings come first ([resolve]), and
//! the app shows the server before the person types the password.

use url::Url;

use crate::model::{Account, AccountKind, Security, Server};

/// How long an invite shows before a new one takes its place, in seconds:
/// as long as a pairing request lives.
pub const INVITE_TTL: i64 = 5 * 60;

/// Digits in the invite's code: about 80 bits, where the shown code has 6.
const CODE_DIGITS: usize = 24;

/// What a QR code tells the new phone.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Invite {
    /// The address whose mailbox holds the space.
    pub email: String,
    pub kind: AccountKind,
    /// The one-time code, digits only.
    pub code: String,
}

/// A new code for an invite.
pub fn invite_code() -> String {
    let mut b = [0u8; CODE_DIGITS];
    // 250 is the largest multiple of 10 under 256: no digit comes up more.
    let mut digits = String::with_capacity(CODE_DIGITS);
    while digits.len() < CODE_DIGITS {
        getrandom::fill(&mut b).expect("the system has randomness");
        for x in b {
            if x < 250 && digits.len() < CODE_DIGITS {
                digits.push(char::from(b'0' + x % 10));
            }
        }
    }
    digits
}

impl Invite {
    /// The invite for `account`'s mailbox, with a new code.
    pub fn new(account: &Account) -> Self {
        Invite {
            email: account.email.clone(),
            kind: account.kind.clone(),
            code: invite_code(),
        }
    }

    /// As the QR code holds it: `piuma:pair?…`.
    pub fn to_link(&self) -> String {
        let mut url = Url::parse("piuma:pair").expect("a valid base");
        {
            let mut q = url.query_pairs_mut();
            q.append_pair("v", "1").append_pair("a", &self.email);
            match &self.kind {
                AccountKind::Imap {
                    imap,
                    smtp,
                    username,
                } => {
                    q.append_pair("i", &server(imap))
                        .append_pair("o", &server(smtp));
                    if username != &self.email {
                        q.append_pair("u", username);
                    }
                }
                AccountKind::Jmap {
                    session_url,
                    username,
                } => {
                    q.append_pair("j", session_url);
                    if username != &self.email {
                        q.append_pair("u", username);
                    }
                }
            }
            q.append_pair("c", &self.code);
        }
        url.to_string()
    }

    /// Reads a scanned link; None for anything that isn't an invite.
    pub fn from_link(link: &str) -> Option<Self> {
        let url = Url::parse(link.trim()).ok()?;
        if url.scheme() != "piuma" || url.path() != "pair" {
            return None;
        }
        let get = |k: &str| {
            url.query_pairs()
                .find(|(key, _)| key == k)
                .map(|(_, v)| v.into_owned())
        };
        if get("v")? != "1" {
            return None;
        }
        let email = get("a").filter(|a| a.contains('@'))?;
        let code: String = get("c")?.chars().filter(char::is_ascii_digit).collect();
        if code.len() < 12 {
            return None;
        }
        let username = get("u").unwrap_or_else(|| email.clone());
        let kind = match get("j") {
            // Only over HTTPS: the password goes there.
            Some(session_url) if session_url.starts_with("https://") => AccountKind::Jmap {
                session_url,
                username,
            },
            Some(_) => return None,
            None => AccountKind::Imap {
                imap: parse_server(&get("i")?)?,
                smtp: parse_server(&get("o")?)?,
                username,
            },
        };
        Some(Invite { email, kind, code })
    }
}

/// "imap.example.org:993:tls".
fn server(s: &Server) -> String {
    format!("{}:{}:{}", s.host, s.port, s.security.tag())
}

fn parse_server(s: &str) -> Option<Server> {
    let mut parts = s.rsplitn(3, ':');
    let security = parts.next()?;
    let port = parts.next()?.parse().ok()?;
    let host = parts.next()?.to_owned();
    if host.is_empty() {
        return None;
    }
    let security = Security::from_tag(security);
    // The password would cross the network in the clear.
    if security == Security::None {
        return None;
    }
    Some(Server {
        host,
        port,
        security,
    })
}

/// The servers to sign in to with a scanned invite.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Resolved {
    pub kind: AccountKind,
    /// They come from the code itself (the address has no known or
    /// published settings): the person checks the host before signing in.
    pub from_invite: bool,
}

impl Resolved {
    /// The host the password goes to, to show before signing in.
    pub fn host(&self) -> String {
        match &self.kind {
            AccountKind::Imap { imap, .. } => imap.host.clone(),
            AccountKind::Jmap { session_url, .. } => Url::parse(session_url)
                .ok()
                .and_then(|u| u.host_str().map(str::to_owned))
                .unwrap_or_else(|| session_url.clone()),
        }
    }
}

/// Where to sign in for `invite`: the address's known or published
/// settings when there are any, the code's otherwise.
pub async fn resolve(invite: &Invite) -> Resolved {
    if let AccountKind::Imap { .. } = invite.kind {
        let found = match crate::autoconfig::known(&invite.email) {
            Some(s) => Some(s),
            None => crate::autoconfig::discover(&invite.email).await,
        };
        if let Some(s) =
            found.filter(|s| s.imap.security != Security::None && s.smtp.security != Security::None)
        {
            return Resolved {
                kind: AccountKind::Imap {
                    imap: s.imap,
                    smtp: s.smtp,
                    username: s.username,
                },
                from_invite: false,
            };
        }
    }
    Resolved {
        kind: invite.kind.clone(),
        from_invite: true,
    }
}

/// The QR code of `text`, as rows of dark modules, `width` by `width`,
/// without the quiet zone (the app draws the margin).
pub fn qr_modules(text: &str) -> (usize, Vec<bool>) {
    let code = qrcode::QrCode::with_error_correction_level(text, qrcode::EcLevel::M)
        .expect("an invite fits in a QR code");
    let width = code.width();
    let dark = code
        .to_colors()
        .into_iter()
        .map(|c| c == qrcode::Color::Dark)
        .collect();
    (width, dark)
}

/// Looks for a QR code in a camera frame: `gray` holds one byte of light
/// per pixel, `width` by `height`, `stride` bytes per row. The text of the
/// first code found.
pub fn read_qr(gray: &[u8], width: usize, height: usize, stride: usize) -> Option<String> {
    if width == 0 || height == 0 || stride < width || gray.len() < stride * (height - 1) + width {
        return None;
    }
    let mut img =
        rqrr::PreparedImage::prepare_from_greyscale(width, height, |x, y| gray[y * stride + x]);
    img.detect_grids()
        .into_iter()
        .find_map(|g| g.decode().ok().map(|(_, text)| text))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::AccountId;

    fn account(kind: AccountKind) -> Account {
        Account {
            id: AccountId(1),
            name: "Info".into(),
            email: "info@example.org".into(),
            sender_name: String::new(),
            color: "#3451D1".into(),
            kind,
        }
    }

    fn imap() -> AccountKind {
        AccountKind::Imap {
            imap: Server {
                host: "imaps.example.org".into(),
                port: 993,
                security: Security::Tls,
            },
            smtp: Server {
                host: "smtps.example.org".into(),
                port: 465,
                security: Security::Tls,
            },
            username: "info@example.org".into(),
        }
    }

    #[test]
    fn an_invite_goes_through_its_link() {
        let invite = Invite::new(&account(imap()));
        assert_eq!(invite.code.len(), CODE_DIGITS);
        assert!(invite.code.chars().all(|c| c.is_ascii_digit()));
        let link = invite.to_link();
        assert!(link.starts_with("piuma:pair?v=1&a=info%40example.org"));
        assert_eq!(Invite::from_link(&link), Some(invite));

        let jmap = Invite::new(&account(AccountKind::Jmap {
            session_url: "https://mail.example.org/.well-known/jmap".into(),
            username: String::new(),
        }));
        assert_eq!(Invite::from_link(&jmap.to_link()), Some(jmap));
    }

    #[test]
    fn other_codes_are_not_invites() {
        assert_eq!(Invite::from_link("https://example.org"), None);
        assert_eq!(Invite::from_link("piuma:pair?v=1&a=x%40y.z&c=123"), None);
        assert_eq!(
            Invite::from_link("piuma:pair?v=2&a=x%40y.z&j=h&c=123456789012"),
            None
        );
    }

    #[test]
    fn a_code_that_would_send_the_password_in_the_clear_is_refused() {
        let mut invite = Invite::new(&account(imap()));
        if let AccountKind::Imap { imap, .. } = &mut invite.kind {
            imap.security = Security::None;
        }
        assert_eq!(Invite::from_link(&invite.to_link()), None);
        let mut invite = Invite::new(&account(imap()));
        if let AccountKind::Imap { smtp, .. } = &mut invite.kind {
            smtp.security = Security::None;
        }
        assert_eq!(Invite::from_link(&invite.to_link()), None);
        let jmap = Invite::new(&account(AccountKind::Jmap {
            session_url: "http://mail.example.org/jmap".into(),
            username: String::new(),
        }));
        assert_eq!(Invite::from_link(&jmap.to_link()), None);
    }

    #[tokio::test]
    async fn the_address_s_own_settings_come_before_the_code_s() {
        // A code for a Gmail address that points somewhere else.
        let invite = Invite {
            email: "matteo@gmail.com".into(),
            kind: imap(),
            code: invite_code(),
        };
        let r = resolve(&invite).await;
        assert!(!r.from_invite);
        assert_eq!(r.host(), "imap.gmail.com");
    }

    #[test]
    fn a_qr_code_reads_back() {
        let link = Invite::new(&account(imap())).to_link();
        let (width, dark) = qr_modules(&link);
        // Drawn 4 pixels a module with a 4-module margin, as a camera
        // would see it straight on.
        let scale = 4;
        let side = (width + 8) * scale;
        let mut gray = vec![255u8; side * side];
        for y in 0..width {
            for x in 0..width {
                if dark[y * width + x] {
                    for dy in 0..scale {
                        for dx in 0..scale {
                            let (px, py) = ((x + 4) * scale + dx, (y + 4) * scale + dy);
                            gray[py * side + px] = 0;
                        }
                    }
                }
            }
        }
        assert_eq!(read_qr(&gray, side, side, side), Some(link));
        assert_eq!(read_qr(&vec![128u8; 64 * 64], 64, 64, 64), None);
    }
}
