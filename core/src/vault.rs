//! The Vault: parcels, bills and trips, read on the device from the
//! original email. Structured data (schema.org JSON-LD, which many shops,
//! carriers and airlines put in their mail) comes first; plain words, in
//! English and Italian, after. Nothing leaves the device.

use std::sync::LazyLock;

use regex::Regex;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::store::Attachment;

/// What a card is about.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Kind {
    #[default]
    Shipment,
    Bill,
    Flight,
    /// A table, a room, a ticket: a place on a day.
    Booking,
    /// Something you sold: to ship, on its way to the buyer, paid out.
    Sale,
    /// A date that costs you if missed: a renewal, an expiry, a fine.
    Deadline,
    /// A gift card or a voucher, with its code.
    Voucher,
    /// A payslip, a statement, a tax form: a file to keep.
    Document,
}

/// How far a parcel has come.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Default, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Stage {
    #[default]
    Ordered,
    Shipped,
    Transit,
    Delivered,
}

/// One card, with only the fields of its kind filled in.
#[derive(Debug, Clone, PartialEq, Eq, Default, Serialize, Deserialize)]
#[serde(default)]
pub struct Card {
    pub kind: Kind,
    /// What joins the emails about the same thing: the tracking number,
    /// the booking code, else the message's own id.
    pub key: String,
    /// The item, the bill, the place.
    pub title: String,
    /// The shop, the company that sent the bill, the airline.
    pub merchant: String,
    /// The merchant's VAT number, when the email identifies it.
    pub vat_number: String,
    /// The day it arrives, is due, leaves, or is booked for:
    /// "YYYY-MM-DD", or empty when the email doesn't say.
    pub day: String,
    /// The time on that day, "HH:MM", or empty.
    pub time: String,

    pub carrier: String,
    pub tracking: String,
    pub stage: Stage,
    pub last_scan: String,
    /// The carrier's page for this parcel: the email's own link, else
    /// the carrier's tracking page. Opened only when the person asks.
    pub track_url: String,

    /// In cents (hundredths of the currency).
    pub amount: Option<i64>,
    /// ISO 4217, like "EUR".
    pub currency: String,
    pub paid: bool,

    pub number: String,
    pub origin: String,
    pub origin_city: String,
    pub destination: String,
    pub destination_city: String,
    pub arrives: String,
    pub seat: String,
    /// A train's coach, "4".
    pub coach: String,
    pub code: String,

    pub party: u32,
    /// A booking's "confirmed", "pending" or "cancelled"; a bill's
    /// "failed", "refund", "in" (money received), "renews" or "ending";
    /// a parcel's "pickup" (waiting at a pick-up point); a document's
    /// "payslip", "statement", "tax" or "contract".
    pub status: String,
    pub address: String,

    /// What a booking is: "train", "ferry", "bus", "stay", "parking",
    /// "car", "event" or "table"; empty for one the email doesn't tell.
    pub travel: String,
    /// The day something ends: a stay's check-out, a parking's or a car's
    /// return (its time in `arrives`), the last day at a pick-up point, a
    /// plan's renewal or end, a voucher's expiry. "YYYY-MM-DD" or empty.
    pub until: String,
    /// How often a plan charges: "week", "month" or "year"; empty when
    /// the email isn't about one.
    pub period: String,
    /// The days a shop gives to send things back, when the email says.
    pub return_days: u32,
    /// The day of the first email about it, filled in by the store.
    pub first: String,

    /// The bill's PDF, or the boarding pass, among the attachments.
    pub file: Option<u32>,
    pub file_name: String,
}

/// The message a card is read from.
pub struct Source<'a> {
    pub subject: &'a str,
    pub from_name: &'a str,
    pub message_id: &'a str,
    /// Unix seconds, for years an email leaves out.
    pub received_at: i64,
    pub text: &'a str,
    pub html: Option<&'a str>,
    pub attachments: &'a [Attachment],
}

const SHIPMENT_WORDS: &[&str] = &[
    "shipped",
    "shipping",
    "shipment",
    "dispatched",
    "delivered",
    "delivery",
    "your order",
    "order confirm",
    "tracking",
    "parcel",
    "package",
    "spedit",
    "spedizione",
    "consegn",
    "ordine",
    "pacco",
    "tracciamento",
    "in transito",
];
const BILL_WORDS: &[&str] = &[
    "invoice",
    "bill",
    "receipt",
    "payment",
    "fattura",
    "bolletta",
    "ricevuta",
    "pagamento",
    "refund",
    "rimborso",
    "addebito",
    "accredito",
    "bonifico",
    "you received",
    "hai ricevuto",
    "sent you",
    "ti ha inviato",
    "royalt",
    "earnings",
];
/// A plan paid again and again.
const PLAN_WORDS: &[&str] = &[
    "subscription",
    "abbonamento",
    "membership",
    "renews",
    "renewal",
    "your plan",
    "il tuo piano",
    "trial",
    "prova gratuita",
];
const TRIP_WORDS: &[&str] = &[
    "flight",
    "boarding",
    "check-in",
    "itinerary",
    "booking",
    "reservation",
    "e-ticket",
    "volo",
    "imbarco",
    "prenotazione",
    "biglietto",
    "itinerario",
    "italo",
    "trenitalia",
    "treno",
    "train ticket",
    "ferry",
    "traghetto",
    "hotel",
    "check-out",
    "your stay",
    "soggiorno",
    "parking",
    "parcheggio",
    "car rental",
    "car hire",
    "noleggio",
    "ticket",
    "biglietti",
    "concerto",
    "your table",
    "tavolo",
];
/// A sale on a second-hand site, as the seller reads it.
const SALE_WORDS: &[&str] = &[
    "sold",
    "vendita",
    "venduto",
    "venduta",
    "hai venduto",
    "ship by",
    "ship your",
    "spedisci",
    "da spedire",
    "buyer",
    "acquirente",
    "compratore",
    "payout",
];
const DEADLINE_WORDS: &[&str] = &[
    "expires",
    "expiring",
    "expiry",
    "renewal notice",
    "renew your",
    "scade",
    "scadenza",
    "in scadenza",
    "rinnovo",
    "avviso di pagamento",
    "pagopa",
    "bollo",
    "multa",
    "verbale",
    "contravvenzione",
    "revisione",
    "polizza",
    "insurance",
    "assicurazione",
    "passport",
    "passaporto",
    "patente",
    "licence",
    "license",
    "carta d'identità",
];
/// Deadline words that win over a plan's: an insurance renewal is a
/// deadline, not a subscription.
const DEADLINE_FIRST: &[&str] = &[
    "avviso di pagamento",
    "pagopa",
    "bollo",
    "multa",
    "verbale",
    "contravvenzione",
    "revisione",
    "polizza",
    "insurance",
    "assicurazione",
    "passport",
    "passaporto",
    "patente",
    "licence",
    "license",
    "carta d'identità",
];
const VOUCHER_WORDS: &[&str] = &[
    "gift card",
    "giftcard",
    "e-gift",
    "carta regalo",
    "buono regalo",
    "voucher",
];
const DOCUMENT_WORDS: &[&str] = &[
    "busta paga",
    "cedolino",
    "payslip",
    "pay slip",
    "estratto conto",
    "statement",
    "rendiconto",
    "f24",
    "certificazione unica",
    "modello 730",
    "730 precompilato",
    "dichiarazione dei redditi",
    "tax return",
    "contratto",
];

/// Whether a subject is worth reading the whole email for.
pub fn candidate(subject: &str) -> bool {
    let s = subject.to_lowercase();
    [
        SHIPMENT_WORDS,
        BILL_WORDS,
        PLAN_WORDS,
        TRIP_WORDS,
        SALE_WORDS,
        DEADLINE_WORDS,
        VOUCHER_WORDS,
        DOCUMENT_WORDS,
    ]
    .iter()
    .any(|words| words.iter().any(|w| s.contains(w)))
}

/// Whether an HTML body carries schema.org data.
pub fn has_markup(html: &str) -> bool {
    html.contains("application/ld+json")
}

/// The card an email makes, if it makes one.
pub fn extract(src: &Source) -> Option<Card> {
    let card = src.html.and_then(from_markup).or_else(|| from_words(src))?;
    Some(finish(card, src))
}

/// The card of an email a rule moved to the Vault: what it says, else
/// a receipt with its subject, sender and PDF, so it is never left out.
pub fn extract_kept(src: &Source) -> Card {
    let card = src
        .html
        .and_then(from_markup)
        .or_else(|| from_words(src))
        .unwrap_or(Card {
            kind: Kind::Bill,
            key: format!("kept:{}", src.message_id).to_lowercase(),
            paid: true,
            ..Card::default()
        });
    finish(card, src)
}

/// What every card has: a key, a title, who it is from and its file.
fn finish(mut card: Card, src: &Source) -> Card {
    if card.kind == Kind::Bill && !card.paid {
        card.paid = says_paid(src.subject, src.text);
    }
    if card.kind == Kind::Shipment && card.track_url.is_empty() {
        card.track_url = link_with(src, &card.tracking).unwrap_or_default();
    }
    mend(&mut card);
    if card.key.is_empty() {
        card.key = match (card.kind, card.amount) {
            // Retries of a failed charge say the same thing again: one card
            // per sender.
            (Kind::Bill, None) if card.status == "failed" => {
                format!("bill:failed:{}", src.from_name.trim()).to_lowercase()
            }
            // Reminders about the same bill say the same sum: one card.
            (Kind::Bill, Some(amount)) => format!(
                "bill:{}:{amount}{}:{}",
                src.from_name.trim(),
                card.currency,
                card.day
            )
            .to_lowercase(),
            // Reminders of one deadline name the same day.
            (Kind::Deadline, _) if !card.day.is_empty() => {
                format!("deadline:{}:{}", src.from_name.trim(), card.day).to_lowercase()
            }
            _ => format!("{:?}:{}", card.kind, src.message_id).to_lowercase(),
        };
    }
    if card.title.is_empty() {
        // A room, a car park or a car is best named by who sent it.
        card.title = match card.travel.as_str() {
            "stay" | "parking" | "car" if !src.from_name.trim().is_empty() => {
                src.from_name.trim().to_owned()
            }
            _ => clean_subject(src.subject),
        };
    }
    if card.merchant.is_empty() && card.kind != Kind::Flight {
        card.merchant = src.from_name.to_owned();
    }
    if card.return_days == 0 && matches!(card.kind, Kind::Shipment | Kind::Bill) {
        card.return_days = return_days(&body_text(src));
    }
    let file = match card.kind {
        Kind::Bill | Kind::Deadline | Kind::Voucher | Kind::Document => {
            src.attachments.iter().find(|a| is_pdf(a))
        }
        Kind::Flight | Kind::Booking => src
            .attachments
            .iter()
            .find(|a| a.mime == "application/vnd.apple.pkpass")
            .or_else(|| src.attachments.iter().find(|a| is_pdf(a))),
        Kind::Shipment | Kind::Sale => None,
    };
    if let Some(f) = file {
        card.file = Some(f.part);
        card.file_name = f.name.clone();
    }
    card
}

/// Fills in what a parcel's number alone tells: the carrier, when only
/// one uses numbers of that shape, and the carrier's tracking page.
/// Also run on cards kept before these were read.
pub fn mend(card: &mut Card) {
    if card.kind != Kind::Shipment || card.tracking.is_empty() {
        return;
    }
    if card.carrier.is_empty() {
        card.carrier = carrier_of(&card.tracking).unwrap_or_default().to_owned();
    }
    let track_url = card.track_url.trim();
    if track_url.is_empty() || !track_url.starts_with("https://") {
        card.track_url = tracking_page(&card.carrier, &card.tracking).unwrap_or_default();
    }
}

/// The carrier a tracking number's shape names, from the rules of
/// tracking_number_data (MIT): only shapes no one else uses, with their
/// check digit where they have one.
pub fn carrier_of(tracking: &str) -> Option<&'static str> {
    let code: String = tracking
        .split_whitespace()
        .collect::<String>()
        .to_uppercase();
    let b = code.as_bytes();
    let digits = |r: std::ops::Range<usize>| {
        b.get(r.clone())
            .is_some_and(|s| s.iter().all(u8::is_ascii_digit))
    };
    let letters = |r: std::ops::Range<usize>| {
        b.get(r.clone())
            .is_some_and(|s| s.iter().all(u8::is_ascii_uppercase))
    };
    // UPS: 1Z, then 15 letters or digits and a check digit.
    if code.len() == 18 && code.starts_with("1Z") && b[2..].iter().all(u8::is_ascii_alphanumeric) {
        let value = |c: u8| {
            if c.is_ascii_digit() {
                (c - b'0') as u32
            } else {
                ((c as u32) - 3) % 10
            }
        };
        let sum: u32 = b[2..17]
            .iter()
            .enumerate()
            .map(|(i, &c)| value(c) * if i % 2 == 1 { 2 } else { 1 })
            .sum();
        let check = (10 - sum % 10) % 10;
        return (b[17].is_ascii_digit() && (b[17] - b'0') as u32 == check).then_some("UPS");
    }
    // Amazon Logistics: TBA, TBC or TBM and 12 digits.
    if code.len() == 15 && code.starts_with("TB") && b"ACM".contains(&b[2]) && digits(3..15) {
        return Some("Amazon Logistics");
    }
    // DHL piece numbers: JJD, JVGL and the like, then 9 or 10 digits.
    for head in [3, 4] {
        if b.first() == Some(&b'J')
            && letters(1..head)
            && matches!(code.len() - head, 9 | 10)
            && digits(head..code.len())
        {
            return Some("DHL");
        }
    }
    // The post's own (UPU S10): two letters, 8 digits, a check digit and
    // the country.
    if code.len() == 13 && letters(0..2) && digits(2..11) && letters(11..13) {
        const WEIGHTS: [u32; 8] = [8, 6, 4, 2, 3, 5, 9, 7];
        let sum: u32 = b[2..10]
            .iter()
            .zip(WEIGHTS)
            .map(|(&c, w)| (c - b'0') as u32 * w)
            .sum();
        let check = match 11 - sum % 11 {
            10 => 0,
            11 => 5,
            n => n,
        };
        if (b[10] - b'0') as u32 != check {
            return None;
        }
        return match &code[11..] {
            "IT" => Some("Poste Italiane"),
            "GB" => Some("Royal Mail"),
            "DE" => Some("Deutsche Post"),
            "US" => Some("USPS"),
            "NL" => Some("PostNL"),
            "ES" => Some("Correos"),
            _ => None,
        };
    }
    None
}

/// The carrier's tracking page: the parcel's own where the carrier has
/// a stable link for it, else the page to look it up on.
fn tracking_page(carrier: &str, tracking: &str) -> Option<String> {
    let code: String = tracking.split_whitespace().collect();
    let code: String = code.chars().filter(char::is_ascii_alphanumeric).collect();
    let with = |base: &str| Some(format!("{base}{code}"));
    match carrier.to_lowercase().as_str() {
        "ups" => with("https://www.ups.com/track?tracknum="),
        "fedex" => with("https://www.fedex.com/fedextrack/?trknbr="),
        "dhl" => with("https://www.dhl.com/it-it/home/tracking.html?tracking-id="),
        "usps" => with("https://tools.usps.com/go/TrackConfirmAction?tLabels="),
        "royal mail" => with("https://www.royalmail.com/track-your-item#/tracking-results/"),
        "deutsche post" => {
            with("https://www.deutschepost.de/de/s/sendungsverfolgung.html?piececode=")
        }
        "brt" | "bartolini" => with("https://services.brt.it/it/tracking?OP=N&CD="),
        "poste italiane" | "poste delivery" => Some("https://www.poste.it/cerca/index.html".into()),
        "gls" => {
            Some("https://www.gls-italy.com/it/servizi-per-destinatari/ricerca-spedizione".into())
        }
        "sda" => Some("https://www.sda.it/".into()),
        "inpost" => Some("https://inpost.it/trova-il-tuo-pacco".into()),
        "dpd" => Some("https://www.dpd.com/it/it/ricevere/traccia-il-tuo-pacco/".into()),
        _ => None,
    }
}

static LINK: LazyLock<Regex> = LazyLock::new(|| re(r#"https://[^\s"'<>()]+"#));

/// The email's own link to the parcel: an https address with its
/// tracking number in it.
fn link_with(src: &Source, tracking: &str) -> Option<String> {
    let code: String = tracking.split_whitespace().collect();
    if code.len() < 6 {
        return None;
    }
    let html = src.html.unwrap_or_default();
    [html, src.text]
        .iter()
        .flat_map(|t| LINK.find_iter(t))
        .map(|m| m.as_str().replace("&amp;", "&"))
        .find(|url| url.contains(&code))
}

fn is_pdf(a: &Attachment) -> bool {
    a.mime == "application/pdf" || a.name.to_lowercase().ends_with(".pdf")
}

/// The subject without "Fwd:", "Re:" and the like.
fn clean_subject(subject: &str) -> String {
    let mut s = subject.trim();
    loop {
        let lower = s.to_lowercase();
        let Some(rest) = ["re:", "fwd:", "fw:", "i:", "r:"]
            .iter()
            .find(|p| lower.starts_with(*p))
            .map(|p| &s[p.len()..])
        else {
            return s.to_owned();
        };
        s = rest.trim_start();
    }
}

// ---------------------------------------------------------------------------
// schema.org

fn from_markup(html: &str) -> Option<Card> {
    if !has_markup(html) {
        return None;
    }
    let doc = scraper::Html::parse_document(html);
    let sel = scraper::Selector::parse(r#"script[type="application/ld+json"]"#).ok()?;
    for script in doc.select(&sel) {
        let raw: String = script.text().collect();
        let Ok(value) = serde_json::from_str::<Value>(raw.trim()) else {
            continue;
        };
        for item in items(&value) {
            if let Some(card) = from_item(item) {
                return Some(card);
            }
        }
    }
    None
}

/// The things a JSON-LD block describes: one, a list, or a `@graph`.
fn items(v: &Value) -> Vec<&Value> {
    match v {
        Value::Array(list) => list.iter().flat_map(items).collect(),
        Value::Object(o) => match o.get("@graph") {
            Some(g) => items(g),
            None => vec![v],
        },
        _ => Vec::new(),
    }
}

/// The schema.org type, without its "http://schema.org/" prefix.
fn type_of(v: &Value) -> &str {
    let t = match v.get("@type") {
        Some(Value::Array(list)) => list.first().and_then(Value::as_str),
        Some(t) => t.as_str(),
        None => None,
    };
    t.map(|t| t.rsplit('/').next().unwrap_or(t))
        .unwrap_or_default()
}

/// A field as text: a string, a number, or the `name` of an object.
fn text(v: Option<&Value>) -> String {
    match v {
        Some(Value::String(s)) => s.trim().to_owned(),
        Some(Value::Number(n)) => n.to_string(),
        Some(Value::Array(list)) => text(list.first()),
        Some(o @ Value::Object(_)) => text(o.get("name")),
        _ => String::new(),
    }
}

/// Follows `path` through objects, taking the first of any list.
fn at<'a>(v: &'a Value, path: &[&str]) -> Option<&'a Value> {
    let mut v = v;
    for key in path {
        if let Value::Array(list) = v {
            v = list.first()?;
        }
        v = v.get(*key)?;
    }
    Some(v)
}

fn first_text(v: &Value, paths: &[&[&str]]) -> String {
    paths
        .iter()
        .map(|p| text(at(v, p)))
        .find(|t| !t.is_empty())
        .unwrap_or_default()
}

/// Keep the VAT number of the same party whose name became `merchant`.
fn merchant_vat(v: &Value, paths: &[&[&str]]) -> String {
    paths
        .iter()
        .filter_map(|p| at(v, p))
        .find(|party| !text(Some(party)).is_empty())
        .map(|party| text(party.get("vatID")))
        .unwrap_or_default()
}

/// "2026-10-24T07:15:00+02:00" as ("2026-10-24", "07:15"), as written:
/// the local time of the place, which is what a ticket shows.
fn date_time(s: &str) -> (String, String) {
    let s = s.trim();
    let day = if s.len() >= 10 && parse_iso(&s[..10]).is_some() {
        s[..10].to_owned()
    } else {
        String::new()
    };
    let time = s
        .split_once('T')
        .map(|(_, t)| t.get(..5).unwrap_or_default().to_owned())
        .filter(|t| t.len() == 5 && t.as_bytes()[2] == b':')
        .unwrap_or_default();
    (day, time)
}

fn from_item(v: &Value) -> Option<Card> {
    let card = match type_of(v) {
        "ParcelDelivery" => {
            let (day, _) = date_time(&first_text(
                v,
                &[&["expectedArrivalUntil"], &["expectedArrivalFrom"]],
            ));
            let status = first_text(v, &[&["deliveryStatus"], &["partOfOrder", "orderStatus"]]);
            let tracking = text(v.get("trackingNumber"));
            Card {
                kind: Kind::Shipment,
                key: key("ship", &tracking),
                title: first_text(
                    v,
                    &[
                        &["itemShipped", "name"],
                        &["partOfOrder", "acceptedOffer", "itemOffered", "name"],
                    ],
                ),
                merchant: first_text(
                    v,
                    &[&["partOfOrder", "merchant"], &["partOfOrder", "seller"]],
                ),
                vat_number: merchant_vat(
                    v,
                    &[&["partOfOrder", "merchant"], &["partOfOrder", "seller"]],
                ),
                carrier: first_text(v, &[&["carrier"], &["provider"]]),
                track_url: text(v.get("trackingUrl")),
                tracking,
                stage: order_stage(&status).unwrap_or(Stage::Shipped),
                status: if status.contains("PickupAvailable") {
                    "pickup".into()
                } else {
                    String::new()
                },
                day,
                ..Card::default()
            }
        }
        "Order" => {
            let number = text(v.get("orderNumber"));
            let amount = parse_amount(&first_text(
                v,
                &[&["totalPrice"], &["price"], &["acceptedOffer", "price"]],
            ));
            Card {
                kind: Kind::Shipment,
                key: key("order", &number),
                title: first_text(v, &[&["acceptedOffer", "itemOffered", "name"]]),
                merchant: first_text(v, &[&["merchant"], &["seller"]]),
                vat_number: merchant_vat(v, &[&["merchant"], &["seller"]]),
                stage: order_stage(&text(v.get("orderStatus"))).unwrap_or(Stage::Ordered),
                currency: if amount.is_some() {
                    first_text(
                        v,
                        &[&["priceCurrency"], &["acceptedOffer", "priceCurrency"]],
                    )
                    .to_uppercase()
                } else {
                    String::new()
                },
                amount,
                ..Card::default()
            }
        }
        "Invoice" => {
            let due = at(v, &["totalPaymentDue"]).or_else(|| at(v, &["minimumPaymentDue"]));
            let amount = due.and_then(|d| {
                let value = first_text(d, &[&["price"], &["value"]]);
                parse_amount(&value)
            });
            let currency = due
                .map(|d| first_text(d, &[&["priceCurrency"], &["currency"]]))
                .unwrap_or_default();
            let (day, _) = date_time(&text(v.get("paymentDueDate")));
            Card {
                kind: Kind::Bill,
                key: key(
                    "bill",
                    &first_text(v, &[&["confirmationNumber"], &["identifier"]]),
                ),
                title: first_text(v, &[&["description"], &["name"]]),
                merchant: first_text(v, &[&["provider"], &["broker"]]),
                vat_number: merchant_vat(v, &[&["provider"], &["broker"]]),
                amount,
                currency: currency.to_uppercase(),
                paid: text(v.get("paymentStatus")).contains("PaymentComplete"),
                day,
                ..Card::default()
            }
        }
        "FlightReservation" => {
            let f = at(v, &["reservationFor"])?;
            let airline = first_text(f, &[&["airline", "iataCode"]]);
            let mut number = text(f.get("flightNumber"));
            if !airline.is_empty() && !number.starts_with(&airline) {
                number = format!("{airline} {number}");
            }
            let (day, time) = date_time(&text(f.get("departureTime")));
            let (_, arrives) = date_time(&text(f.get("arrivalTime")));
            let city = |airport: &str| {
                first_text(
                    f,
                    &[&[airport, "address", "addressLocality"], &[airport, "name"]],
                )
            };
            let code = text(v.get("reservationNumber"));
            Card {
                kind: Kind::Flight,
                key: key("trip", &code),
                title: number.clone(),
                merchant: first_text(f, &[&["airline"]]),
                number,
                origin: first_text(f, &[&["departureAirport", "iataCode"]]),
                origin_city: city("departureAirport"),
                destination: first_text(f, &[&["arrivalAirport", "iataCode"]]),
                destination_city: city("arrivalAirport"),
                day,
                time,
                arrives,
                seat: first_text(
                    v,
                    &[
                        &["airplaneSeat"],
                        &["reservedTicket", "ticketedSeat", "seatNumber"],
                    ],
                ),
                code,
                ..Card::default()
            }
        }
        t if t.ends_with("Reservation") => {
            let place = at(v, &["reservationFor"])?;
            let travel = match t {
                "TrainReservation" => "train",
                "BusReservation" => "bus",
                "BoatReservation" => "ferry",
                "LodgingReservation" => "stay",
                "RentalCarReservation" => "car",
                "EventReservation" => "event",
                "FoodEstablishmentReservation" => "table",
                _ => "",
            };
            let (day, time) = date_time(&first_text(
                v,
                &[
                    &["startTime"],
                    &["checkinTime"],
                    &["checkinDate"],
                    &["pickupTime"],
                    &["reservationFor", "departureTime"],
                    &["reservationFor", "startDate"],
                ],
            ));
            let (until, arrives) = date_time(&first_text(
                v,
                &[
                    &["endTime"],
                    &["checkoutTime"],
                    &["checkoutDate"],
                    &["dropoffTime"],
                    &["reservationFor", "arrivalTime"],
                    &["reservationFor", "endDate"],
                ],
            ));
            let address_of = |a: Option<&Value>| match a {
                Some(Value::String(s)) => s.trim().to_owned(),
                Some(a) => [text(a.get("streetAddress")), text(a.get("addressLocality"))]
                    .into_iter()
                    .filter(|s| !s.is_empty())
                    .collect::<Vec<_>>()
                    .join(", "),
                None => String::new(),
            };
            let address = [
                place.get("address"),
                at(place, &["location", "address"]),
                at(v, &["pickupLocation", "address"]),
            ]
            .into_iter()
            .map(address_of)
            .find(|a| !a.is_empty())
            .unwrap_or_default();
            // A ride is named by where it goes: "Milano Centrale → Roma Termini".
            let ends = [
                ("departureStation", "arrivalStation"),
                ("departureBusStop", "arrivalBusStop"),
                ("departureBoatTerminal", "arrivalBoatTerminal"),
            ]
            .iter()
            .map(|(from, to)| (text(place.get(*from)), text(place.get(*to))))
            .find(|(from, to)| !from.is_empty() && !to.is_empty());
            let title = match (&ends, travel) {
                (Some((from, to)), _) => format!("{from} → {to}"),
                (None, "car") => first_text(v, &[&["provider"], &["reservationFor", "name"]]),
                _ => text(place.get("name")),
            };
            let code = text(v.get("reservationNumber"));
            let status = text(v.get("reservationStatus"));
            Card {
                kind: Kind::Booking,
                key: key("trip", &code),
                title,
                time,
                // A ride that arrives the next day ends then too.
                until: if until == day { String::new() } else { until },
                day,
                arrives,
                number: first_text(place, &[&["trainNumber"], &["busNumber"]]),
                coach: first_text(v, &[&["reservedTicket", "ticketedSeat", "seatSection"]]),
                seat: first_text(v, &[&["reservedTicket", "ticketedSeat", "seatNumber"]]),
                party: text(v.get("partySize")).parse().unwrap_or(0),
                status: if status.contains("Cancelled") {
                    "cancelled".into()
                } else if status.contains("Pending") {
                    "pending".into()
                } else {
                    "confirmed".into()
                },
                address,
                code,
                travel: travel.into(),
                ..Card::default()
            }
        }
        _ => return None,
    };
    Some(card)
}

fn key(prefix: &str, id: &str) -> String {
    let id: String = id.split_whitespace().collect();
    if id.is_empty() {
        String::new()
    } else {
        format!("{prefix}:{}", id.to_uppercase())
    }
}

fn order_stage(status: &str) -> Option<Stage> {
    let s = status.rsplit('/').next().unwrap_or(status);
    Some(match s {
        "OrderDelivered" => Stage::Delivered,
        "OrderInTransit" | "OrderPickupAvailable" | "OrderOutForDelivery" => Stage::Transit,
        "OrderShipped" => Stage::Shipped,
        "OrderProcessing" | "OrderPaymentDue" => Stage::Ordered,
        _ => return None,
    })
}

// ---------------------------------------------------------------------------
// Plain words

fn re(pattern: &str) -> Regex {
    Regex::new(pattern).expect("vault pattern")
}

static FLIGHT: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(?i:\b(?:flight|volo|flug|vol)\b)\s*(?i:n(?:o|r|umber|umero)?\.?\s*)?[:#]?\s*\b([A-Z][A-Z0-9]|[0-9][A-Z])\s?([0-9]{1,4})\b",
    )
});
static ROUTE: LazyLock<Regex> =
    LazyLock::new(|| re(r"\b([A-Z]{3})\s*(?:→|->|–|—|-|>|\bto\b|\ba\b)\s*([A-Z]{3})\b"));
static AIRPORT: LazyLock<Regex> =
    LazyLock::new(|| re(r"([A-Z][\p{L}'.]+(?: [A-Z][\p{L}'.]+){0,2})?\s*\(([A-Z]{3})\)"));
static TIME: LazyLock<Regex> = LazyLock::new(|| re(r"\b([01]?[0-9]|2[0-3])[:.]([0-5][0-9])\b"));
static SEAT: LazyLock<Regex> =
    LazyLock::new(|| re(r"(?i:\b(?:seat|posto)\b)\s*[:#]?\s*([0-9]{1,2}[A-K])\b"));
static CODE: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(?i:booking reference|booking code|confirmation (?:code|number)|reservation (?:code|number)|record locator|\bpnr\b|codice (?:di )?prenotazione|codice biglietto|codice pnr|riferimento (?:della )?prenotazione)(?i:\s*\(pnr\))?\s*[:#]?\s*([A-Z0-9]{5,8})\b",
    )
});
static TRACKING: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(?i:tracking(?: number| code| no\.?| id)?|numero di (?:tracciamento|spedizione)|codice (?:di )?(?:tracciamento|spedizione)|lettera di vettura|n\. spedizione|spedizione)\s*[:#]?\s*([A-Z0-9][A-Z0-9 -]{5,40})",
    )
});
/// A train's times, "16:35 > 17:20".
static LEG: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"\b([01]?[0-9]|2[0-3])[:.]([0-5][0-9])\s*(?:>|→|->|–|—|-)\s*([01]?[0-9]|2[0-3])[:.]([0-5][0-9])\b",
    )
});
static UPS: LazyLock<Regex> = LazyLock::new(|| re(r"\b1Z[0-9A-Z]{16}\b"));
static ORDER: LazyLock<Regex> = LazyLock::new(|| {
    re(r"(?i:\border|\bordine)\s*(?i:n(?:o|r|umber|umero)?\.?\s*)?[:#]?\s*([0-9][0-9A-Z-]{4,30})\b")
});
static AMOUNT: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(€|\$|£|\b(?:EUR|USD|GBP|CHF)\b)\s?([0-9]{1,3}(?:[.,  ][0-9]{3})*(?:[.,][0-9]{2})?|[0-9]+(?:[.,][0-9]{2})?)|([0-9]{1,3}(?:[.,  ][0-9]{3})*(?:[.,][0-9]{2})?|[0-9]+(?:[.,][0-9]{2})?)\s?(€|\b(?:EUR|USD|GBP|CHF)\b|euro\b)",
    )
});

/// Uppercase words that look like airports and aren't.
const NOT_AIRPORTS: &[&str] = &[
    "EUR", "USD", "GBP", "CHF", "VAT", "IVA", "PDF", "THE", "AND", "FOR", "CET", "UTC", "GMT",
    "PNR", "SMS", "APP", "WWW", "COM", "NUM", "TEL", "FAX",
];

const CARRIERS: &[&str] = &[
    "Poste Italiane",
    "Poste Delivery",
    "Amazon Logistics",
    "Royal Mail",
    "Deutsche Post",
    "Corriere Rapido",
    "Bartolini",
    "Chronopost",
    "Colissimo",
    "Correos",
    "InPost",
    "Nexive",
    "PostNL",
    "FedEx",
    "Hermes",
    "USPS",
    "Evri",
    "DHL",
    "UPS",
    "GLS",
    "BRT",
    "SDA",
    "TNT",
    "DPD",
];

fn from_words(src: &Source) -> Option<Card> {
    let body = body_text(src);
    let subject = src.subject;
    let lower_subject = subject.to_lowercase();
    let received = day_of(src.received_at);
    let is = |words: &[&str]| words.iter().any(|w| lower_subject.contains(w));

    // A payslip or a statement is a file to keep, never a bill.
    if is(DOCUMENT_WORDS) {
        return document(&lower_subject, src);
    }
    if is(SALE_WORDS) {
        if let Some(card) = sale(subject, &body, received) {
            return Some(card);
        }
    }
    if is(TRIP_WORDS) {
        let card = flight(&body, received)
            .or_else(|| train(subject, &body, received))
            .or_else(|| stay(subject, &body, received))
            .or_else(|| parking(subject, &body, received))
            .or_else(|| car_hire(subject, &body, received))
            .or_else(|| event(subject, &body, received));
        if card.is_some() {
            return card;
        }
    }
    if is(SHIPMENT_WORDS) {
        if let Some(card) = shipment(subject, &body, received) {
            return Some(card);
        }
        // An order with nothing to follow yet, often a download or a
        // licence, is a purchase: its receipt.
        if stage_in(subject) == Some(Stage::Ordered) {
            if let Some(mut card) = bill(subject, &body, received) {
                if card.status.is_empty() {
                    card.paid = true;
                    card.day.clear();
                }
                return Some(card);
            }
        }
    }
    if is(VOUCHER_WORDS) {
        if let Some(card) = voucher(&body, received) {
            return Some(card);
        }
    }
    if is(DEADLINE_WORDS) && (is(DEADLINE_FIRST) || (!is(PLAN_WORDS) && !is(BILL_WORDS))) {
        if let Some(card) = deadline(subject, &body, received) {
            return Some(card);
        }
    }
    if is(BILL_WORDS) || is(PLAN_WORDS) {
        return bill(subject, &body, received);
    }
    None
}

/// The text the person would read, one line per block.
fn body_text(src: &Source) -> String {
    let shown = crate::reading::plain_text(&crate::reading::readable(src.text, src.html));
    let shown = if shown.trim().is_empty() {
        src.text.to_owned()
    } else {
        shown
    };
    // Non-breaking and thin spaces read as spaces.
    shown.replace(['\u{a0}', '\u{202f}', '\u{2009}'], " ")
}

fn flight(body: &str, received: Day) -> Option<Card> {
    let f = FLIGHT.captures(body)?;
    let number = format!("{} {}", &f[1], &f[2]);
    let after = &body[f.get(0)?.start()..];
    let (origin, origin_city, destination, destination_city) =
        route(after).or_else(|| route(body))?;
    let mut times = TIME
        .captures_iter(after)
        .map(|c| format!("{:0>2}:{}", &c[1], &c[2]));
    let time = times.next().unwrap_or_default();
    let arrives = times.next().unwrap_or_default();
    let day = find_day(after, received).or_else(|| find_day(body, received));
    let code = CODE
        .captures(body)
        .map(|c| c[1].to_owned())
        .unwrap_or_default();
    Some(Card {
        kind: Kind::Flight,
        key: key("trip", &code),
        title: number.clone(),
        number,
        origin,
        origin_city,
        destination,
        destination_city,
        day: day.map(|d| d.to_string()).unwrap_or_default(),
        time,
        arrives,
        seat: SEAT
            .captures(body)
            .map(|c| c[1].to_owned())
            .unwrap_or_default(),
        code,
        ..Card::default()
    })
}

/// A train, ferry or bus ticket, as Italo, Trenitalia and the ferry
/// lines send it: a ticket code, the times "16:35 > 17:20" (or after
/// "Partenza" and "Arrivo"), the route after "Itinerario". A booking
/// card: a seat on a day.
fn train(subject: &str, body: &str, received: Day) -> Option<Card> {
    let code = CODE.captures(body)?[1].to_owned();
    let lower = body.to_lowercase();
    let (time, arrives) = match LEG.captures(body) {
        Some(leg) => (
            format!("{:0>2}:{}", &leg[1], &leg[2]),
            format!("{:0>2}:{}", &leg[3], &leg[4]),
        ),
        None => (
            time_after(body, &["partenza", "departure", "departs"])?,
            time_after(body, &["arrivo", "arrival", "arrives"]).unwrap_or_default(),
        ),
    };
    let after = |words: &[&str]| -> Option<String> {
        words.iter().find_map(|k| {
            let at = find_word(&lower, k)?;
            body.get(at + k.len()..)?
                .lines()
                .map(|l| l.replace('|', " ").trim().to_owned())
                .find(|l| !l.is_empty())
        })
    };
    let title = after(&["itinerario", "tratta", "rotta", "collegamento", "route"])
        .and_then(|line| {
            let (from, to) = [" - ", " > ", " → ", " – "]
                .iter()
                .find_map(|sep| line.split_once(sep))?;
            Some(format!("{} → {}", from.trim(), to.trim()))
        })
        .or_else(|| {
            let from = place_after(body, &["porto di partenza", "departure port", "da"])?;
            let to = place_after(body, &["porto di arrivo", "arrival port", "a"])?;
            Some(format!("{from} → {to}"))
        })
        .unwrap_or_default();
    let day = ["data", "date", "andata", "partenza", "departure"]
        .iter()
        .find_map(|k| {
            let at = find_word(&lower, k)?;
            let rest = body.get(at + k.len()..)?.replace('|', " ");
            parse_day_near(rest.trim_start(), received)
        })
        .or_else(|| find_day(body, received));
    let words = format!("{} {lower}", subject.to_lowercase());
    let travel = if ["ferry", "traghetto", "nave", "imbarco veicoli", "porto di"]
        .iter()
        .any(|w| words.contains(w))
    {
        "ferry"
    } else if ["autobus", "pullman", "coach ticket"]
        .iter()
        .any(|w| words.contains(w))
        || contains_word(&words, "bus")
    {
        "bus"
    } else {
        "train"
    };
    let seated = train_seat(body);
    Some(Card {
        kind: Kind::Booking,
        key: key("trip", &code),
        title,
        day: day.map(|d| d.to_string()).unwrap_or_default(),
        time,
        arrives,
        number: seated.number,
        coach: if travel == "train" {
            seated.coach
        } else {
            String::new()
        },
        seat: seated.seat,
        code,
        status: "confirmed".into(),
        travel: travel.into(),
        ..Card::default()
    })
}

/// The first time on the line after one of `keys`, "16:35".
fn time_after(body: &str, keys: &[&str]) -> Option<String> {
    let lower = body.to_lowercase();
    keys.iter().find_map(|k| {
        let at = find_word(&lower, k)?;
        let rest: String = body.get(at + k.len()..)?.chars().take(60).collect();
        let c = TIME.captures(&rest)?;
        Some(format!("{:0>2}:{}", &c[1], &c[2]))
    })
}

/// A place named on its own after one of `keys` and a colon: "Da: Genova".
fn place_after(body: &str, keys: &[&str]) -> Option<String> {
    body.lines().find_map(|line| {
        let lower = line.to_lowercase();
        keys.iter().find_map(|k| {
            let rest = lower.trim_start().strip_prefix(k)?;
            let rest = rest.trim_start().strip_prefix(':')?;
            // Lowercasing can change byte lengths; take the same chars.
            let skip = line.chars().count() - rest.chars().count();
            let name: String = line.chars().skip(skip).collect();
            let name = name
                .split(|c: char| c.is_ascii_digit() || c == '|' || c == ',')
                .next()?
                .trim();
            (name.chars().count() >= 3 && name.chars().any(char::is_alphabetic))
                .then(|| name.to_owned())
        })
    })
}

/// The words after one of `keys` up to the end of its line: a hotel's
/// name after "Struttura:".
fn line_after(body: &str, keys: &[&str]) -> Option<String> {
    body.lines().find_map(|line| {
        let lower = line.to_lowercase();
        keys.iter().find_map(|k| {
            let rest = lower.trim_start().strip_prefix(k)?;
            if !rest.trim_start().starts_with(':') {
                return None;
            }
            let rest = rest.trim_start().trim_start_matches(':');
            let skip = line.chars().count() - rest.chars().count();
            let value: String = line.chars().skip(skip).collect();
            let value = value.replace('|', " ").trim().to_owned();
            (!value.is_empty()).then_some(value)
        })
    })
}

/// A day and a time after one of `keys`: "Check-in: Fri 7 Nov, from 15:00".
fn when_after(body: &str, keys: &[&str], received: Day) -> Option<(Day, String)> {
    let lower = body.to_lowercase();
    keys.iter().find_map(|k| {
        let at = find_word(&lower, k)?;
        let rest = body.get(at + k.len()..)?.replace('|', " ");
        let rest = rest.trim_start_matches(|c: char| c == ':' || c.is_whitespace());
        let window: String = rest.chars().take(60).collect();
        let day = parse_day_near(&window, received)?;
        let time = TIME
            .captures(&window)
            .map(|c| format!("{:0>2}:{}", &c[1], &c[2]))
            .unwrap_or_default();
        Some((day, time))
    })
}

/// A room booked from a check-in day to a check-out day.
fn stay(subject: &str, body: &str, received: Day) -> Option<Card> {
    let (day, time) = when_after(body, &["check-in", "check in", "arrivo"], received)?;
    let (until, arrives) = when_after(body, &["check-out", "check out", "partenza"], received)?;
    if until <= day {
        return None;
    }
    let title = line_after(
        body,
        &[
            "hotel",
            "struttura",
            "alloggio",
            "property",
            "accommodation",
        ],
    )
    .or_else(|| quoted(subject))
    .unwrap_or_default();
    Some(Card {
        kind: Kind::Booking,
        key: key("trip", &code_in(body)),
        title,
        day: day.to_string(),
        time,
        until: until.to_string(),
        arrives,
        party: party_in(body),
        code: code_in(body),
        address: line_after(body, &["address", "indirizzo"]).unwrap_or_default(),
        status: "confirmed".into(),
        travel: "stay".into(),
        ..Card::default()
    })
}

/// A car park booked from an entry to an exit.
fn parking(subject: &str, body: &str, received: Day) -> Option<Card> {
    let words = format!("{} {}", subject.to_lowercase(), body.to_lowercase());
    if !["parking", "parcheggio", "car park", "sosta"]
        .iter()
        .any(|w| words.contains(w))
    {
        return None;
    }
    let (day, time) = when_after(
        body,
        &[
            "ingresso", "entrata", "entry", "arrival", "arrivo", "dal", "from",
        ],
        received,
    )?;
    let (until, arrives) = when_after(
        body,
        &["uscita", "exit", "departure", "partenza", "al", "to"],
        received,
    )?;
    if until < day {
        return None;
    }
    let code = code_in(body);
    Some(Card {
        kind: Kind::Booking,
        key: key("trip", &code),
        title: line_after(body, &["parcheggio", "parking", "car park", "location"])
            .unwrap_or_default(),
        day: day.to_string(),
        time,
        until: until.to_string(),
        arrives,
        code,
        address: line_after(body, &["address", "indirizzo"]).unwrap_or_default(),
        status: "confirmed".into(),
        travel: "parking".into(),
        ..Card::default()
    })
}

/// A car hired from a pick-up to a drop-off.
fn car_hire(subject: &str, body: &str, received: Day) -> Option<Card> {
    let words = format!("{} {}", subject.to_lowercase(), body.to_lowercase());
    if !["car rental", "car hire", "noleggio", "rent a car"]
        .iter()
        .any(|w| words.contains(w))
    {
        return None;
    }
    let (day, time) = when_after(body, &["pick-up", "pickup", "pick up", "ritiro"], received)?;
    let (until, arrives) = when_after(
        body,
        &[
            "drop-off",
            "dropoff",
            "drop off",
            "return",
            "riconsegna",
            "restituzione",
        ],
        received,
    )?;
    if until < day {
        return None;
    }
    let code = code_in(body);
    Some(Card {
        kind: Kind::Booking,
        key: key("trip", &code),
        day: day.to_string(),
        time,
        until: until.to_string(),
        arrives,
        code,
        address: line_after(
            body,
            &[
                "pick-up location",
                "luogo di ritiro",
                "address",
                "indirizzo",
            ],
        )
        .unwrap_or_default(),
        status: "confirmed".into(),
        travel: "car".into(),
        ..Card::default()
    })
}

/// Tickets for a concert, a show, a match or a museum; or a table.
fn event(subject: &str, body: &str, received: Day) -> Option<Card> {
    let s = subject.to_lowercase();
    let table = ["your table", "tavolo", "ristorante", "restaurant"]
        .iter()
        .any(|w| s.contains(w));
    let ticket = [
        "ticket",
        "biglietti",
        "biglietto",
        "concerto",
        "evento",
        "spettacolo",
    ]
    .iter()
    .any(|w| s.contains(w));
    // A support ticket is not a seat at a show.
    let support = [
        "support",
        "assistenza",
        "request",
        "richiesta",
        "case #",
        "pratica",
    ]
    .iter()
    .any(|w| s.contains(w));
    if (!table && !ticket) || support {
        return None;
    }
    let (day, time) = when_after(
        body,
        &["data", "date", "quando", "when", "il giorno", "giorno"],
        received,
    )
    .or_else(|| {
        let day = find_day(body, received)?;
        let time = TIME
            .captures(body)
            .map(|c| format!("{:0>2}:{}", &c[1], &c[2]))
            .unwrap_or_default();
        Some((day, time))
    })?;
    if time.is_empty() {
        return None;
    }
    let title = quoted(subject)
        .or_else(|| line_after(body, &["evento", "event", "spettacolo", "show"]))
        .or_else(|| {
            subject
                .split_once(':')
                .map(|(_, t)| t.trim().to_owned())
                .filter(|t| !t.is_empty())
        })
        .unwrap_or_default();
    let code = code_in(body);
    Some(Card {
        kind: Kind::Booking,
        key: key("trip", &code),
        title,
        day: day.to_string(),
        time,
        party: party_in(body),
        code,
        address: line_after(
            body,
            &[
                "luogo",
                "venue",
                "location",
                "dove",
                "where",
                "indirizzo",
                "address",
            ],
        )
        .unwrap_or_default(),
        status: "confirmed".into(),
        travel: if table { "table" } else { "event" }.into(),
        ..Card::default()
    })
}

fn code_in(body: &str) -> String {
    CODE.captures(body)
        .map(|c| c[1].to_owned())
        .unwrap_or_default()
}

static PARTY: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(?i)\b([1-9][0-9]?)\s*(?:adults?|adulti|guests?|ospiti|persone|people|persons|coperti|biglietti|tickets)\b",
    )
});

/// How many people a booking is for: "2 adults", "4 persone".
fn party_in(body: &str) -> u32 {
    PARTY
        .captures(body)
        .and_then(|c| c[1].parse().ok())
        .unwrap_or(0)
}

/// A train's number, coach and seat.
#[derive(Default)]
struct Seated {
    number: String,
    coach: String,
    seat: String,
}

static TRAIN_NUMBER: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(?i:\bn\.?\s*treno|\btreno|\btrain|\bfrecciarossa|\bfrecciargento|\bintercity|\bitalo)\s*(?i:n\.?\s*)?[:#]?\s*([0-9]{3,5})\b",
    )
});
static COACH: LazyLock<Regex> =
    LazyLock::new(|| re(r"(?i:\bcarrozza|\bcoach|\bvettura)\s*[:#]?\s*([0-9]{1,2})\b"));
static TRAIN_SEAT: LazyLock<Regex> =
    LazyLock::new(|| re(r"(?i:\bposto|\bposti|\bseat|\bseats)\s*[:#]?\s*([0-9]{1,3}[A-F]?)\b"));

/// The column names of a ticket's tables, as Italo and Trenitalia print
/// them: a row of these, then a row of their values.
const TICKET_HEADS: &[&str] = &[
    "orari",
    "orario",
    "n.treno",
    "n. treno",
    "treno",
    "numero treno",
    "train",
    "ambiente",
    "classe",
    "class",
    "carrozza",
    "coach",
    "posto",
    "posti",
    "seat",
    "seats",
    "data",
    "date",
];

/// Reads a ticket's number, coach and seat: from a row of column names
/// and the row of values after it (each cell a line, or cells between
/// "|"), else from words like "Carrozza: 9, Posto: 23".
fn train_seat(body: &str) -> Seated {
    let cells: Vec<&str> = body
        .lines()
        .flat_map(|l| l.split('|'))
        .map(str::trim)
        .filter(|c| !c.is_empty())
        .collect();
    let head = |c: &str| TICKET_HEADS.contains(&c.trim_end_matches(':').to_lowercase().as_str());
    let mut out = Seated::default();
    let mut i = 0;
    while i < cells.len() {
        if !head(cells[i]) {
            i += 1;
            continue;
        }
        let start = i;
        while i < cells.len() && head(cells[i]) {
            i += 1;
        }
        let names = &cells[start..i];
        let Some(values) = cells.get(i..i + names.len()) else {
            break;
        };
        for (name, value) in names.iter().zip(values) {
            let name = name.trim_end_matches(':').to_lowercase();
            let value = value.trim();
            let digits = |n: usize| {
                value.len() <= n && value.chars().next().is_some_and(|c| c.is_ascii_digit())
            };
            match name.as_str() {
                "n.treno" | "n. treno" | "treno" | "numero treno" | "train"
                    if out.number.is_empty()
                        && value.len() <= 5
                        && value.chars().all(|c| c.is_ascii_digit()) =>
                {
                    out.number = value.to_owned();
                }
                "carrozza" | "coach" if out.coach.is_empty() && digits(2) => {
                    out.coach = value.to_owned();
                }
                "posto" | "posti" | "seat" | "seats" if out.seat.is_empty() && digits(4) => {
                    out.seat = value.to_owned();
                }
                _ => {}
            }
        }
        i += names.len();
    }
    if out.number.is_empty() {
        out.number = TRAIN_NUMBER
            .captures(body)
            .map(|c| c[1].to_owned())
            .unwrap_or_default();
    }
    if out.coach.is_empty() {
        out.coach = COACH
            .captures(body)
            .map(|c| c[1].to_owned())
            .unwrap_or_default();
    }
    if out.seat.is_empty() {
        out.seat = TRAIN_SEAT
            .captures(body)
            .map(|c| c[1].to_owned())
            .unwrap_or_default();
    }
    out
}

/// Where a flight goes from and to: "Milan (MXP) … Lisbon (LIS)", or
/// "MXP → LIS".
fn route(text: &str) -> Option<(String, String, String, String)> {
    let airports: Vec<(String, String)> = AIRPORT
        .captures_iter(text)
        .filter(|c| !NOT_AIRPORTS.contains(&&c[2]))
        .map(|c| {
            (
                c[2].to_owned(),
                c.get(1)
                    .map(|m| m.as_str().trim().to_owned())
                    .unwrap_or_default(),
            )
        })
        .collect();
    if let [from, to, ..] = airports.as_slice() {
        if from.0 != to.0 {
            return Some((from.0.clone(), from.1.clone(), to.0.clone(), to.1.clone()));
        }
    }
    ROUTE
        .captures_iter(text)
        .find(|c| !NOT_AIRPORTS.contains(&&c[1]) && !NOT_AIRPORTS.contains(&&c[2]) && c[1] != c[2])
        .map(|c| {
            (
                c[1].to_owned(),
                String::new(),
                c[2].to_owned(),
                String::new(),
            )
        })
}

/// A sale on a second-hand site, as its emails tell the seller: sold,
/// to ship by a day, on its way, received by the buyer, paid out. A
/// buyer's emails say "seller" and are parcels.
fn sale(subject: &str, body: &str, received: Day) -> Option<Card> {
    let s = subject.to_lowercase();
    let lower = body.to_lowercase();
    let words = format!("{s}\n{lower}");
    let has = |list: &[&str]| list.iter().any(|w| words.contains(w));
    let sold = has(&[
        "hai venduto",
        "you sold",
        "you've sold",
        "item sold",
        "your item sold",
        "has been sold",
        "è stato venduto",
        "è stata venduta",
        "venduto!",
        "sold!",
    ]);
    let to_ship = has(&[
        "ship by",
        "ship it by",
        "ship your item",
        "please ship",
        "spedisci",
        "da spedire",
        "stampa l'etichetta",
        "print the label",
        "print your label",
        "shipping label",
        "etichetta di spedizione",
    ]);
    let buyer = has(&["buyer", "acquirente", "compratore"]);
    let paid_out = has(&[
        "payout",
        "paid out",
        "hai ricevuto il pagamento",
        "il pagamento è stato trasferito",
        "trasferito sul tuo",
        "accreditato sul tuo",
        "transferred to your",
        "money is on its way",
    ]);
    let delivered = has(&[
        "buyer received",
        "buyer has received",
        "picked up by the buyer",
        "delivered to the buyer",
        "acquirente ha ricevuto",
        "compratore ha ricevuto",
        "ritirato dall'acquirente",
        "consegnato all'acquirente",
    ]);
    let shipped = has(&[
        "you shipped",
        "hai spedito",
        "on its way to the buyer",
        "in viaggio verso l'acquirente",
        "spedizione registrata",
    ]);
    if !sold && !(buyer && (to_ship || paid_out || delivered || shipped)) {
        return None;
    }
    let stage = if delivered || paid_out {
        Stage::Delivered
    } else if shipped {
        Stage::Transit
    } else {
        Stage::Ordered
    };
    let ship_by = [
        "ship by",
        "ship it by",
        "spedisci entro",
        "spediscilo entro",
        "spediscila entro",
        "da spedire entro",
        "entro il",
    ]
    .iter()
    .find_map(|k| {
        let at = lower.find(k)?;
        parse_day_near(body.get(at + k.len()..)?, received)
    });
    let title = quoted(subject)
        .or_else(|| line_after(body, &["articolo", "item", "prodotto", "oggetto"]))
        .unwrap_or_default();
    let order = ORDER
        .captures(body)
        .map(|c| c[1].to_owned())
        .unwrap_or_default();
    let found = money_near(
        body,
        &[
            "you'll receive",
            "riceverai",
            "you earned",
            "hai guadagnato",
            "prezzo",
            "price",
            "totale",
            "total",
            "importo",
            "amount",
        ],
    );
    let tracking = tracking_number(body);
    Some(Card {
        kind: Kind::Sale,
        key: if order.is_empty() {
            key("sale", &title.to_lowercase())
        } else {
            key("sale", &order)
        },
        title,
        stage,
        day: if stage == Stage::Ordered {
            ship_by.map(|d| d.to_string()).unwrap_or_default()
        } else {
            String::new()
        },
        carrier: CARRIERS
            .iter()
            .find(|c| contains_word(&lower, &c.to_lowercase()))
            .map(|c| (*c).to_owned())
            .unwrap_or_default(),
        tracking,
        amount: found.as_ref().map(|(a, _)| *a),
        currency: found.map(|(_, c)| c).unwrap_or_default(),
        paid: paid_out,
        ..Card::default()
    })
}

/// The first sum within the words after one of `keys`, else the only
/// sum the text has.
fn money_near(body: &str, keys: &[&str]) -> Option<(i64, String)> {
    let lower = body.to_lowercase();
    keys.iter()
        .find_map(|k| {
            let at = lower.find(k)?;
            let rest = body.get(at + k.len()..)?;
            let window: String = rest.chars().take(80).collect();
            money(&window)
        })
        .or_else(|| {
            let all: Vec<(i64, String)> = AMOUNT
                .captures_iter(body)
                .filter_map(|c| money(&c[0]))
                .collect();
            match all.as_slice() {
                [one] => Some(one.clone()),
                [first, rest @ ..] if rest.iter().all(|a| a == first) => Some(first.clone()),
                _ => None,
            }
        })
}

static VOUCHER_CODE: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(?i:\b(?:claim code|gift card code|card number|codice del buono|codice regalo|codice della carta|codice|code|pin))\s*[:#]?\s*([A-Z0-9][A-Z0-9-]{5,28}[A-Z0-9])\b",
    )
});

/// A gift card or a voucher: its code, what it is worth, until when.
fn voucher(body: &str, received: Day) -> Option<Card> {
    let code = VOUCHER_CODE
        .captures_iter(body)
        .map(|c| c[1].to_owned())
        .find(|c| c.len() >= 8 && c.chars().any(|ch| ch.is_ascii_digit() || ch == '-'))
        .unwrap_or_default();
    let found = money_near(
        body,
        &[
            "valore", "value", "importo", "amount", "saldo", "balance", "credito", "credit",
        ],
    );
    if code.is_empty() && found.is_none() {
        return None;
    }
    let lower = body.to_lowercase();
    let until = [
        "valid until",
        "valid through",
        "expires on",
        "expires",
        "expiry date",
        "valido fino al",
        "valida fino al",
        "utilizzabile entro il",
        "scade il",
        "scadenza",
    ]
    .iter()
    .find_map(|k| {
        let at = find_word(&lower, k)?;
        parse_day_near(body.get(at + k.len()..)?, received)
    });
    Some(Card {
        kind: Kind::Voucher,
        key: key("voucher", &code),
        code,
        amount: found.as_ref().map(|(a, _)| *a),
        currency: found.map(|(_, c)| c).unwrap_or_default(),
        until: until.map(|d| d.to_string()).unwrap_or_default(),
        ..Card::default()
    })
}

/// A date that costs you if missed: an insurance renewal, a document's
/// expiry, a payment notice, a fine. Only a day the email states.
fn deadline(subject: &str, body: &str, received: Day) -> Option<Card> {
    let lower = body.to_lowercase();
    let day = [
        "expires on",
        "will expire on",
        "expiry date",
        "expiration date",
        "valid until",
        "due date",
        "due by",
        "pay by",
        "scade il",
        "scadrà il",
        "data di scadenza",
        "in scadenza il",
        "da pagare entro",
        "pagare entro",
        "entro il",
        "scadenza",
        "expires",
    ]
    .iter()
    .find_map(|k| {
        let at = find_word(&lower, k)?;
        parse_day_near(body.get(at + k.len()..)?, received)
    })
    .or_else(|| find_day(subject, received))?;
    let found = money_near(
        body,
        &[
            "importo",
            "amount",
            "da pagare",
            "to pay",
            "premio",
            "premium",
            "totale",
            "total",
        ],
    );
    Some(Card {
        kind: Kind::Deadline,
        day: day.to_string(),
        amount: found.as_ref().map(|(a, _)| *a),
        currency: found.map(|(_, c)| c).unwrap_or_default(),
        ..Card::default()
    })
}

/// A payslip, a statement, a tax form or a contract, kept for its PDF:
/// without one there is nothing to keep.
fn document(lower_subject: &str, src: &Source) -> Option<Card> {
    if !src.attachments.iter().any(is_pdf) {
        return None;
    }
    let is = |words: &[&str]| words.iter().any(|w| lower_subject.contains(w));
    let status = if is(&["busta paga", "cedolino", "payslip", "pay slip"]) {
        "payslip"
    } else if is(&["estratto conto", "statement", "rendiconto"]) {
        "statement"
    } else if is(&["contratto"]) {
        "contract"
    } else {
        "tax"
    };
    Some(Card {
        kind: Kind::Document,
        status: status.into(),
        ..Card::default()
    })
}

static RETURNS: LazyLock<Regex> = LazyLock::new(|| {
    re(
        r"(?i)\b([0-9]{1,3})[\s-]*(?:days?|giorni)\b[^.\n]{0,30}?\b(?:to return|for returns|returns?|reso|resi|recesso|restitu)|\b(?:return|returns|reso|resi|recesso|restituire|restituirlo)\b[^.\n]{0,40}?\b([0-9]{1,3})\s*(?:days?|giorni)\b",
    )
});

/// The days a shop gives to send things back: "100 days to return",
/// "reso gratuito entro 30 giorni". 0 when the email doesn't say.
fn return_days(body: &str) -> u32 {
    RETURNS
        .captures(body)
        .and_then(|c| c.get(1).or_else(|| c.get(2)))
        .and_then(|m| m.as_str().parse().ok())
        .filter(|d| (1..=365).contains(d))
        .unwrap_or(0)
}

fn shipment(subject: &str, body: &str, received: Day) -> Option<Card> {
    let tracking = tracking_number(body);
    let stage = stage_in(subject).or_else(|| stage_in(body));
    // A parcel needs a number to follow, or a subject that says where it is.
    if tracking.is_empty() && stage_in(subject).is_none_or(|s| s == Stage::Ordered) {
        return None;
    }
    let order = ORDER
        .captures(body)
        .map(|c| c[1].to_owned())
        .unwrap_or_default();
    let lower = body.to_lowercase();
    let carrier = CARRIERS
        .iter()
        .find(|c| contains_word(&lower, &c.to_lowercase()))
        .map(|c| (*c).to_owned())
        .unwrap_or_default();
    let expected = [
        "arriving",
        "arrives",
        "expected delivery",
        "expected",
        "estimated delivery",
        "delivery date",
        "delivery by",
        "delivered by",
        "consegna prevista",
        "data di consegna",
        "arriverà",
        "in arrivo",
    ]
    .iter()
    .find_map(|k| {
        let at = lower.find(k)?;
        let rest = body.get(at + k.len()..)?;
        parse_day_near(rest, received)
    });
    let title = quoted(subject).unwrap_or_default();
    // Waiting at a pick-up point, until the day it goes back.
    let words = format!("{}\n{lower}", subject.to_lowercase());
    let pickup = PICKUP.iter().any(|w| words.contains(w));
    let until = pickup
        .then(|| {
            [
                "ritiralo entro",
                "ritira entro",
                "ritirarlo entro",
                "collect it by",
                "pick it up by",
                "collect by",
                "fino al",
                "until",
                "entro il",
                "entro",
            ]
            .iter()
            .find_map(|k| {
                let at = lower.find(k)?;
                parse_day_near(body.get(at + k.len()..)?, received)
            })
        })
        .flatten();
    // What the order cost, for Spending.
    let found = money_near(
        body,
        &["order total", "totale ordine", "totale", "total", "importo"],
    );
    Some(Card {
        kind: Kind::Shipment,
        key: if tracking.is_empty() {
            key("order", &order)
        } else {
            key("ship", &tracking)
        },
        title,
        carrier,
        tracking,
        stage: if pickup {
            Stage::Transit
        } else {
            stage.unwrap_or(Stage::Ordered)
        },
        status: if pickup {
            "pickup".into()
        } else {
            String::new()
        },
        until: until.map(|d| d.to_string()).unwrap_or_default(),
        day: expected.map(|d| d.to_string()).unwrap_or_default(),
        last_scan: last_scan(body),
        amount: found.as_ref().map(|(a, _)| *a),
        currency: found.map(|(_, c)| c).unwrap_or_default(),
        ..Card::default()
    })
}

/// A parcel waiting at a pick-up point or a locker.
const PICKUP: &[&str] = &[
    "ready for pick",
    "ready to collect",
    "ready for collection",
    "waiting for you at",
    "pronto per il ritiro",
    "pronto da ritirare",
    "disponibile per il ritiro",
    "in giacenza",
    "ritira il tuo pacco",
    "ritiralo entro",
];

/// The rest of the line after "Last scan:", where and when the parcel was
/// last seen: "Last scan: Bologna, 6:40".
fn last_scan(body: &str) -> String {
    const KEYS: [&str; 8] = [
        "last scan",
        "latest scan",
        "last update",
        "latest update",
        "last location",
        "ultima scansione",
        "ultimo aggiornamento",
        "ultima posizione",
    ];
    for line in body.lines() {
        let lower = line.to_lowercase();
        for k in KEYS {
            let Some(at) = find_word(&lower, k) else {
                continue;
            };
            // Lowercasing can change byte lengths; step over the key by chars.
            let skip = lower[..at + k.len()].chars().count();
            let rest: String = line.chars().skip(skip).collect();
            let rest = rest
                .trim_start_matches([':', '-', '–', '·', ' ', '\t'])
                .trim();
            if !rest.is_empty() {
                return rest
                    .chars()
                    .take(60)
                    .collect::<String>()
                    .trim_end()
                    .to_owned();
            }
        }
    }
    String::new()
}

/// What a subject puts in quotes, often the item: Shipped: "Desk lamp".
fn quoted(s: &str) -> Option<String> {
    for (open, close) in [('"', '"'), ('“', '”'), ('«', '»')] {
        if let Some((_, rest)) = s.split_once(open) {
            if let Some((inside, _)) = rest.split_once(close) {
                let inside = inside.trim();
                if !inside.is_empty() {
                    return Some(inside.to_owned());
                }
            }
        }
    }
    None
}

fn contains_word(haystack: &str, word: &str) -> bool {
    find_word(haystack, word).is_some()
}

/// Where `word` first stands on its own in `haystack`.
fn find_word(haystack: &str, word: &str) -> Option<usize> {
    haystack.match_indices(word).map(|(i, _)| i).find(|&i| {
        let before = haystack[..i].chars().next_back();
        let after = haystack[i + word.len()..].chars().next();
        before.is_none_or(|c| !c.is_alphanumeric()) && after.is_none_or(|c| !c.is_alphanumeric())
    })
}

fn tracking_number(body: &str) -> String {
    if let Some(m) = UPS.find(body) {
        return m.as_str().to_owned();
    }
    for c in TRACKING.captures_iter(body) {
        // The number runs while its pieces look like one: capitals and
        // digits, nothing like the next word.
        let m = c.get(1).expect("group");
        let mut captured = m.as_str();
        // A capture that stopped inside a word ("… IT Segui") leaves that word out.
        if body[m.end()..]
            .chars()
            .next()
            .is_some_and(char::is_alphanumeric)
        {
            captured = captured
                .rsplit_once([' ', '-'])
                .map_or("", |(head, _)| head);
        }
        let mut pieces = Vec::new();
        for piece in captured.split([' ', '-']) {
            let looks = !piece.is_empty()
                && piece
                    .chars()
                    .all(|ch| ch.is_ascii_uppercase() || ch.is_ascii_digit())
                && (piece.chars().any(|ch| ch.is_ascii_digit()) || piece.len() <= 3);
            if !looks {
                break;
            }
            pieces.push(piece);
        }
        // Not a lone short word: a number has digits, and enough of them.
        while pieces
            .last()
            .is_some_and(|p| !p.chars().any(|ch| ch.is_ascii_digit()) && p.len() > 2)
        {
            pieces.pop();
        }
        let number = pieces.join(" ");
        if number.chars().filter(char::is_ascii_digit).count() >= 6 {
            return number;
        }
    }
    String::new()
}

fn stage_in(text: &str) -> Option<Stage> {
    let t = text.to_lowercase();
    let has = |words: &[&str]| words.iter().any(|w| t.contains(w));
    if has(&[
        "has been delivered",
        "was delivered",
        "delivered:",
        "delivered today",
        "è stato consegnato",
        "è stata consegnata",
        "consegnato",
        "consegna effettuata",
    ]) || t.trim_start().starts_with("delivered")
    {
        Some(Stage::Delivered)
    } else if has(PICKUP)
        || has(&[
            "out for delivery",
            "in consegna",
            "in transit",
            "in transito",
            "on its way",
            "on the way",
            "in arrivo",
            "arriving",
        ])
    {
        Some(Stage::Transit)
    } else if has(&[
        "shipped",
        "dispatched",
        "has been sent",
        "spedito",
        "spedita",
        "è partito",
    ]) {
        Some(Stage::Shipped)
    } else if has(&[
        "order confirm",
        "order received",
        "thank you for your order",
        "ordine confermato",
        "conferma d'ordine",
        "conferma ordine",
        "grazie per il tuo ordine",
    ]) {
        Some(Stage::Ordered)
    } else {
        None
    }
}

fn bill(subject: &str, body: &str, received: Day) -> Option<Card> {
    let lower = body.to_lowercase();
    let s = subject.to_lowercase();
    let words = format!("{s}\n{lower}");
    // Money coming back, or coming in, is never spending.
    let refund = ["refund", "rimborso", "rimborsato", "rimborsata"]
        .iter()
        .any(|w| s.contains(w))
        || [
            "you've received a refund",
            "you have received a refund",
            "your refund",
            "has been refunded",
            "hai ricevuto un rimborso",
            "ti abbiamo rimborsato",
            "è stato rimborsato",
        ]
        .iter()
        .any(|w| lower.contains(w));
    let money_in = !refund && MONEY_IN.iter().any(|w| words.contains(w));
    // The amount near "total" or "to pay", else the only one there is.
    let found = money_near(
        body,
        &[
            "amount due",
            "total due",
            "balance due",
            "to pay",
            "da pagare",
            "importo",
            "totale",
            "total",
            "amount",
        ],
    );
    let failed = says_failed(subject, body);
    let paid = says_paid(subject, body);
    let plan = PLAN_WORDS.iter().any(|w| words.contains(w));
    let day_after = |keys: &[&str]| {
        keys.iter().find_map(|k| {
            let at = find_word(&lower, k)?;
            parse_day_near(body.get(at + k.len()..)?, received)
        })
    };
    let renews = plan.then(|| day_after(RENEWS)).flatten();
    let ending = plan.then(|| day_after(ENDS)).flatten();
    let status = if failed {
        "failed"
    } else if refund {
        "refund"
    } else if money_in {
        "in"
    } else if !paid && ending.is_some() {
        "ending"
    } else if !paid && renews.is_some() {
        "renews"
    } else {
        ""
    };
    // A charge that failed, or a plan about to renew or end, needs you
    // even when the email names no sum.
    let (amount, currency) = match found {
        Some((amount, currency)) => (Some(amount), currency),
        None if matches!(status, "failed" | "renews" | "ending") => (None, String::new()),
        None => return None,
    };
    // Only a bill to pay has a day it is due.
    let due = status
        .is_empty()
        .then(|| {
            day_after(&[
                "payment due",
                "due date",
                "due by",
                "due on",
                "pay by",
                "data di scadenza",
                "in scadenza",
                "scadenza",
                "scade il",
                "da pagare entro",
                "entro il",
                "due",
            ])
        })
        .flatten();
    Some(Card {
        kind: Kind::Bill,
        amount,
        currency,
        paid,
        status: status.into(),
        period: if plan { period_of(&words) } else { "" }.into(),
        until: ending.or(renews).map(|d| d.to_string()).unwrap_or_default(),
        day: due.map(|d| d.to_string()).unwrap_or_default(),
        ..Card::default()
    })
}

/// Money someone sent you, or earned: never spending.
const MONEY_IN: &[&str] = &[
    "you received a payment",
    "you've received a payment",
    "you have received a payment",
    "you've got money",
    "has sent you",
    "sent you a payment",
    "ti ha inviato un pagamento",
    "ti ha inviato denaro",
    "hai ricevuto un pagamento",
    "hai ricevuto denaro",
    "hai ricevuto un bonifico",
    "bonifico in entrata",
    "bonifico ricevuto",
    "accredito",
    "payout",
    "royalt",
    "your earnings",
    "i tuoi guadagni",
    "you earned",
    "hai guadagnato",
];

/// Where a plan says when it charges next.
const RENEWS: &[&str] = &[
    "renews on",
    "will renew on",
    "will renew",
    "renewal date",
    "next billing date",
    "next payment date",
    "next payment",
    "next charge",
    "prossimo rinnovo",
    "prossimo addebito",
    "si rinnoverà il",
    "si rinnoverà",
    "rinnovo automatico il",
    "data di rinnovo",
    "verrà rinnovato il",
    "sarà rinnovato il",
];

/// Where a plan says when it ends.
const ENDS: &[&str] = &[
    "will end on",
    "ends on",
    "will expire on",
    "expires on",
    "access until",
    "trial ends",
    "scadrà il",
    "terminerà il",
    "termina il",
    "attivo fino al",
];

/// How often a plan charges, from "/month", "annual", "al mese".
fn period_of(words: &str) -> &'static str {
    let has = |list: &[&str]| list.iter().any(|w| words.contains(w));
    if has(&["/week", "per week", "weekly", "a settimana", "settimanale"]) {
        "week"
    } else if has(&[
        "/year", "/yr", "per year", "a year", "yearly", "annual", "all'anno", "/anno", "annuale",
    ]) {
        "year"
    } else if has(&[
        "/month",
        "/mo",
        "per month",
        "a month",
        "monthly",
        "al mese",
        "/mese",
        "mensile",
    ]) {
        "month"
    } else {
        ""
    }
}

/// The subject or text says the money went: a receipt, "Payment
/// Successful", "payment to …". A charge that failed is still to pay.
pub fn says_paid(subject: &str, body: &str) -> bool {
    let s = subject.to_lowercase();
    let lower = body.to_lowercase();
    !says_failed(subject, body)
        && ([
            "receipt",
            "ricevuta",
            "payment received",
            "payment successful",
            "payment confirmation",
            "payment complete",
            "payment to ",
            "pagamento ricevuto",
            "pagamento riuscito",
            "pagamento completato",
            "conferma di pagamento",
        ]
        .iter()
        .any(|w| s.contains(w))
            || [
                "payment received",
                "payment successful",
                "payment was successful",
                "payment is complete",
                "successfully paid",
                "amount paid",
                "you paid",
                "thank you for your payment",
                "has been charged",
                "we've charged",
                "pagamento ricevuto",
                "pagamento effettuato",
                "pagamento riuscito",
                "importo pagato",
                "abbiamo ricevuto il pagamento",
                "è stato addebitato",
            ]
            .iter()
            .any(|w| lower.contains(w)))
}

/// The subject or text says a charge didn't go through: "Failed
/// Payment", "we couldn't charge your card", "pagamento non riuscito".
pub fn says_failed(subject: &str, body: &str) -> bool {
    let s = subject.to_lowercase();
    let lower = body.to_lowercase();
    [
        "failed",
        "declined",
        "unsuccessful",
        "problem with your recent payment",
        "problem with your payment",
        "non riuscito",
        "rifiutato",
        "non è andato a buon fine",
    ]
    .iter()
    .any(|w| s.contains(w))
        || [
            "payment has failed",
            "payment failed",
            "payment was declined",
            "payment was unsuccessful",
            "was unsuccessful",
            "couldn't charge your",
            "could not charge your",
            "were unable to charge",
            "we were unable to process your payment",
            "pagamento non è andato a buon fine",
            "pagamento non riuscito",
            "pagamento è stato rifiutato",
            "non siamo riusciti ad addebitare",
            "impossibile addebitare",
        ]
        .iter()
        .any(|w| lower.contains(w))
}

/// The first amount in `text`, in cents, with its currency.
fn money(text: &str) -> Option<(i64, String)> {
    let c = AMOUNT.captures(text)?;
    let (symbol, number) = match (c.get(1), c.get(2), c.get(3), c.get(4)) {
        (Some(s), Some(n), _, _) => (s.as_str(), n.as_str()),
        (_, _, Some(n), Some(s)) => (s.as_str(), n.as_str()),
        _ => return None,
    };
    let currency = match symbol.to_lowercase().as_str() {
        "€" | "eur" | "euro" => "EUR",
        "$" | "usd" => "USD",
        "£" | "gbp" => "GBP",
        "chf" => "CHF",
        _ => return None,
    };
    Some((parse_amount(number)?, currency.to_owned()))
}

/// "1.234,56", "1,234.56", "64.20", "64,20" or "39" in cents.
fn parse_amount(s: &str) -> Option<i64> {
    let s: String = s.chars().filter(|c| !c.is_whitespace()).collect();
    let decimals = s
        .rfind(['.', ','])
        .filter(|&i| s.len() - i - 1 == 2)
        .map(|i| (&s[..i], &s[i + 1..]));
    let (whole, cents) = decimals.unwrap_or((s.as_str(), "00"));
    let whole: String = whole.chars().filter(char::is_ascii_digit).collect();
    if whole.is_empty() {
        return None;
    }
    Some(whole.parse::<i64>().ok()? * 100 + cents.parse::<i64>().ok()?)
}

// ---------------------------------------------------------------------------
// Reminders

/// Settings: notify on a parcel's delivery day, and before a bill is due.
pub const NOTIFY_PARCELS: &str = "vault.notify_parcels";
pub const NOTIFY_DUE: &str = "vault.notify_due";

/// How many days ahead a bill is worth a notice.
pub const DUE_AHEAD: i64 = 3;

/// What a Vault notice is about (`Notifications`, "Piuma · Vault").
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Remind {
    /// A parcel arrives today.
    Parcel,
    /// A bill is due in this many days (0: today).
    Due(i64),
}

impl Remind {
    /// Kept so each card gives one notice of each kind.
    pub fn tag(self) -> &'static str {
        match self {
            Remind::Parcel => "parcel",
            Remind::Due(_) => "due",
        }
    }
}

/// What a card is worth reminding of on [today], if anything: a parcel
/// not delivered yet on its day, a bill not paid within [DUE_AHEAD] days
/// of its due date.
pub fn remind(card: &Card, today: Day) -> Option<Remind> {
    let day = parse_iso(&card.day)?;
    let left = day.number() - today.number();
    match card.kind {
        Kind::Shipment if left == 0 && card.stage != Stage::Delivered => Some(Remind::Parcel),
        Kind::Bill | Kind::Deadline
            if !card.paid && card.status.is_empty() && (0..=DUE_AHEAD).contains(&left) =>
        {
            Some(Remind::Due(left))
        }
        _ => None,
    }
}

impl Day {
    /// The day it is at Unix time [unix], [offset_minutes] east of UTC.
    pub fn local(unix: i64, offset_minutes: i32) -> Day {
        day_of(unix + i64::from(offset_minutes) * 60)
    }
}

// ---------------------------------------------------------------------------
// Days

/// A calendar day.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord)]
pub struct Day {
    pub year: i32,
    pub month: u32,
    pub day: u32,
}

impl std::fmt::Display for Day {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{:04}-{:02}-{:02}", self.year, self.month, self.day)
    }
}

impl Day {
    fn new(year: i32, month: u32, day: u32) -> Option<Day> {
        let days = match month {
            1 | 3 | 5 | 7 | 8 | 10 | 12 => 31,
            4 | 6 | 9 | 11 => 30,
            2 if year % 4 == 0 && (year % 100 != 0 || year % 400 == 0) => 29,
            2 => 28,
            _ => return None,
        };
        (1..=days)
            .contains(&day)
            .then_some(Day { year, month, day })
    }

    /// Days since 1970-01-01.
    fn number(self) -> i64 {
        let (y, m) = if self.month <= 2 {
            (self.year as i64 - 1, self.month as i64 + 9)
        } else {
            (self.year as i64, self.month as i64 - 3)
        };
        let era = y.div_euclid(400);
        let yoe = y - era * 400;
        let doy = (153 * m + 2) / 5 + self.day as i64 - 1;
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;
        era * 146_097 + doe - 719_468
    }

    fn from_number(n: i64) -> Day {
        let z = n + 719_468;
        let era = z.div_euclid(146_097);
        let doe = z - era * 146_097;
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        let mp = (5 * doy + 2) / 153;
        let day = (doy - (153 * mp + 2) / 5 + 1) as u32;
        let month = if mp < 10 { mp + 3 } else { mp - 9 } as u32;
        let year = (yoe + era * 400 + i64::from(month <= 2)) as i32;
        Day { year, month, day }
    }

    fn plus(self, days: i64) -> Day {
        Day::from_number(self.number() + days)
    }
}

/// The day (UTC) of a Unix time.
fn day_of(unix: i64) -> Day {
    Day::from_number(unix.div_euclid(86_400))
}

fn parse_iso(s: &str) -> Option<Day> {
    let mut parts = s.splitn(3, '-');
    let y = parts.next()?.parse().ok()?;
    let m = parts.next()?.parse().ok()?;
    let d = parts.next()?.parse().ok()?;
    Day::new(y, m, d)
}

const MONTHS: &[(&str, u32)] = &[
    ("january", 1),
    ("february", 2),
    ("march", 3),
    ("april", 4),
    ("may", 5),
    ("june", 6),
    ("july", 7),
    ("august", 8),
    ("september", 9),
    ("october", 10),
    ("november", 11),
    ("december", 12),
    ("gennaio", 1),
    ("febbraio", 2),
    ("marzo", 3),
    ("aprile", 4),
    ("maggio", 5),
    ("giugno", 6),
    ("luglio", 7),
    ("agosto", 8),
    ("settembre", 9),
    ("ottobre", 10),
    ("novembre", 11),
    ("dicembre", 12),
    ("sept", 9),
    ("jan", 1),
    ("feb", 2),
    ("mar", 3),
    ("apr", 4),
    ("jun", 6),
    ("jul", 7),
    ("aug", 8),
    ("sep", 9),
    ("oct", 10),
    ("nov", 11),
    ("dec", 12),
    ("gen", 1),
    ("mag", 5),
    ("giu", 6),
    ("lug", 7),
    ("ago", 8),
    ("set", 9),
    ("ott", 10),
    ("dic", 12),
];

static NUMERIC_DAY: LazyLock<Regex> = LazyLock::new(|| {
    re(r"^(\d{4})-(\d{2})-(\d{2})|^(\d{1,2})[/.](\d{1,2})(?:[/.](\d{4}|\d{2}))?\b")
});
static DAY_MONTH: LazyLock<Regex> =
    LazyLock::new(|| re(r"^(\d{1,2})(?:st|nd|rd|th)?\s+([\p{L}]+)\.?(?:,?\s+(\d{4}))?"));
static MONTH_DAY: LazyLock<Regex> =
    LazyLock::new(|| re(r"^([\p{L}]+)\.?\s+(\d{1,2})(?:st|nd|rd|th)?\b(?:,?\s+(\d{4}))?"));

fn month(word: &str) -> Option<u32> {
    let w = word.to_lowercase();
    MONTHS.iter().find(|(name, _)| *name == w).map(|(_, m)| *m)
}

/// A year an email left out: the one that puts the day closest after it
/// arrived (a bill due in January, sent in December, is next year's).
fn with_year(month: u32, day: u32, year: Option<i32>, received: Day) -> Option<Day> {
    if let Some(y) = year {
        return Day::new(y, month, day);
    }
    let this = Day::new(received.year, month, day)?;
    if this.number() < received.number() - 60 {
        Day::new(received.year + 1, month, day)
    } else {
        Some(this)
    }
}

/// A day at the very start of `s`, after any weekday and "on"/"il".
fn parse_day(s: &str, received: Day) -> Option<Day> {
    let mut s = s.trim_start_matches(|c: char| c.is_whitespace() || c == ':' || c == ',');
    let lower = s.to_lowercase();
    for (word, add) in [("today", 0), ("oggi", 0), ("tomorrow", 1), ("domani", 1)] {
        if lower.starts_with(word) {
            return Some(received.plus(add));
        }
    }
    // Leading words that carry no date: "on", "il", "by", a weekday.
    for _ in 0..3 {
        let word: String = s.chars().take_while(|c| c.is_alphabetic()).collect();
        let w = word.to_lowercase();
        let skip = ["on", "by", "il", "entro", "the", "del", "per"].contains(&w.as_str())
            || (w.len() >= 3
                && [
                    "monday",
                    "tuesday",
                    "wednesday",
                    "thursday",
                    "friday",
                    "saturday",
                    "sunday",
                    "lunedì",
                    "martedì",
                    "mercoledì",
                    "giovedì",
                    "venerdì",
                    "sabato",
                    "domenica",
                ]
                .iter()
                .any(|d| d.starts_with(&w)));
        if !skip || word.is_empty() {
            break;
        }
        s = s[word.len()..].trim_start_matches(|c: char| c.is_whitespace() || c == ',' || c == '.');
    }
    if let Some(c) = NUMERIC_DAY.captures(s) {
        if let Some(y) = c.get(1) {
            return Day::new(
                y.as_str().parse().ok()?,
                c[2].parse().ok()?,
                c[3].parse().ok()?,
            );
        }
        let (a, b): (u32, u32) = (c[4].parse().ok()?, c[5].parse().ok()?);
        // Day first, as in Europe, unless that can't be.
        let (day, month) = if b > 12 { (b, a) } else { (a, b) };
        let year = c.get(6).and_then(|y| {
            let y: i32 = y.as_str().parse().ok()?;
            Some(if y < 100 { 2000 + y } else { y })
        });
        return with_year(month, day, year, received);
    }
    if let Some(c) = DAY_MONTH.captures(s) {
        if let Some(m) = month(&c[2]) {
            let year = c.get(3).and_then(|y| y.as_str().parse().ok());
            return with_year(m, c[1].parse().ok()?, year, received);
        }
    }
    if let Some(c) = MONTH_DAY.captures(s) {
        if let Some(m) = month(&c[1]) {
            let year = c.get(3).and_then(|y| y.as_str().parse().ok());
            return with_year(m, c[2].parse().ok()?, year, received);
        }
    }
    None
}

/// A day within the first words of `s`.
fn parse_day_near(s: &str, received: Day) -> Option<Day> {
    let window: String = s.chars().take(40).collect();
    let mut at = 0;
    while at < window.len() {
        if let Some(d) = parse_day(&window[at..], received) {
            return Some(d);
        }
        // Next word.
        let next = window[at..]
            .char_indices()
            .skip_while(|(_, c)| !c.is_whitespace())
            .find(|(_, c)| !c.is_whitespace())
            .map(|(i, _)| at + i);
        match next {
            Some(n) => at = n,
            None => break,
        }
    }
    None
}

/// The first day written anywhere in `s`.
fn find_day(s: &str, received: Day) -> Option<Day> {
    s.char_indices()
        .filter(|(i, c)| {
            c.is_alphanumeric()
                && s[..*i]
                    .chars()
                    .next_back()
                    .is_none_or(|p| !p.is_alphanumeric())
        })
        .find_map(|(i, _)| {
            let rest = &s[i..];
            let first = rest.chars().next()?;
            // Bare words are not days: only numbers and month names start one.
            let word: String = rest.chars().take_while(|c| c.is_alphabetic()).collect();
            (first.is_ascii_digit() || month(&word).is_some())
                .then(|| parse_day(rest, received))
                .flatten()
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Thursday, October 15, 2026, 10:30 UTC.
    const OCT_15: i64 = 1_792_060_200;

    fn src<'a>(subject: &'a str, text: &'a str, html: Option<&'a str>) -> Source<'a> {
        Source {
            subject,
            from_name: "Shop",
            message_id: "<m1@example.com>",
            received_at: OCT_15,
            text,
            html,
            attachments: &[],
        }
    }

    #[test]
    fn days_count_from_1970() {
        let d = day_of(OCT_15);
        assert_eq!(d.to_string(), "2026-10-15");
        assert_eq!(Day::from_number(d.number()), d);
        assert_eq!(d.plus(17).to_string(), "2026-11-01");
        assert_eq!(
            Day::new(2028, 2, 29).unwrap().plus(1).to_string(),
            "2028-03-01"
        );
    }

    #[test]
    fn days_are_read_as_written() {
        let r = day_of(OCT_15);
        let p = |s| parse_day(s, r).map(|d| d.to_string());
        assert_eq!(p("October 30").as_deref(), Some("2026-10-30"));
        assert_eq!(p("30 ottobre 2026").as_deref(), Some("2026-10-30"));
        assert_eq!(p("Fri, Oct 23").as_deref(), Some("2026-10-23"));
        assert_eq!(p("venerdì 23 ottobre").as_deref(), Some("2026-10-23"));
        assert_eq!(p("30/10/2026").as_deref(), Some("2026-10-30"));
        assert_eq!(p("2026-10-30").as_deref(), Some("2026-10-30"));
        assert_eq!(p("tomorrow").as_deref(), Some("2026-10-16"));
        assert_eq!(p("domani").as_deref(), Some("2026-10-16"));
        // Sent in October, due in January: next year's.
        assert_eq!(p("15 January").as_deref(), Some("2027-01-15"));
        assert_eq!(p("hello"), None);
    }

    #[test]
    fn amounts_in_cents() {
        assert_eq!(parse_amount("64.20"), Some(6420));
        assert_eq!(parse_amount("64,20"), Some(6420));
        assert_eq!(parse_amount("1.234,56"), Some(123_456));
        assert_eq!(parse_amount("1,234.56"), Some(123_456));
        assert_eq!(parse_amount("39"), Some(3900));
        assert_eq!(money("€ 64,20"), Some((6420, "EUR".into())));
        assert_eq!(money("64,20 EUR"), Some((6420, "EUR".into())));
        assert_eq!(money("$12.50"), Some((1250, "USD".into())));
    }

    #[test]
    fn subjects_worth_a_look() {
        assert!(candidate("Your order has shipped"));
        assert!(candidate("La tua bolletta di ottobre"));
        assert!(candidate("Carta d'imbarco: volo VL 482"));
        assert!(!candidate("Lunch on Friday?"));
    }

    #[test]
    fn a_parcel_from_schema_org() {
        let html = r#"<html><head><script type="application/ld+json">
        {"@context":"http://schema.org","@type":"ParcelDelivery",
         "carrier":{"@type":"Organization","name":"Corriere Rapido"},
         "trackingNumber":"CR 7741 2093 IT",
         "itemShipped":{"@type":"Product","name":"Desk lamp"},
         "expectedArrivalUntil":"2026-10-16T18:00:00+02:00",
         "deliveryStatus":"http://schema.org/OrderInTransit",
         "partOfOrder":{"@type":"Order","merchant":{"@type":"Organization","name":"Casa&Luce"}}}
        </script></head><body><p>On its way</p></body></html>"#;
        let card = extract(&src("Your order is on its way", "", Some(html))).unwrap();
        assert_eq!(card.kind, Kind::Shipment);
        assert_eq!(card.title, "Desk lamp");
        assert_eq!(card.merchant, "Casa&Luce");
        assert_eq!(card.carrier, "Corriere Rapido");
        assert_eq!(card.tracking, "CR 7741 2093 IT");
        assert_eq!(card.key, "ship:CR77412093IT");
        assert_eq!(card.stage, Stage::Transit);
        assert_eq!(card.day, "2026-10-16");
    }

    #[test]
    fn vat_belongs_to_the_merchant_not_the_customer_or_carrier() {
        for (kind, merchant) in [
            ("Invoice", "provider"),
            ("Invoice", "broker"),
            ("Order", "merchant"),
            ("Order", "seller"),
        ] {
            let value = serde_json::json!({
                "@type": kind,
                merchant: {"name": "Shop", "vatID": " IT01234567890 "},
                "customer": {"vatID": "IT99999999999"}
            });
            let card = from_item(&value).unwrap();
            assert_eq!(card.vat_number, "IT01234567890");
            let mut without_merchant_vat = value;
            without_merchant_vat[merchant]
                .as_object_mut()
                .unwrap()
                .remove("vatID");
            assert!(from_item(&without_merchant_vat)
                .unwrap()
                .vat_number
                .is_empty());
        }
        let invoice = serde_json::json!({
            "@type": "Invoice",
            "provider": {"name": "Shop"},
            "broker": {"name": "Payment service", "vatID": "LU999999999"}
        });
        assert!(from_item(&invoice).unwrap().vat_number.is_empty());
        let parcel = serde_json::json!({
            "@type": "ParcelDelivery",
            "carrier": {"vatID": "IT99999999999"},
            "partOfOrder": {"seller": {"name": "Shop", "vatID": "IT01234567890"}}
        });
        assert_eq!(from_item(&parcel).unwrap().vat_number, "IT01234567890");
    }

    #[test]
    fn old_cards_without_vat_still_load() {
        let card: Card = serde_json::from_str(r#"{"kind":"bill","merchant":"Shop"}"#).unwrap();
        assert!(card.vat_number.is_empty());
        assert_eq!(card.merchant, "Shop");
    }

    #[test]
    fn a_flight_from_schema_org() {
        let html = r#"<script type="application/ld+json">[{"@context":"http://schema.org",
          "@type":"FlightReservation","reservationNumber":"Q7X2LM",
          "airplaneSeat":"14A",
          "reservationFor":{"@type":"Flight","flightNumber":"482",
            "airline":{"@type":"Airline","name":"Volare","iataCode":"VL"},
            "departureAirport":{"@type":"Airport","name":"Milan","iataCode":"MXP"},
            "departureTime":"2026-10-23T07:15:00+02:00",
            "arrivalAirport":{"@type":"Airport","name":"Lisbon","iataCode":"LIS"},
            "arrivalTime":"2026-10-23T09:05:00+01:00"}}]</script>"#;
        let card = extract(&src("Your booking", "", Some(html))).unwrap();
        assert_eq!(card.kind, Kind::Flight);
        assert_eq!(card.number, "VL 482");
        assert_eq!(
            (card.origin.as_str(), card.origin_city.as_str()),
            ("MXP", "Milan")
        );
        assert_eq!(card.destination, "LIS");
        assert_eq!(
            (card.day.as_str(), card.time.as_str()),
            ("2026-10-23", "07:15")
        );
        assert_eq!(card.arrives, "09:05");
        assert_eq!((card.seat.as_str(), card.code.as_str()), ("14A", "Q7X2LM"));
        assert_eq!(card.key, "trip:Q7X2LM");
    }

    #[test]
    fn a_table_from_schema_org() {
        let html = r#"<script type="application/ld+json">{"@context":"http://schema.org",
          "@type":"FoodEstablishmentReservation","reservationStatus":"http://schema.org/ReservationConfirmed",
          "partySize":"4","startTime":"2026-10-16T20:30:00+02:00",
          "reservationFor":{"@type":"FoodEstablishment","name":"Osteria del Ponte",
            "address":{"@type":"PostalAddress","streetAddress":"Via del Ponte 3","addressLocality":"Bologna"}}}</script>"#;
        let card = extract(&src("Reservation confirmed", "", Some(html))).unwrap();
        assert_eq!(card.kind, Kind::Booking);
        assert_eq!(card.title, "Osteria del Ponte");
        assert_eq!(
            (card.day.as_str(), card.time.as_str()),
            ("2026-10-16", "20:30")
        );
        assert_eq!(card.party, 4);
        assert_eq!(card.status, "confirmed");
        assert_eq!(card.address, "Via del Ponte 3, Bologna");
    }

    #[test]
    fn an_invoice_from_schema_org() {
        let html = r#"<script type="application/ld+json">{"@context":"http://schema.org","@type":"Invoice",
          "description":"Electricity bill · October","provider":{"@type":"Organization","name":"EnergiaVerde"},
          "totalPaymentDue":{"@type":"PriceSpecification","price":"64.20","priceCurrency":"EUR"},
          "paymentDueDate":"2026-10-30","paymentStatus":"http://schema.org/PaymentDue"}</script>"#;
        let card = extract(&src("Your bill", "", Some(html))).unwrap();
        assert_eq!(card.kind, Kind::Bill);
        assert_eq!(card.title, "Electricity bill · October");
        assert_eq!(card.merchant, "EnergiaVerde");
        assert_eq!((card.amount, card.currency.as_str()), (Some(6420), "EUR"));
        assert_eq!(card.day, "2026-10-30");
        assert!(!card.paid);
    }

    #[test]
    fn a_bill_in_plain_italian() {
        let text = "Gentile cliente,\n\nla bolletta di ottobre è disponibile.\n\nTotale da pagare: 64,20 €\nScadenza: 30/10/2026\n\nEnergiaVerde";
        let card = extract(&src("La tua bolletta di ottobre", text, None)).unwrap();
        assert_eq!(card.kind, Kind::Bill);
        assert_eq!(card.title, "La tua bolletta di ottobre");
        assert_eq!(card.merchant, "Shop");
        assert_eq!((card.amount, card.currency.as_str()), (Some(6420), "EUR"));
        assert_eq!(card.day, "2026-10-30");
        assert!(!card.paid);
    }

    #[test]
    fn a_train_ticket_from_italo() {
        let text = "Conferma acquisto biglietto\n\nCodice biglietto BIYIKN\n\nAndata\n\nData\n20/10\nOrari\n16:35 > 17:20\nItinerario\nReggio Em. AV - MI CENTRALE\n\nCarrozza 4 Posto 16";
        let card = extract(&src("Italo – Conferma Acquisto", text, None)).unwrap();
        assert_eq!(card.kind, Kind::Booking);
        assert_eq!(card.title, "Reggio Em. AV → MI CENTRALE");
        assert_eq!(card.day, "2026-10-20");
        assert_eq!(
            (card.time.as_str(), card.arrives.as_str()),
            ("16:35", "17:20")
        );
        assert_eq!(card.code, "BIYIKN");
        assert_eq!(card.key, "trip:BIYIKN");
    }

    #[test]
    fn a_failed_charge_without_a_sum_still_asks() {
        let text = "we couldn't charge your card for a recent invoice\n\nHi, your recent Acme payment has failed because of a problem with your credit card.\nUpdate credit card details";
        let card = extract(&src(
            "There was a problem with your recent payment for Acme",
            text,
            None,
        ))
        .unwrap();
        assert_eq!(card.kind, Kind::Bill);
        assert_eq!(card.amount, None);
        assert_eq!(card.status, "failed");
        assert!(!card.paid);
        // The retries of the same charge are one card.
        let mut again = src("Your payment failed", "Your payment failed.", None);
        again.message_id = "<retry@example.com>";
        assert_eq!(extract(&again).unwrap().key, card.key);
        assert_eq!(card.key, "bill:failed:shop");
        // A sum that failed is a failed bill too, not a receipt.
        let card = extract(&src(
            "Payment receipt",
            "Your payment of US$ 15.25 was unsuccessful. Please update your card.",
            None,
        ))
        .unwrap();
        assert_eq!((card.amount, card.status.as_str()), (Some(1525), "failed"));
        assert!(!card.paid);
        // Plain mail about payments makes no card.
        assert!(extract(&src(
            "Your payment method has been updated",
            "Your PayPal account was updated.",
            None
        ))
        .is_none());
    }

    #[test]
    fn a_ticket_tells_train_coach_and_seat() {
        // Each table cell on its own line, as the reader lays them out.
        let cells = "Codice biglietto ABCDEF\n\nData\n\n20/10\n\nOrari\n\n16:35 > 17:20\n\nItinerario\n\nCittà A - CITTA B\n\nOrari\n\nN.Treno\n\nAmbiente\n\n16:35 > 17:20\n\n8000\n\nSmart\n\nCarrozza\n\nPosto\n\n4\n\n16";
        let card = extract(&src("Treno – Conferma Acquisto biglietto", cells, None)).unwrap();
        assert_eq!(card.kind, Kind::Booking);
        assert_eq!(
            (
                card.number.as_str(),
                card.coach.as_str(),
                card.seat.as_str()
            ),
            ("8000", "4", "16")
        );
        // Cells between bars, as a plain-text part draws a table.
        let bars = "| Codice biglietto ABCDEF |\n| Data |\n| 20/10 |\n| Orari | N.Treno | Ambiente |\n| 16:35 > 17:20 | 8000 | Smart |\n| Carrozza | Posto |\n| 4 | 16 |";
        let card = extract(&src("Treno – Conferma Acquisto biglietto", bars, None)).unwrap();
        assert_eq!(
            (
                card.number.as_str(),
                card.coach.as_str(),
                card.seat.as_str()
            ),
            ("8000", "4", "16")
        );
        // Words in a line.
        let line = "Treno 9900 Codice Biglietto (PNR): GHIJKL Carrozza: 9, Posto: 23 Partenza 10:40 > 11:26 Data 19/10";
        let card = extract(&src("Il tuo biglietto del treno", line, None)).unwrap();
        assert_eq!(
            (
                card.number.as_str(),
                card.coach.as_str(),
                card.seat.as_str()
            ),
            ("9900", "9", "23")
        );
    }

    #[test]
    fn the_post_says_which_parcel_arrived() {
        let text = "Consegnata al destinatario\nGentile CLIENTE, ti informiamo che la spedizione F000D42400001 è stata consegnata il giorno 14.10.2026 alle ore 10:24.";
        let card = extract(&src("Consegnata al destinatario", text, None)).unwrap();
        assert_eq!(card.kind, Kind::Shipment);
        assert_eq!(card.stage, Stage::Delivered);
        assert_eq!(card.key, "ship:F000D42400001");
        // "Spedizione gratuita" is no number.
        assert!(extract(&src(
            "Il tuo ordine",
            "Spedizione GRATUITA in 3 giorni.",
            None
        ))
        .is_none());
    }

    #[test]
    fn a_refund_is_money_back_not_a_bill() {
        let text = "Zalando ti ha inviato un rimborso.\nImporto: 215,93 €\nData: 7 agosto 2026";
        let back = extract(&src("Hai ricevuto un rimborso da Zalando", text, None)).unwrap();
        assert_eq!((back.kind, back.status.as_str()), (Kind::Bill, "refund"));
        assert_eq!(back.amount, Some(21593));
        assert!(back.day.is_empty());
        let text = "Your refund of €215.93 has been processed.\nTotal: €215.93";
        let back = extract(&src("Payment update", text, None)).unwrap();
        assert_eq!(back.status, "refund");
    }

    #[test]
    fn reminders_of_one_bill_make_one_card() {
        let text = "We couldn't take your payment.\nAmount due: €29.00";
        let first = extract(&src("Failed Payment", text, None)).unwrap();
        let mut again = src("Failed Payment", text, None);
        again.message_id = "<other@example.com>";
        assert_eq!(extract(&again).unwrap().key, first.key);
        let other = "We couldn't take your payment.\nAmount due: €49.00";
        assert_ne!(
            extract(&src("Failed Payment", other, None)).unwrap().key,
            first.key
        );
    }

    #[test]
    fn a_payment_that_went_through_is_paid() {
        let paid = [
            ("Payment Successful for order at rrk", "Total: 11,61 €"),
            ("€6.10 payment to Anthropic Ireland", "Amount: €6.10"),
        ];
        for (subject, text) in paid {
            let card = extract(&src(subject, text, None)).unwrap();
            assert_eq!(card.kind, Kind::Bill);
            assert!(card.paid, "{subject}");
        }
        let card = extract(&src(
            "Blackmagic Cloud Failed Payment",
            "We could not charge your card. Amount due: $15.25",
            None,
        ))
        .unwrap();
        assert!(!card.paid);
    }

    #[test]
    fn a_receipt_is_paid() {
        let text = "Thanks for your payment.\nGym membership, October\nTotal: €39.00";
        let card = extract(&src("Your receipt from Palestra", text, None)).unwrap();
        assert_eq!(card.amount, Some(3900));
        assert!(card.paid);
    }

    #[test]
    fn a_tracking_number_names_its_carrier() {
        assert_eq!(carrier_of("1Z 999 AA1 0123 4567 84"), Some("UPS"));
        assert_eq!(carrier_of("1Z999AA10123456785"), None);
        assert_eq!(carrier_of("RR123456785IT"), Some("Poste Italiane"));
        assert_eq!(carrier_of("RR123456786IT"), None);
        assert_eq!(carrier_of("RR123456785GB"), Some("Royal Mail"));
        assert_eq!(carrier_of("TBA123456789012"), Some("Amazon Logistics"));
        assert_eq!(carrier_of("JJD0123456789"), Some("DHL"));
        // Plain digits could be anyone's.
        assert_eq!(carrier_of("123456789012"), None);
    }

    #[test]
    fn a_parcel_opens_the_emails_own_link_else_the_carriers_page() {
        let text = "Your parcel is on its way.\nTracking number: RR123456785IT\nFollow it: https://shop.example/track?n=RR123456785IT&amp;l=it";
        let card = extract(&src("Your order has shipped", text, None)).unwrap();
        assert_eq!(card.carrier, "Poste Italiane");
        assert_eq!(
            card.track_url,
            "https://shop.example/track?n=RR123456785IT&l=it"
        );

        let text = "Your parcel is on its way.\nTracking number: 1Z999AA10123456784";
        let card = extract(&src("Your order has shipped", text, None)).unwrap();
        assert_eq!(card.carrier, "UPS");
        assert_eq!(
            card.track_url,
            "https://www.ups.com/track?tracknum=1Z999AA10123456784"
        );

        // A carrier with no page known, and no link: nothing to open.
        let text = "Your parcel is on its way with Nexive.\nTracking number: 4455667788990";
        let card = extract(&src("Your order has shipped", text, None)).unwrap();
        assert!(card.track_url.is_empty());
    }

    #[test]
    fn a_parcel_in_plain_words() {
        let text = "Good news! Your order 402-1234567 has shipped with DHL.\nTracking number: JD014600006281234567\nExpected delivery: Friday, October 16";
        let card = extract(&src("Shipped: \"Wireless headphones\"", text, None)).unwrap();
        assert_eq!(card.kind, Kind::Shipment);
        assert_eq!(card.title, "Wireless headphones");
        assert_eq!(card.carrier, "DHL");
        assert_eq!(card.tracking, "JD014600006281234567");
        assert_eq!(card.stage, Stage::Shipped);
        assert_eq!(card.day, "2026-10-16");
        assert_eq!(card.last_scan, "");
    }

    #[test]
    fn a_parcel_says_where_it_was_last_seen() {
        let text = "Your parcel is on its way with DHL.\nTracking number: JD014600006281234567\nLast scan: Bologna, 6:40\nExpected delivery: Friday, October 16";
        let card = extract(&src("Shipped: \"Desk lamp\"", text, None)).unwrap();
        assert_eq!(card.last_scan, "Bologna, 6:40");
        let text = "Il tuo pacco è in viaggio.\nCodice di tracciamento: CR 7741 2093 IT\nUltimo aggiornamento – Centro di smistamento Milano, 21:15";
        let card = extract(&src("Spedito: il tuo ordine", text, None)).unwrap();
        assert_eq!(card.last_scan, "Centro di smistamento Milano, 21:15");
        assert_eq!(last_scan("Last update:\nnothing here"), "");
    }

    #[test]
    fn a_tracking_number_stops_at_the_next_word() {
        assert_eq!(
            tracking_number("Codice di tracciamento: CR 7741 2093 IT Segui il pacco"),
            "CR 7741 2093 IT"
        );
        assert_eq!(tracking_number("Tracking: soon"), "");
    }

    #[test]
    fn a_delivered_parcel() {
        let text = "Il tuo pacco è stato consegnato.\nNumero di spedizione: 1Z999AA10123456784";
        let card = extract(&src("Consegnato: il tuo ordine", text, None)).unwrap();
        assert_eq!(card.stage, Stage::Delivered);
        assert_eq!(card.tracking, "1Z999AA10123456784");
        assert_eq!(card.key, "ship:1Z999AA10123456784");
    }

    #[test]
    fn a_flight_in_plain_words() {
        let text = "Your e-ticket\n\nFlight VL 482 · Friday 23 October 2026\nMilan (MXP) 07:15 → Lisbon (LIS) 09:05\nSeat 14A\nBooking reference: Q7X2LM";
        let card = extract(&src("Your flight to Lisbon", text, None)).unwrap();
        assert_eq!(card.kind, Kind::Flight);
        assert_eq!(card.number, "VL 482");
        assert_eq!(
            (card.origin.as_str(), card.origin_city.as_str()),
            ("MXP", "Milan")
        );
        assert_eq!(
            (card.destination.as_str(), card.destination_city.as_str()),
            ("LIS", "Lisbon")
        );
        assert_eq!(card.day, "2026-10-23");
        assert_eq!(
            (card.time.as_str(), card.arrives.as_str()),
            ("07:15", "09:05")
        );
        assert_eq!(card.seat, "14A");
        assert_eq!(card.code, "Q7X2LM");
    }

    #[test]
    fn ordinary_mail_makes_no_card() {
        assert!(extract(&src("Lunch on Friday?", "See you at 13:00", None)).is_none());
        // A bill word with no amount is not a bill.
        assert!(extract(&src("Billing question", "Can you call me?", None)).is_none());
        // An order with nothing to follow yet waits for the next email.
        assert!(extract(&src("Your order", "Thanks for shopping", None)).is_none());
    }

    #[test]
    fn the_pdf_goes_with_the_bill() {
        let files = [Attachment {
            part: 2,
            name: "bolletta.pdf".into(),
            mime: "application/pdf".into(),
            size: 1000,
            ..Default::default()
        }];
        let s = Source {
            attachments: &files,
            ..src("Fattura ottobre", "Importo: 64,20 €", None)
        };
        let card = extract(&s).unwrap();
        assert_eq!(
            (card.file, card.file_name.as_str()),
            (Some(2), "bolletta.pdf")
        );
    }
    #[test]
    fn reminds_of_parcels_on_their_day_and_bills_ahead() {
        let today = Day::new(2026, 10, 19).unwrap();
        let parcel = Card {
            kind: Kind::Shipment,
            day: "2026-10-19".into(),
            stage: Stage::Transit,
            ..Card::default()
        };
        assert_eq!(remind(&parcel, today), Some(Remind::Parcel));
        let delivered = Card {
            stage: Stage::Delivered,
            ..parcel.clone()
        };
        assert_eq!(remind(&delivered, today), None);
        let tomorrow = Card {
            day: "2026-10-20".into(),
            ..parcel
        };
        assert_eq!(remind(&tomorrow, today), None);
        let bill = Card {
            kind: Kind::Bill,
            day: "2026-10-22".into(),
            ..Card::default()
        };
        assert_eq!(remind(&bill, today), Some(Remind::Due(3)));
        assert_eq!(
            remind(
                &Card {
                    day: "2026-10-23".into(),
                    ..bill.clone()
                },
                today
            ),
            None
        );
        assert_eq!(
            remind(
                &Card {
                    day: "2026-10-18".into(),
                    ..bill.clone()
                },
                today
            ),
            None
        );
        assert_eq!(remind(&Card { paid: true, ..bill }, today), None);
        assert_eq!(remind(&Card::default(), today), None);
        // 23:30 UTC on the 18th is already the 19th in Rome.
        assert_eq!(Day::local(1_792_366_200, 120), today);
    }

    #[test]
    fn a_sale_says_what_to_ship_and_when_it_is_paid_out() {
        let text = "Congratulazioni, hai venduto il tuo articolo!\nArticolo: Climbing harness\nPrezzo: 45,00 €\nSpediscilo entro giovedì 22 ottobre.";
        let sold = extract(&src("Hai venduto \"Climbing harness\"", text, None)).unwrap();
        assert_eq!(sold.kind, Kind::Sale);
        assert_eq!(sold.title, "Climbing harness");
        assert_eq!(sold.stage, Stage::Ordered);
        assert_eq!(sold.day, "2026-10-22");
        assert_eq!(sold.amount, Some(4500));
        assert!(!sold.paid);
        let text =
            "L'acquirente ha ricevuto il pacco. Il pagamento è stato trasferito sul tuo conto.";
        let done = extract(&src("Vendita completata: \"Climbing harness\"", text, None)).unwrap();
        assert_eq!(done.kind, Kind::Sale);
        assert_eq!(done.key, sold.key);
        assert_eq!(done.stage, Stage::Delivered);
        assert!(done.paid);
        // A buyer's email is a parcel, not a sale.
        let text = "Il venditore ha spedito il tuo ordine.\nCodice di tracciamento: RB123456789IT";
        let bought = extract(&src("Il tuo ordine è stato spedito", text, None)).unwrap();
        assert_eq!(bought.kind, Kind::Shipment);
    }

    #[test]
    fn a_hotel_keeps_its_nights() {
        let text = "Prenotazione confermata\nStruttura: Casa do Rio\nCheck-in: venerdì 7 novembre 2026, dalle 15:00\nCheck-out: lunedì 10 novembre 2026, entro le 11:00\n2 adulti\nNumero di conferma: 48213377";
        let stay = extract(&src("La tua prenotazione è confermata", text, None)).unwrap();
        assert_eq!(stay.kind, Kind::Booking);
        assert_eq!(stay.travel, "stay");
        assert_eq!(stay.title, "Casa do Rio");
        assert_eq!(
            (stay.day.as_str(), stay.time.as_str()),
            ("2026-11-07", "15:00")
        );
        assert_eq!(
            (stay.until.as_str(), stay.arrives.as_str()),
            ("2026-11-10", "11:00")
        );
        assert_eq!(stay.party, 2);
    }

    #[test]
    fn a_car_park_runs_from_entry_to_exit() {
        let text = "Grazie per aver prenotato.\nParcheggio: StationPark Centrale\nIngresso: 19/10/2026 09:00\nUscita: 20/10/2026 23:45\nCodice prenotazione: 278179";
        let park = extract(&src("Conferma prenotazione parcheggio", text, None)).unwrap();
        assert_eq!(park.travel, "parking");
        assert_eq!(park.title, "StationPark Centrale");
        assert_eq!(
            (park.day.as_str(), park.time.as_str()),
            ("2026-10-19", "09:00")
        );
        assert_eq!(
            (park.until.as_str(), park.arrives.as_str()),
            ("2026-10-20", "23:45")
        );
        assert_eq!(park.code, "278179");
    }

    #[test]
    fn a_hired_car_and_a_ferry_are_trips() {
        let text = "Your car rental is confirmed.\nPick-up: 7 November 2026, 10:00\nDrop-off: 10 November 2026, 16:00\nBooking reference: CRX4821";
        let car = extract(&src("Car rental confirmation", text, None)).unwrap();
        assert_eq!(car.travel, "car");
        assert_eq!(car.title, "Shop");
        assert_eq!(car.until, "2026-11-10");
        let text = "Biglietto traghetto\nCodice prenotazione: FRY8824\nDa: Genova\nA: Olbia\nData: 3 novembre 2026\nPartenza 20:30\nArrivo 07:30";
        let ferry = extract(&src("Il tuo biglietto", text, None)).unwrap();
        assert_eq!(ferry.travel, "ferry");
        assert_eq!(ferry.title, "Genova → Olbia");
        assert_eq!(
            (ferry.time.as_str(), ferry.arrives.as_str()),
            ("20:30", "07:30")
        );
        assert_eq!(ferry.day, "2026-11-03");
    }

    #[test]
    fn tickets_for_a_show_are_an_event() {
        let text = "Ecco i tuoi biglietti.\nData: sabato 14 novembre 2026, ore 21:00\nLuogo: Teatro Verdi, Via Roma 1\n2 biglietti\nCodice ordine: TKT55120";
        let show = extract(&src("I tuoi biglietti per \"Notte di jazz\"", text, None)).unwrap();
        assert_eq!(show.travel, "event");
        assert_eq!(show.title, "Notte di jazz");
        assert_eq!(
            (show.day.as_str(), show.time.as_str()),
            ("2026-11-14", "21:00")
        );
        assert_eq!(show.address, "Teatro Verdi, Via Roma 1");
        assert_eq!(show.party, 2);
        // A support ticket is not a show.
        let text = "We received your request on 12 October 2026 at 10:00.";
        assert!(extract(&src("Your support ticket #4411", text, None)).is_none());
    }

    #[test]
    fn a_gift_card_keeps_its_code_and_expiry() {
        let text = "Hai ricevuto una carta regalo!\nValore: 50,00 €\nCodice: GC7X-29QP-LM4D\nValida fino al 31/12/2027";
        let card = extract(&src("La tua carta regalo", text, None)).unwrap();
        assert_eq!(card.kind, Kind::Voucher);
        assert_eq!(card.code, "GC7X-29QP-LM4D");
        assert_eq!(card.amount, Some(5000));
        assert_eq!(card.until, "2027-12-31");
    }

    #[test]
    fn a_deadline_states_its_day() {
        let text = "Gentile cliente, la sua polizza auto scade il 3 marzo 2027.\nPremio di rinnovo: 412,00 €";
        let due = extract(&src("Avviso di rinnovo polizza", text, None)).unwrap();
        assert_eq!(due.kind, Kind::Deadline);
        assert_eq!(due.day, "2027-03-03");
        assert_eq!(due.amount, Some(41200));
        let text = "Avviso di pagamento pagoPA\nImporto: 42,00 €\nDa pagare entro il 15/11/2026";
        let notice = extract(&src("Avviso di pagamento", text, None)).unwrap();
        assert_eq!(
            (notice.kind, notice.day.as_str()),
            (Kind::Deadline, "2026-11-15")
        );
        // Two reminders of one deadline are one card.
        let mut again = src("Avviso di pagamento", text, None);
        again.message_id = "<other@example.com>";
        assert_eq!(extract(&again).unwrap().key, notice.key);
    }

    #[test]
    fn a_payslip_is_a_document_with_its_file() {
        let files = [Attachment {
            part: 2,
            name: "cedolino_10_2026.pdf".into(),
            mime: "application/pdf".into(),
            ..Attachment::default()
        }];
        let mut mail = src(
            "Cedolino di ottobre",
            "In allegato il cedolino. Netto: 1.850,00 €",
            None,
        );
        mail.attachments = &files;
        let doc = extract(&mail).unwrap();
        assert_eq!((doc.kind, doc.status.as_str()), (Kind::Document, "payslip"));
        assert_eq!(doc.file, Some(2));
        // A statement with no file is nothing to keep, and never a bill.
        let text = "Il tuo estratto conto è disponibile. Saldo: 1.234,56 €";
        assert!(extract(&src("Estratto conto di ottobre", text, None)).is_none());
    }

    #[test]
    fn a_parcel_at_a_pick_up_point_says_until_when() {
        let text = "Il tuo pacco è pronto per il ritiro presso il punto selezionato.\nCodice di tracciamento: 3SXYZ0123456789\nRitiralo entro il 26 ottobre.";
        let parcel = extract(&src("Il tuo pacco è pronto per il ritiro", text, None)).unwrap();
        assert_eq!(parcel.kind, Kind::Shipment);
        assert_eq!(parcel.status, "pickup");
        assert_eq!(parcel.stage, Stage::Transit);
        assert_eq!(parcel.until, "2026-10-26");
    }

    #[test]
    fn an_order_tells_its_total_and_return_window() {
        let text = "Thank you for your order!\nOrder number: 1386597\nOrder total: €124.78\nYou have 100 days to return anything.";
        // Nothing to follow yet: a purchase, paid.
        let order = extract(&src("Order confirmation", text, None)).unwrap();
        assert_eq!(order.kind, Kind::Bill);
        assert!(order.paid);
        assert_eq!(order.amount, Some(12478));
        assert_eq!(order.return_days, 100);
        assert_eq!(
            return_days("Reso gratuito entro 30 giorni dalla consegna."),
            30
        );
        assert_eq!(return_days("Delivery in 3 days."), 0);
    }

    #[test]
    fn money_in_and_plans_are_told_apart() {
        let text = "Hai ricevuto un pagamento di 45,00 € da Daniel.";
        let got = extract(&src("Hai ricevuto denaro", text, None)).unwrap();
        assert_eq!((got.kind, got.status.as_str()), (Kind::Bill, "in"));
        let text =
            "Your DroneMap Base subscription renews on November 1, 2026.\nAmount: €19.00 per year";
        let renews = extract(&src("Your subscription renews soon", text, None)).unwrap();
        assert_eq!(renews.status, "renews");
        assert_eq!(renews.until, "2026-11-01");
        assert_eq!(renews.period, "year");
        assert!(renews.day.is_empty());
        let text = "Your Health Premium trial ends on October 27, 2026.";
        let ending = extract(&src("Your trial is ending", text, None)).unwrap();
        assert_eq!(
            (ending.status.as_str(), ending.until.as_str()),
            ("ending", "2026-10-27")
        );
        let text = "Receipt\nNotepad Cloud monthly subscription\nTotal: €9.99\nNext payment: November 16, 2026";
        let charged = extract(&src("Your receipt from Notepad Cloud", text, None)).unwrap();
        assert!(charged.paid);
        assert_eq!(charged.status, "");
        assert_eq!(
            (charged.period.as_str(), charged.until.as_str()),
            ("month", "2026-11-16")
        );
    }

    #[test]
    fn schema_reservations_tell_their_kind() {
        let html = r#"<script type="application/ld+json">{"@context":"http://schema.org","@type":"LodgingReservation","reservationNumber":"LX9","reservationFor":{"@type":"LodgingBusiness","name":"Casa do Rio","address":{"streetAddress":"Rua 1","addressLocality":"Lisboa"}},"checkinDate":"2026-11-07T15:00:00","checkoutDate":"2026-11-10T11:00:00"}</script>"#;
        let stay = extract(&src("Booking", "", Some(html))).unwrap();
        assert_eq!(
            (stay.travel.as_str(), stay.title.as_str()),
            ("stay", "Casa do Rio")
        );
        assert_eq!(
            (stay.day.as_str(), stay.until.as_str()),
            ("2026-11-07", "2026-11-10")
        );
        let html = r#"<script type="application/ld+json">{"@context":"http://schema.org","@type":"TrainReservation","reservationNumber":"K7RW2Q","reservationFor":{"@type":"TrainTrip","trainNumber":"8134","departureStation":{"name":"Reggio Emilia AV"},"arrivalStation":{"name":"Milano Centrale"},"departureTime":"2026-10-20T16:35:00","arrivalTime":"2026-10-20T17:20:00"},"reservedTicket":{"ticketedSeat":{"seatNumber":"16","seatSection":"4"}}}</script>"#;
        let ride = extract(&src("Ticket", "", Some(html))).unwrap();
        assert_eq!(ride.travel, "train");
        assert_eq!(ride.title, "Reggio Emilia AV → Milano Centrale");
        assert_eq!(
            (
                ride.number.as_str(),
                ride.coach.as_str(),
                ride.seat.as_str()
            ),
            ("8134", "4", "16")
        );
        assert_eq!(
            (ride.time.as_str(), ride.arrives.as_str()),
            ("16:35", "17:20")
        );
        assert!(ride.until.is_empty());
    }

    #[test]
    fn a_deadline_is_reminded_like_a_bill() {
        let today = Day::new(2026, 10, 15).unwrap();
        let card = Card {
            kind: Kind::Deadline,
            day: "2026-10-17".into(),
            ..Card::default()
        };
        assert_eq!(remind(&card, today), Some(Remind::Due(2)));
        let failed = Card {
            kind: Kind::Bill,
            day: "2026-10-16".into(),
            status: "renews".into(),
            ..Card::default()
        };
        assert_eq!(remind(&failed, today), None);
    }
}
