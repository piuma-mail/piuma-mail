//! Deadlines for a mail connection: a server that stops answering, or
//! one that sends far more than it should, ends the command with an error
//! instead of keeping the watcher, or a person opening a message, waiting
//! for ever.
//!
//! The deadline follows progress rather than the clock: a command fails
//! once the server has sent nothing for [`Limits::stall`] while an answer
//! is awaited, however long the answer takes as a whole. A 100 MB message
//! that keeps arriving is fine; a NOOP nobody answers is not. Sending a
//! command starts its count afresh.
//!
//! The same wrapper counts what each command brings back and refuses more
//! than its budget, whatever the server declared beforehand
//! (`RFC822.SIZE` is only a claim).

use std::future::Future;
use std::io;
use std::pin::Pin;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::task::{Context, Poll};
use std::time::Duration;

use tokio::io::{AsyncRead, AsyncWrite, ReadBuf};
use tokio::time::Sleep;

/// How long a connection may stay silent while an answer is awaited, and
/// how much one command may bring back. Shared between a connection and
/// its wrapper, so each phase (login, commands, IDLE) sets its own.
#[derive(Debug)]
pub(crate) struct Limits {
    /// Milliseconds; 0 waits for ever (IDLE, which has its own deadline).
    stall: AtomicU64,
    /// Bytes per command.
    budget: AtomicU64,
}

impl Limits {
    pub(crate) fn new(stall: Duration, budget: u64) -> Arc<Self> {
        Arc::new(Limits {
            stall: AtomicU64::new(stall.as_millis() as u64),
            budget: AtomicU64::new(budget),
        })
    }

    pub(crate) fn stall(&self) -> Duration {
        Duration::from_millis(self.stall.load(Ordering::Relaxed))
    }

    pub(crate) fn set_stall(&self, stall: Duration) {
        self.stall
            .store(stall.as_millis() as u64, Ordering::Relaxed);
    }

    fn budget(&self) -> u64 {
        self.budget.load(Ordering::Relaxed)
    }

    /// Commands sent while the guard lives may bring back at most
    /// `bytes`; then the budget is `after` again.
    pub(crate) fn cap(self: &Arc<Self>, bytes: u64, after: u64) -> Cap {
        self.budget.store(bytes, Ordering::Relaxed);
        Cap {
            limits: self.clone(),
            after,
        }
    }
}

/// Puts the usual budget back when dropped.
pub(crate) struct Cap {
    limits: Arc<Limits>,
    after: u64,
}

impl Drop for Cap {
    fn drop(&mut self) {
        self.limits.budget.store(self.after, Ordering::Relaxed);
    }
}

/// The error a command over its budget ends with.
#[derive(Debug)]
pub(crate) struct Overflow;

impl std::fmt::Display for Overflow {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("the server sent more than this command may bring")
    }
}

impl std::error::Error for Overflow {}

/// Whether `e` is the wrapper's: silence or too much.
pub(crate) fn stalled(e: &io::Error) -> bool {
    e.kind() == io::ErrorKind::TimedOut
}

pub(crate) fn overflowed(e: &io::Error) -> bool {
    e.get_ref().is_some_and(|inner| inner.is::<Overflow>())
}

/// A stream with the deadlines and the budget of [`Limits`].
#[derive(Debug)]
pub(crate) struct Watched<S> {
    inner: S,
    limits: Arc<Limits>,
    reading: Option<Pin<Box<Sleep>>>,
    writing: Option<Pin<Box<Sleep>>>,
    /// Bytes the command under way may still bring back.
    left: u64,
}

impl<S> Watched<S> {
    pub(crate) fn new(inner: S, limits: Arc<Limits>) -> Self {
        let left = limits.budget();
        Watched {
            inner,
            limits,
            reading: None,
            writing: None,
            left,
        }
    }
}

/// Polls the timer for a wait, started now if none runs: ready once the
/// connection has been silent for the stall time.
fn silent_too_long(
    timer: &mut Option<Pin<Box<Sleep>>>,
    stall: Duration,
    cx: &mut Context<'_>,
) -> bool {
    if stall.is_zero() {
        *timer = None;
        return false;
    }
    let timer = timer.get_or_insert_with(|| Box::pin(tokio::time::sleep(stall)));
    timer.as_mut().poll(cx).is_ready()
}

fn timed_out() -> io::Error {
    io::Error::new(io::ErrorKind::TimedOut, "the server stopped answering")
}

impl<S: AsyncRead + Unpin> AsyncRead for Watched<S> {
    fn poll_read(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        buf: &mut ReadBuf<'_>,
    ) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        let before = buf.filled().len();
        match Pin::new(&mut this.inner).poll_read(cx, buf) {
            Poll::Ready(Ok(())) => {
                this.reading = None;
                let got = (buf.filled().len() - before) as u64;
                if got > this.left {
                    this.left = 0;
                    return Poll::Ready(Err(io::Error::other(Overflow)));
                }
                this.left -= got;
                Poll::Ready(Ok(()))
            }
            Poll::Ready(Err(e)) => {
                this.reading = None;
                Poll::Ready(Err(e))
            }
            Poll::Pending => {
                if silent_too_long(&mut this.reading, this.limits.stall(), cx) {
                    this.reading = None;
                    return Poll::Ready(Err(timed_out()));
                }
                Poll::Pending
            }
        }
    }
}

impl<S: AsyncWrite + Unpin> AsyncWrite for Watched<S> {
    fn poll_write(
        self: Pin<&mut Self>,
        cx: &mut Context<'_>,
        data: &[u8],
    ) -> Poll<io::Result<usize>> {
        let this = self.get_mut();
        match Pin::new(&mut this.inner).poll_write(cx, data) {
            Poll::Ready(result) => {
                this.writing = None;
                if matches!(result, Ok(n) if n > 0) {
                    // A new command: its answer gets the whole budget, and
                    // a wait given up before (IDLE ended by us) no longer
                    // counts.
                    this.left = this.limits.budget();
                    this.reading = None;
                }
                Poll::Ready(result)
            }
            Poll::Pending => {
                if silent_too_long(&mut this.writing, this.limits.stall(), cx) {
                    this.writing = None;
                    return Poll::Ready(Err(timed_out()));
                }
                Poll::Pending
            }
        }
    }

    fn poll_flush(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        let this = self.get_mut();
        match Pin::new(&mut this.inner).poll_flush(cx) {
            Poll::Ready(result) => {
                this.writing = None;
                Poll::Ready(result)
            }
            Poll::Pending => {
                if silent_too_long(&mut this.writing, this.limits.stall(), cx) {
                    this.writing = None;
                    return Poll::Ready(Err(timed_out()));
                }
                Poll::Pending
            }
        }
    }

    fn poll_shutdown(self: Pin<&mut Self>, cx: &mut Context<'_>) -> Poll<io::Result<()>> {
        Pin::new(&mut self.get_mut().inner).poll_shutdown(cx)
    }
}

/// Asks the system to probe an idle connection, so one whose route died
/// (a NAT that forgot it, a network that went away) fails instead of
/// looking open for hours: after a minute of silence, then every 15 s.
pub(crate) fn keep_alive(tcp: &tokio::net::TcpStream) {
    let probe = socket2::TcpKeepalive::new().with_time(Duration::from_secs(60));
    #[cfg(any(
        target_os = "android",
        target_os = "ios",
        target_os = "linux",
        target_os = "macos",
        target_os = "windows"
    ))]
    let probe = probe.with_interval(Duration::from_secs(15));
    // Best effort: a system that refuses still has the stall deadline.
    socket2::SockRef::from(tcp).set_tcp_keepalive(&probe).ok();
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::io::{AsyncReadExt, AsyncWriteExt};

    #[tokio::test(start_paused = true)]
    async fn silence_while_an_answer_is_awaited_times_out() {
        let (ours, _theirs) = tokio::io::duplex(64);
        let limits = Limits::new(Duration::from_secs(30), 1024);
        let mut watched = Watched::new(ours, limits);
        let mut buf = [0u8; 8];
        let e = watched.read(&mut buf).await.unwrap_err();
        assert!(stalled(&e), "{e}");
    }

    #[tokio::test(start_paused = true)]
    async fn an_answer_that_keeps_coming_has_no_deadline_as_a_whole() {
        let (ours, mut theirs) = tokio::io::duplex(64);
        let limits = Limits::new(Duration::from_secs(30), u64::MAX);
        let mut watched = Watched::new(ours, limits);
        let sender = tokio::spawn(async move {
            // Five minutes in all, 20 s between pieces.
            for _ in 0..15 {
                tokio::time::sleep(Duration::from_secs(20)).await;
                theirs.write_all(b"piece").await.unwrap();
            }
        });
        let mut got = 0;
        let mut buf = [0u8; 8];
        while got < 75 {
            got += watched.read(&mut buf).await.unwrap();
        }
        sender.await.unwrap();
    }

    #[tokio::test(start_paused = true)]
    async fn no_stall_waits_for_ever() {
        let (ours, mut theirs) = tokio::io::duplex(64);
        let limits = Limits::new(Duration::ZERO, 1024);
        let mut watched = Watched::new(ours, limits);
        tokio::spawn(async move {
            tokio::time::sleep(Duration::from_secs(3600)).await;
            theirs.write_all(b"x").await.unwrap();
            std::future::pending::<()>().await;
        });
        let mut buf = [0u8; 1];
        assert_eq!(watched.read(&mut buf).await.unwrap(), 1);
    }

    #[tokio::test(start_paused = true)]
    async fn more_than_the_budget_is_refused_and_a_new_command_starts_over() {
        let (ours, mut theirs) = tokio::io::duplex(64);
        let limits = Limits::new(Duration::from_secs(30), 10);
        let mut watched = Watched::new(ours, limits.clone());
        theirs.write_all(b"0123456789AB").await.unwrap();
        let mut buf = [0u8; 64];
        let e = watched.read(&mut buf).await.unwrap_err();
        assert!(overflowed(&e), "{e}");
        // A new command, with a bigger cap for it.
        let _cap = limits.cap(100, 10);
        watched.write_all(b"a2 NOOP\r\n").await.unwrap();
        theirs.write_all(b"0123456789AB").await.unwrap();
        assert_eq!(watched.read(&mut buf).await.unwrap(), 12);
    }

    #[test]
    fn a_cap_gives_the_usual_budget_back() {
        let limits = Limits::new(Duration::from_secs(1), 10);
        {
            let _cap = limits.cap(5, 10);
            assert_eq!(limits.budget(), 5);
        }
        assert_eq!(limits.budget(), 10);
    }
}
