//! Translation on the device where the system has none of its own
//! (Windows, Linux, Android): Firefox's open translation models, run by
//! `fxtranslate`. A language pair is downloaded once into the app's data
//! folder, then everything happens here; the email's words never leave.
//!
//! The models come from Mozilla's Remote Settings, hash-checked. Pairs
//! without a model of their own go through English, as Firefox does.

use std::collections::HashMap;
use std::io::SeekFrom;
use std::path::PathBuf;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::mpsc::{channel, Sender};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use fxtranslate::cache::Cache;
use fxtranslate::engine::Translation;
use fxtranslate::fetch::{DownloadOutcome, Fetch, FetchError, Sink};
use fxtranslate::remote::{fetch_records, pick, Record};
use fxtranslate::route::{resolve_route, Route, PREFERRED_HUB};

/// Whether a pair translates on this device.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum PairStatus {
    /// Downloaded: translating starts at once.
    Ready,
    /// There are models for it, downloaded first (once).
    Download,
    /// No model for it, or none known while offline.
    Unsupported,
}

/// How far a download is, 0 to 1.
/// What [Report] gets once the models are ready and the text is being
/// translated, instead of a download fraction.
pub const TRANSLATING: f64 = -1.0;

pub type Report = Arc<dyn Fn(f64) + Send + Sync>;

/// The pairs open in memory, on the one thread they live on (the models
/// hold buffers that may not move between threads).
type Open = HashMap<(String, String), Translation>;
type Job = Box<dyn FnOnce(&mut Open) + Send>;

/// The pairs downloaded under one folder, and the thread that translates.
pub struct Translator {
    root: PathBuf,
    cache: Cache,
    records: Mutex<Option<Arc<Vec<Record>>>>,
    worker: Mutex<Sender<Job>>,
}

impl Translator {
    /// Models go under `root` (the app's data folder).
    pub fn new(root: impl Into<PathBuf>) -> Translator {
        let root = root.into();
        let (worker, jobs) = channel::<Job>();
        std::thread::Builder::new()
            .name("piuma-translate".into())
            .spawn(move || {
                let mut open = Open::new();
                for job in jobs {
                    job(&mut open);
                }
            })
            .expect("a translation thread");
        Translator {
            cache: Cache::with_root(root.clone()),
            root,
            records: Mutex::default(),
            worker: Mutex::new(worker),
        }
    }

    /// What `from`→`to` needs here. Asks Mozilla's list of models (once
    /// per run) only for a pair not downloaded yet.
    pub fn status(&self, from: &str, to: &str) -> PairStatus {
        if from == to {
            return PairStatus::Unsupported;
        }
        if self.downloaded(from, to) {
            return PairStatus::Ready;
        }
        match self.records().map(|r| resolve_route(&r, from, to)) {
            Ok(Ok(_)) => PairStatus::Download,
            _ => PairStatus::Unsupported,
        }
    }

    /// About how many bytes the pair still downloads, for "Getting
    /// German–English · 28 MB".
    pub fn download_size(&self, from: &str, to: &str) -> Option<u64> {
        let records = self.records().ok()?;
        let files = self.missing(&records, from, to).ok()?;
        let fetch = Web::new(None);
        let mut total = 0;
        for r in files {
            total += fetch.size(&r.cdn_url())?;
        }
        Some(total)
    }

    /// `texts` in `to`, one for one. A pair not downloaded yet is fetched
    /// first, telling `progress` how far it is (0 to 1).
    pub fn translate(
        &self,
        texts: Vec<String>,
        from: &str,
        to: &str,
        progress: Report,
    ) -> Result<Vec<String>, String> {
        let key = (from.to_owned(), to.to_owned());
        // Bytes still to come, so the line under the pill fills evenly.
        let total = if self.downloaded(from, to) {
            None
        } else {
            self.download_size(from, to)
        };
        let root = self.root.clone();
        let (done, result) = channel();
        self.run(Box::new(move |open: &mut Open| {
            let translated = (|| {
                if !open.contains_key(&key) {
                    let fetch = Web::new(Some(Progress {
                        done: AtomicU64::new(0),
                        total,
                        report: progress.clone(),
                    }));
                    let t = fxtranslate::loader::load_translation(
                        &fetch,
                        &Cache::with_root(root),
                        &key.0,
                        &key.1,
                    )?;
                    open.insert(key.clone(), t);
                }
                // Nothing left to download: the pill says "Translating" now.
                (progress)(TRANSLATING);
                Ok(paragraphs(&open[&key], &texts))
            })();
            let _ = done.send(translated);
        }))?;
        result
            .recv()
            .map_err(|_| "the translation stopped".to_owned())?
    }

    fn run(&self, job: Job) -> Result<(), String> {
        self.worker
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .send(job)
            .map_err(|_| "the translation thread is gone".to_owned())
    }

    /// The pairs downloaded, as "de-en", with their size in bytes.
    pub fn downloaded_pairs(&self) -> Vec<(String, u64)> {
        self.cache
            .list_cached()
            .unwrap_or_default()
            .into_iter()
            .map(|p| (p.name, p.bytes))
            .collect()
    }

    /// Deletes a downloaded pair ("de-en").
    pub fn remove(&self, name: &str) -> Result<(), String> {
        let name = name.to_owned();
        let root = self.root.clone();
        let (done, result) = channel();
        self.run(Box::new(move |open: &mut Open| {
            open.retain(|(f, t), _| format!("{f}-{t}") != name);
            let _ = done.send(Cache::with_root(root).remove_pair(&name).map(|_| ()));
        }))?;
        result
            .recv()
            .map_err(|_| "the translation stopped".to_owned())?
    }

    fn downloaded(&self, from: &str, to: &str) -> bool {
        let has = |f: &str, t: &str| self.cache.cached_model(f, t).is_some();
        has(from, to)
            || (from != PREFERRED_HUB
                && to != PREFERRED_HUB
                && has(from, PREFERRED_HUB)
                && has(PREFERRED_HUB, to))
    }

    fn records(&self) -> Result<Arc<Vec<Record>>, String> {
        let mut kept = self.records.lock().unwrap_or_else(|e| e.into_inner());
        if let Some(r) = kept.as_ref() {
            return Ok(r.clone());
        }
        let r = Arc::new(fetch_records(&Web::new(None))?);
        *kept = Some(r.clone());
        Ok(r)
    }

    /// The files of the pair's route not on this device yet.
    fn missing(&self, records: &[Record], from: &str, to: &str) -> Result<Vec<Record>, String> {
        let legs = match resolve_route(records, from, to)? {
            Route::Direct { src, trg } => vec![(src, trg)],
            Route::Pivot { src, pivot, trg } => vec![(src, pivot.clone()), (pivot, trg)],
        };
        let mut out = Vec::new();
        for (src, trg) in legs {
            if self.cache.cached_model(&src, &trg).is_some() {
                continue;
            }
            for kind in ["model", "vocab", "srcvocab", "trgvocab", "lex"] {
                out.extend(pick(records, kind, &src, &trg).cloned());
            }
        }
        Ok(out)
    }
}

/// [texts] in the pair's language, line by line so line breaks stay where
/// they were. Lines go to a few threads at once: the model is shared, so this
/// costs only scratch memory, and a long email is done several times faster.
fn paragraphs(t: &Translation, texts: &[String]) -> Vec<String> {
    let mut lines: Vec<Vec<String>> = texts
        .iter()
        .map(|text| text.split('\n').map(str::to_owned).collect())
        .collect();
    let mut todo: Vec<&mut String> = lines
        .iter_mut()
        .flatten()
        .filter(|line| !line.trim().is_empty())
        .collect();
    let workers = std::thread::available_parallelism()
        .map_or(1, |n| n.get())
        .clamp(1, 4);
    let chunk = todo.len().div_ceil(workers).max(1);
    std::thread::scope(|scope| {
        for part in todo.chunks_mut(chunk) {
            scope.spawn(move || {
                for line in part {
                    **line = t.translate_long(line);
                }
            });
        }
    });
    lines.into_iter().map(|text| text.join("\n")).collect()
}

struct Progress {
    done: AtomicU64,
    total: Option<u64>,
    report: Report,
}

/// Mozilla's servers through the app's own web client (its certificates
/// and proxy), called from a thread that may block.
struct Web {
    progress: Option<Progress>,
}

impl Web {
    fn new(progress: Option<Progress>) -> Web {
        Web { progress }
    }

    fn client(timeout: Option<Duration>) -> Result<reqwest::Client, String> {
        let mut b = crate::tls::http_client().connect_timeout(Duration::from_secs(15));
        if let Some(t) = timeout {
            b = b.timeout(t);
        }
        b.build().map_err(|e| e.to_string())
    }

    fn block<T>(future: impl std::future::Future<Output = T>) -> T {
        match tokio::runtime::Handle::try_current() {
            Ok(h) => tokio::task::block_in_place(|| h.block_on(future)),
            Err(_) => tokio::runtime::Builder::new_current_thread()
                .enable_all()
                .build()
                .expect("a runtime")
                .block_on(future),
        }
    }

    fn size(&self, url: &str) -> Option<u64> {
        Self::block(async {
            let r = Self::client(Some(Duration::from_secs(15)))
                .ok()?
                .head(url)
                .send()
                .await
                .ok()?;
            // A HEAD has no body, so its length is read off the header.
            let length = r.headers().get(reqwest::header::CONTENT_LENGTH)?;
            r.status()
                .is_success()
                .then(|| length.to_str().ok()?.parse().ok())?
        })
    }
}

impl Fetch for Web {
    fn get(&self, url: &str) -> Result<Vec<u8>, String> {
        Self::block(async {
            let r = Self::client(Some(Duration::from_secs(30)))?
                .get(url)
                .send()
                .await
                .map_err(|e| e.to_string())?;
            if !r.status().is_success() {
                return Err(format!("{url}: {}", r.status()));
            }
            Ok(r.bytes().await.map_err(|e| e.to_string())?.to_vec())
        })
    }

    fn get_to(
        &self,
        url: &str,
        range_from: u64,
        sink: &mut dyn Sink,
        on_progress: &mut dyn FnMut(u64, Option<u64>),
    ) -> Result<DownloadOutcome, FetchError> {
        let failed = |message: String, retryable: bool| FetchError { message, retryable };
        Self::block(async {
            let mut req = Self::client(None).map_err(|e| failed(e, false))?.get(url);
            if range_from > 0 {
                req = req.header(reqwest::header::RANGE, format!("bytes={range_from}-"));
            }
            let mut r = req.send().await.map_err(|e| failed(e.to_string(), true))?;
            let status = r.status();
            if !status.is_success() {
                return Err(failed(
                    format!("{url}: {status}"),
                    fxtranslate::fetch::status_is_retryable(status.as_u16()),
                ));
            }
            let resumed = status == reqwest::StatusCode::PARTIAL_CONTENT;
            let start = if resumed { range_from } else { 0 };
            sink.seek(SeekFrom::Start(start))
                .map_err(|e| failed(e.to_string(), false))?;
            let total = r.content_length().map(|l| l + start);
            let mut have = start;
            while let Some(chunk) = r.chunk().await.map_err(|e| failed(e.to_string(), true))? {
                sink.write_all(&chunk)
                    .map_err(|e| failed(e.to_string(), false))?;
                have += chunk.len() as u64;
                on_progress(have, total);
                if let Some(p) = &self.progress {
                    let done = p.done.fetch_add(chunk.len() as u64, Ordering::Relaxed)
                        + chunk.len() as u64;
                    if let Some(all) = p.total.filter(|t| *t > 0) {
                        (p.report)((done as f64 / all as f64).min(1.0));
                    }
                }
            }
            Ok(DownloadOutcome { resumed, total })
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nothing_downloaded_is_not_ready() {
        let dir = std::env::temp_dir().join(format!("piuma-translate-{}", std::process::id()));
        let t = Translator::new(&dir);
        assert!(!t.downloaded("de", "en"));
        assert!(t.downloaded_pairs().is_empty());
        assert_eq!(t.status("it", "it"), PairStatus::Unsupported);
        std::fs::remove_dir_all(&dir).ok();
    }
}

#[cfg(test)]
mod online {
    use super::*;

    /// Downloads German–English from Mozilla: `cargo test -- --ignored`.
    #[test]
    #[ignore]
    fn translates_german_after_one_download() {
        let dir = std::env::temp_dir().join("piuma-translate-online");
        let t = Translator::new(&dir);
        assert_eq!(t.status("de", "en"), PairStatus::Download);
        let size = t.download_size("de", "en").unwrap();
        assert!(size > 1_000_000, "{size}");
        let seen = Arc::new(Mutex::new(0.0f64));
        let kept = seen.clone();
        let out = t
            .translate(
                vec![
                    "Hallo Matteo,\nwie geht es dir?".to_owned(),
                    "die Lampen für das Studio kommen nächste Woche. Passt dir Dienstag um 10 Uhr? \
                     Ich bringe auch die Muster für den Flur mit."
                        .to_owned(),
                ],
                "de",
                "en",
                Arc::new(move |p| {
                    let mut seen = kept.lock().unwrap();
                    *seen = seen.max(p);
                }),
            )
            .unwrap();
        println!("{out:?} after {size} bytes");
        let at = std::time::Instant::now();
        let again = t
            .translate(
                vec!["Ich bringe auch die Muster für den Flur mit.\n8,36 EUR | Gesamt".to_owned()],
                "de",
                "en",
                Arc::new(|_| {}),
            )
            .unwrap();
        println!("{again:?}");
        println!("again in {:?}", at.elapsed());
        assert!(again[0].contains('|'), "{again:?}");
        assert!(out[0].contains('\n'));
        assert!(*seen.lock().unwrap() > 0.9);
        assert_eq!(t.status("de", "en"), PairStatus::Ready);
        std::fs::remove_dir_all(&dir).ok();
    }
}
