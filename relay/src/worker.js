/**
 * Piuma Mail report relay: a Cloudflare Worker that turns in-app reports into GitHub issues.
 * Adapted from the Final(ish) report relay (same author, same license).
 *
 * The app never holds a GitHub credential: it asks this relay for a ticket when the report form
 * opens, solves a small proof of work while the user writes, then posts the report. The relay
 * keeps the attachments in an R2 bucket (deleted by a lifecycle rule after 90 days) and opens the
 * issue, which links to them through this Worker. Nothing is committed to git.
 *
 *   POST /challenge  {installId}            → {ticket, seed, bits, nbf, exp, now}
 *   POST /report     multipart: report JSON + screenshot / logs / attachment-N files
 *                                           → 201 {url, number} (also for a report already filed)
 *   GET  /files/<key>?s=<signature>         → an attachment, while it is kept
 *   GET  /health                            → {ok: true}
 *   GET  /health/deep                       → GitHub, storage and recent failures; 503 when not ok
 * A cron trigger runs the deep check every few hours and alerts the maintainer (ALERT_WEBHOOK,
 * and an issue when the GitHub token is about to expire).
 *
 * Statuses the app acts on: 403 with retry-after means "this ticket works later"; 401 means the
 * ticket can't be used (bad signature, expired, wrong proof of work): get a new one; 409 means
 * the ticket was used or the same report is on its way; 429 and 503 come with retry-after; 413
 * is too large; 400 is a report GitHub itself refuses (the app stops retrying it); 502 is GitHub
 * or storage failing, and the report was not counted.
 *
 * Abuse guards (the relay URL ships inside the app, so it is public):
 * - every ticket is signed, short-lived, bound to the install id and usable once;
 * - a proof of work per report (POW_BITS, 16 by default, at most 24): a speed bump, not a wall;
 * - a wait before each further report that doubles each time, counted both per installation and
 *   per network (IPv4 address, IPv6 /48), so a fresh install id alone does not reset it;
 * - daily caps per installation and per network (NETWORK_DAILY_LIMIT) and per autonomous system
 *   (ASN_DAILY_LIMIT), so one host or provider can't use up the day for everyone; known cloud and
 *   hosting providers (CLOUD_ASNS) get a much lower cap (CLOUD_ASN_DAILY_LIMIT) that holds for
 *   every installation; a global cap (DAILY_LIMIT) stays as a last resort;
 * - a lane for established installations (whose first ticket is ESTABLISHED_HOURS old): part of
 *   the global cap (ESTABLISHED_RESERVE) only they can use, and no per-ASN cap outside the cloud
 *   providers, so a flood of fresh installations (a few dozen cloud machines, or one person
 *   cycling addresses on a mobile network) can't stop the people who already use the app;
 * - a daily byte budget for attachments, overall (DAILY_BYTES) and per network
 *   (NETWORK_DAILY_BYTES): past it, reports still arrive, without their files;
 * - Cloudflare's rate limiter per network on /challenge and /report;
 * - at most 8 files: images up to 10 MiB each, videos up to 25 MiB, 32 MiB per report in all.
 * Used tickets, counters, the daily totals and which report opened which issue live in one
 * Durable Object (`Meter`), so checking and recording them is atomic.
 *
 * Report text is untrusted: the issue says so at the top, fences every field from the app
 * (description included) so nothing in it renders as a link, an image or HTML, and neutralises
 * @mentions.
 *
 * Bindings: Durable Object `METER` (class `Meter`), R2 bucket `ATTACHMENTS`, optional rate
 * limiter `RATE_LIMITER`; secrets `GITHUB_TOKEN` (fine-grained: Issues on REPO), `TICKET_SECRET`,
 * `FILES_SECRET` (signs attachment links, apart from tickets so links outlive a TICKET_SECRET
 * rotation; without it reports arrive without their files) and optional `ALERT_WEBHOOK`;
 * vars `REPO` ("owner/name") and optionally `PUBLIC_URL`, `DAILY_LIMIT`, `NETWORK_DAILY_LIMIT`,
 * `ASN_DAILY_LIMIT`, `CLOUD_ASNS`, `CLOUD_ASN_DAILY_LIMIT`, `ESTABLISHED_HOURS`,
 * `ESTABLISHED_RESERVE`, `DAILY_BYTES`, `NETWORK_DAILY_BYTES`, `POW_BITS`, `RETENTION_DAYS`.
 *
 * Logs (Workers Logs) carry events, statuses and counts only: never report text, IPs or ids.
 */

import { DurableObject } from 'cloudflare:workers';

const MiB = 1024 * 1024;
// What a report may carry. Memory sets the ceiling: a Worker has 128 MB, and parsing the form holds
// the body and its files at once (about twice MAX_FORM). Files then go to R2 one at a time.
const MAX_IMAGE = 10 * MiB; // also the log
const MAX_VIDEO = 25 * MiB;
const MAX_TOTAL = 32 * MiB;
const MAX_FILES = 8;
const MAX_FORM = MAX_TOTAL + MiB; // the report JSON and multipart overhead on top
/** Types kept, with each one's size limit; anything else is dropped. */
const FILE_TYPES = {
  'image/png': MAX_IMAGE,
  'image/jpeg': MAX_IMAGE,
  'image/webp': MAX_IMAGE,
  'image/gif': MAX_IMAGE,
  'video/mp4': MAX_VIDEO,
  'video/webm': MAX_VIDEO,
  'video/quicktime': MAX_VIDEO,
  'text/plain': MAX_IMAGE,
};
const TICKET_TTL = 30 * 60; // seconds
const DAY = 24 * 60 * 60;
const MAX_WAIT = 15 * 60; // seconds
/** The app solves at most 28 bits; more than 24 would take minutes on a phone. */
const MAX_POW_BITS = 24;
/** How long the relay remembers which issue a report opened (the app retries for 7 days). */
const REPORT_MEMORY = 30 * DAY;
/** A report being filed blocks the same report from another try for this long. */
const IN_PROGRESS = 10 * 60;
/** The deep health check runs at most this often on request (the cron runs it anyway). */
const HEALTH_FRESH = 10 * 60;
/** /health/deep answers from this Worker's memory for this long, without touching the Meter. */
const HEALTH_MEMORY = 60;
/** GitHub's longest issue title, in characters. */
const MAX_TITLE = 256;
/** How long an installation's first ticket is remembered when it never sends a report, and after its last one. */
const INSTALL_MEMORY = 7 * DAY;
const INSTALL_MEMORY_AFTER_REPORT = 90 * DAY;
/**
 * Cloud and hosting providers (autonomous system numbers): rented machines, not people's phones
 * and computers. Overridden by CLOUD_ASNS (comma-separated; empty for none).
 */
export const DEFAULT_CLOUD_ASNS = [
  16509, 14618, 8987, // Amazon AWS
  15169, 396982, 19527, // Google Cloud
  8075, 8068, // Microsoft Azure
  31898, // Oracle Cloud
  14061, // DigitalOcean
  24940, 213230, // Hetzner
  16276, // OVHcloud
  63949, // Akamai Linode
  20473, // Vultr (Choopa)
  12876, // Scaleway
  51167, // Contabo
  60781, 28753, // Leaseweb
  45102, // Alibaba Cloud
  132203, // Tencent Cloud
  9009, // M247
  36352, // ColoCrossing
  53667, // FranTech (BuyVM)
  202425, // IP Volume
  197540, // netcup
];
/** Days before the GitHub token expires when the maintainer is told. */
const TOKEN_WARNING_DAYS = 14;

export default {
  async fetch(request, env) {
    const path = new URL(request.url).pathname.replace(/\/+$/, '');
    try {
      if (request.method === 'POST' && path === '/challenge') return await challenge(request, env);
      if (request.method === 'POST' && path === '/report') return await report(request, env);
      if (request.method === 'GET' && path.startsWith('/files/')) return await serveFile(request, env, path);
      if (path === '/health') return json({ ok: true });
      if (path === '/health/deep') return await deepHealth(request, env);
      return json({ error: 'not found' }, 404);
    } catch (e) {
      if (e instanceof HttpError) return json({ error: e.message }, e.status, e.headers);
      log('error', 'unexpected', { name: e?.name, message: String(e?.message ?? e).slice(0, 200) });
      return json({ error: 'relay error' }, 502);
    }
  },

  /** The cron trigger: the deep check, and alerts when something needs the maintainer. */
  async scheduled(_event, env, ctx) {
    ctx.waitUntil(scheduledCheck(env));
  },
};

class HttpError extends Error {
  constructor(status, message, headers = {}) {
    super(message);
    this.status = status;
    this.headers = headers;
  }
}

/** One structured line for Workers Logs. Callers pass counts and statuses, never content. */
function log(level, event, fields = {}) {
  const line = JSON.stringify({ event, ...fields });
  if (level === 'error') console.error(line);
  else if (level === 'warn') console.warn(line);
  else console.log(line);
}

// ---- Challenge ----------------------------------------------------------------------------

async function challenge(request, env) {
  const who = await client(request, env);
  await rateLimit(env, who);
  const { installId } = await request.json().catch(() => ({}));
  if (!validInstallId(installId)) throw new HttpError(400, 'installId');
  const ih = await hmacHex(env.TICKET_SECRET, `install:${installId}`);
  const status = await meter(env).status(meterKeys(ih, who, env), limits(env));
  if (!status.ok) throw new HttpError(status.status, status.error, { 'retry-after': String(status.retryAfter) });
  const now = nowSeconds();
  // First report: a few seconds (the user is still typing). Each further one in a day doubles it,
  // up to MAX_WAIT: enough to stop a flood, short enough for someone testing all day.
  const wait = waitAfter(status.sent);
  const bits = powBits(env);
  const payload = {
    ih,
    seed: randomHex(16),
    bits,
    nbf: now + wait,
    exp: now + wait + TICKET_TTL,
  };
  const ticket = await sign(env, payload);
  // `now` lets the app read nbf and exp against the relay's clock rather than its own.
  return json({ ticket, seed: payload.seed, bits: payload.bits, nbf: payload.nbf * 1000, exp: payload.exp * 1000, now: now * 1000 });
}

export function powBits(env) {
  const bits = Math.min(Math.max(Number(env.POW_BITS ?? 16), 0), MAX_POW_BITS);
  if (!Number.isInteger(bits)) throw new HttpError(500, 'invalid POW_BITS');
  return bits;
}

// ---- Report -------------------------------------------------------------------------------

async function report(request, env) {
  const who = await client(request, env);
  await rateLimit(env, who);
  const length = Number(request.headers.get('content-length') ?? 0);
  if (length > MAX_FORM) throw new HttpError(413, 'too large');
  const form = await boundedFormData(request);
  let meta;
  try {
    meta = JSON.parse(form.get('report'));
  } catch {
    throw new HttpError(400, 'report');
  }
  const { installId, ticket, powNonce } = meta;
  if (!validInstallId(installId)) throw new HttpError(400, 'installId');

  // A ticket that can never work answers 401, not 403: apps before this relay retried every 403
  // at once with the same ticket. 403 is kept for "too early", always with retry-after.
  const payload = await verify(env, ticket);
  const ih = await hmacHex(env.TICKET_SECRET, `install:${installId}`);
  if (!payload || payload.ih !== ih) throw new HttpError(401, 'ticket');

  // The same report sent again (its 201 was lost on the way): answer with the issue it opened.
  const reportKey = validReportId(meta.reportId)
    ? await hmacHex(env.TICKET_SECRET, `report:${installId}:${meta.reportId}`)
    : null;
  const m = meter(env);
  if (reportKey) {
    const existing = await m.lookup(reportKey);
    if (existing) return json({ url: existing.url, number: existing.number, existing: true }, 201);
  }

  const now = nowSeconds();
  if (now < payload.nbf) throw new HttpError(403, 'early', { 'retry-after': String(payload.nbf - now) });
  if (now > payload.exp) throw new HttpError(401, 'expired');
  if (!(await powOk(payload.seed, powNonce, payload.bits))) throw new HttpError(401, 'pow');

  const r = sanitizeReport(meta);
  const files = collectFiles(form);
  const bytes = files.reduce((n, f) => n + f.size, 0);

  // One atomic step in the Durable Object: refuse a used ticket, a full day, a report sent before
  // the wait or one already on its way, else mark the ticket used, count the report and reserve
  // its id. If GitHub then fails, `refund` takes it all back, so an outage doesn't use up the day.
  const keys = meterKeys(payload.ih, who, env);
  const ticketId = ticket.split('.')[1];
  const claim = await m.claim({ ticketId, keys, reportKey, bytes, limits: limits(env) });
  if (!claim.ok) {
    if (claim.existing) return json({ url: claim.existing.url, number: claim.existing.number, existing: true }, 201);
    const headers = claim.retryAfter ? { 'retry-after': String(claim.retryAfter) } : {};
    throw new HttpError(claim.status, claim.error, headers);
  }

  const stored = [];
  let dropped = null;
  if (files.length && !claim.keepFiles) dropped = 'the daily storage budget was reached';
  else if (files.length && (!env.ATTACHMENTS || !env.FILES_SECRET)) dropped = 'this relay has no attachment storage';
  else if (files.length) {
    try {
      await storeFiles(env, request, files, stored);
    } catch (e) {
      log('error', 'storage_failed', { message: String(e?.message ?? e).slice(0, 200), files: files.length });
      await deleteFiles(env, stored);
      stored.length = 0;
      dropped = 'the attachment storage failed';
    }
  }

  let issue;
  try {
    issue = await github(env).createIssue({
      title: issueTitle(r),
      body: issueBody(r, stored, { dropped: dropped ? { count: files.length, why: dropped } : null, retentionDays: retentionDays(env) }),
      labels: [r.kind === 'problem' ? 'bug' : 'enhancement'],
    });
  } catch (e) {
    await deleteFiles(env, stored);
    await m.refund({ ticketId, keys, reportKey, counted: claim.counted, day: claim.day, asnCounted: claim.asnCounted });
    // GitHub refusing this one report (a 422 for its title or body) says nothing about the relay:
    // the app is told it was rejected and stops, and /health/deep stays as it was.
    if (e instanceof GitHubRejected) throw new HttpError(400, 'report rejected');
    await m.noteUpstream(false);
    throw e instanceof HttpError ? e : new HttpError(502, 'upstream');
  }
  try {
    if (reportKey) await m.remember(reportKey, issue.number, issue.html_url);
    await m.noteUpstream(true);
  } catch (e) {
    log('error', 'remember_failed', { message: String(e?.message ?? e).slice(0, 200) });
  }
  log('info', 'report_filed', { kind: r.kind, files: stored.length, dropped: dropped ? files.length : 0, bytes: claim.counted });
  return json({ url: issue.html_url, number: issue.number }, 201);
}

async function boundedFormData(request) {
  if (!request.body) throw new HttpError(400, 'form');
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      // Content-Length can be missing or inaccurate. Enforce the limit
      // on every byte before buffering or parsing the multipart form.
      if (size > MAX_FORM) {
        await reader.cancel();
        throw new HttpError(413, 'too large');
      }
      chunks.push(value);
    }
  } finally {
    reader.releaseLock();
  }
  // Handed over chunk by chunk, so the body isn't held twice while the form is parsed.
  const body = new ReadableStream({
    pull(controller) {
      const next = chunks.shift();
      if (next) controller.enqueue(next);
      else controller.close();
    },
  });
  try {
    return await new Response(body, { headers: request.headers }).formData();
  } catch {
    throw new HttpError(400, 'form');
  }
}

export function sanitizeReport(meta) {
  // The app's two kinds: Problem and Idea.
  const kind = meta.kind === 'idea' ? 'idea' : 'problem';
  const text = (v, max) => String(v ?? '').replace(/\r/g, '').slice(0, max);
  const title = text(meta.title, 200).replace(/\s+/g, ' ').trim();
  if (!title) throw new HttpError(400, 'title');
  const device = {};
  for (const [k, v] of Object.entries(meta.device ?? {}).slice(0, 20)) device[text(k, 40)] = text(v, 200);
  return {
    kind,
    title,
    description: text(meta.description, 20000).trim(),
    device,
    screens: (Array.isArray(meta.screens) ? meta.screens : []).slice(-12).map((s) => text(s, 120)),
    logExcerpt: text(meta.logExcerpt, 6000),
  };
}

export function collectFiles(form) {
  const out = [];
  const names = new Set();
  let total = 0;
  for (const [field, value] of form.entries()) {
    if (field === 'report' || typeof value === 'string') continue;
    const type = (value.type || 'application/octet-stream').toLowerCase();
    const max = Object.hasOwn(FILE_TYPES, type) ? FILE_TYPES[type] : 0;
    if (!max) continue;
    if (out.length >= MAX_FILES) throw new HttpError(413, 'too many files');
    if (value.size > max) throw new HttpError(413, 'file too large');
    total += value.size;
    if (total > MAX_TOTAL) throw new HttpError(413, 'too large');
    // One key per file within a report.
    let name = safeName(value.name || field);
    const original = name;
    let suffix = out.length + 1;
    while (names.has(name)) name = `${suffix++}-${original}`;
    names.add(name);
    out.push({ field, name, type, size: value.size, file: value });
  }
  return out;
}

// ---- Attachments --------------------------------------------------------------------------
// In R2, under "<day>/<random>/<name>", deleted by the bucket's lifecycle rule. The issue links
// to them through this Worker with a signature, so only someone who can read the issue (or was
// given a link) can open one, and nothing else in the bucket can be listed or guessed.

/** Puts `files` in R2, adding each one to `stored` as soon as it is there (to delete on failure). */
async function storeFiles(env, request, files, stored) {
  const folder = `${new Date().toISOString().slice(0, 10)}/${randomHex(12)}`;
  const base = (env.PUBLIC_URL || new URL(request.url).origin).replace(/\/+$/, '');
  for (const f of files) {
    const key = `${folder}/${f.name}`;
    // A File is a Blob: R2 takes it as it is, with its length, without another copy.
    await env.ATTACHMENTS.put(key, f.file, { httpMetadata: { contentType: f.type } });
    const sig = await fileSignature(env, key);
    stored.push({ ...f, key, url: `${base}/files/${encodePath(key)}?s=${sig}` });
  }
}

async function deleteFiles(env, stored) {
  if (!stored.length || !env.ATTACHMENTS) return;
  try {
    await env.ATTACHMENTS.delete(stored.map((f) => f.key));
  } catch (e) {
    log('warn', 'storage_cleanup_failed', { files: stored.length });
  }
}

/** Attachment links are signed with FILES_SECRET alone, so rotating TICKET_SECRET keeps them working. */
export async function fileSignature(env, key) {
  if (!env.FILES_SECRET) throw new HttpError(404, 'not found');
  return (await hmacHex(env.FILES_SECRET, `file:${key}`)).slice(0, 32);
}

async function serveFile(request, env, path) {
  const key = path.slice('/files/'.length).split('/').map(decodeURIComponent).join('/');
  const sig = new URL(request.url).searchParams.get('s') ?? '';
  if (!/^\d{4}-\d{2}-\d{2}\/[0-9a-f]{24}\/[A-Za-z0-9._-]{1,80}$/.test(key) || !timingSafeEqual(sig, await fileSignature(env, key))) {
    throw new HttpError(404, 'not found');
  }
  const object = env.ATTACHMENTS ? await env.ATTACHMENTS.get(key) : null;
  if (!object) throw new HttpError(404, `gone: attachments are kept ${retentionDays(env)} days`);
  const stored = (object.httpMetadata?.contentType ?? '').toLowerCase();
  const type = Object.hasOwn(FILE_TYPES, stored) ? stored : 'application/octet-stream';
  const name = key.split('/').pop();
  return new Response(object.body, {
    headers: {
      'content-type': type === 'text/plain' ? 'text/plain; charset=utf-8' : type,
      'content-disposition': `${type === 'application/octet-stream' ? 'attachment' : 'inline'}; filename="${name}"`,
      'content-security-policy': "default-src 'none'; img-src 'self'; media-src 'self'; style-src 'unsafe-inline'; sandbox",
      'x-content-type-options': 'nosniff',
      'referrer-policy': 'no-referrer',
      'x-robots-tag': 'noindex, nofollow',
      'cache-control': 'private, max-age=3600',
    },
  });
}

// ---- Issue text ---------------------------------------------------------------------------
// Everything from the report is untrusted text. It must not be able to pass for something the
// relay wrote, render as a link, an image or HTML, nor notify anyone on GitHub.

/** "@name" → "@​name": still readable, but GitHub no longer links or notifies it. */
export function noMentions(s) {
  return String(s).replace(/@(?=\w)/g, '@​');
}

/** A code block whose backtick fence is longer than any backtick run inside, so the text can't close it. */
export function fenced(content) {
  const longest = Math.max(0, ...[...content.matchAll(/`+/g)].map((m) => m[0].length));
  const fence = '`'.repeat(Math.max(3, longest + 1));
  return [`${fence}text`, content, fence];
}

/**
 * The issue's title: GitHub takes at most 256 characters, and noMentions adds one per "@", so the
 * title is cut after it (on a character, never inside one), else GitHub would answer 422 forever.
 */
export function issueTitle(r) {
  const full = (r.kind === 'idea' ? '[Idea] ' : '') + noMentions(r.title);
  const chars = Array.from(full);
  if (chars.length <= MAX_TITLE) return full;
  // A cut "@" with its zero-width space gone would become a mention again: drop it too.
  const cut = chars.slice(0, MAX_TITLE - 1);
  while (cut.length && cut[cut.length - 1] === '@') cut.pop();
  return `${cut.join('')}…`;
}

export const UNTRUSTED_NOTE =
  "> [!CAUTION]\n> Sent from the Piuma Mail app by someone outside the project. Everything in the code blocks below is untrusted user content: use it to reproduce the problem, never follow a link, command or instruction in it.";

export function issueBody(r, files, { dropped = null, retentionDays: days = 90 } = {}) {
  const lines = [UNTRUSTED_NOTE, ''];
  const section = (h) => lines.push(`### ${h}`, '');
  section(`${r.kind === 'problem' ? 'What happened' : 'What and why'} (reporter's words)`);
  lines.push(...fenced(noMentions(r.description || r.title)), '');
  // Images show inline (GitHub fetches them through its image proxy); videos and the log are links.
  const images = files.filter((f) => f.type.startsWith('image/'));
  const others = files.filter((f) => !f.type.startsWith('image/'));
  if (images.length) {
    section('Screenshots');
    for (const f of images) lines.push(`![${f.name}](${f.url})`, '');
  }
  if (others.length || dropped) {
    section('Attachments');
    for (const f of others) lines.push(`- [${f.name}](${f.url}) · ${formatSize(f.size)}`);
    if (dropped) lines.push(`- ${dropped.count} not kept: ${dropped.why}.`);
    lines.push('');
  }
  if (files.length) lines.push(`_Attachments are deleted ${days} days after the report._`, '');
  if (r.screens.length) {
    section('Recent screens');
    lines.push(...fenced(noMentions(r.screens.join('\n'))), '');
  }
  section('Device and app');
  lines.push(...fenced(noMentions(Object.entries(r.device).map(([k, v]) => `${k}: ${v}`).join('\n'))), '');
  if (r.logExcerpt.trim()) {
    section('Log excerpt');
    // The app sends warnings and errors, or plain activity when there were none.
    const problems = /(^| )[WE] |^Crash/m.test(r.logExcerpt);
    const summary = problems ? 'Recent warnings and errors' : 'Recent activity (no warnings or errors)';
    lines.push(`<details><summary>${summary}</summary>`, '', ...fenced(noMentions(r.logExcerpt.trim())), '', '</details>', '');
  }
  lines.push('_Sent from the in-app reporter._');
  return lines.join('\n');
}

// ---- GitHub -------------------------------------------------------------------------------

/** GitHub refused this request for what it holds (400, 422, 413...), not for the relay's access. */
class GitHubRejected extends HttpError {
  constructor(status) {
    super(502, `github ${status}`);
    this.githubStatus = status;
  }
}

/**
 * A 4xx that is about the report itself. 401 and 403 (token, permissions, abuse limits), 404 (the
 * repository or the token's access to it is gone) and 429 (rate limited) are the relay's problem:
 * those stay upstream failures, the report is kept and tried again.
 */
export const rejectsTheReport = (status) => status >= 400 && status < 500 && ![401, 403, 404, 429].includes(status);

function github(env) {
  const base = `https://api.github.com/repos/${env.REPO}`;
  const call = async (method, path, body) => {
    const res = await fetch(base + path, {
      method,
      headers: {
        authorization: `Bearer ${env.GITHUB_TOKEN}`,
        accept: 'application/vnd.github+json',
        'x-github-api-version': '2022-11-28',
        'user-agent': 'piuma-report-relay',
        ...(body ? { 'content-type': 'application/json' } : {}),
      },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (!res.ok) {
      // GitHub's own message ("Bad credentials", "Not Found"), never the request.
      const message = await res.json().then((j) => String(j?.message ?? '').slice(0, 120)).catch(() => '');
      log('error', 'github_failed', { method, path: path.split('?')[0], status: res.status, message });
      if (rejectsTheReport(res.status)) throw new GitHubRejected(res.status);
      throw new HttpError(502, `github ${res.status}`);
    }
    return res;
  };
  return {
    createIssue: async (issue) => (await call('POST', '/issues', issue)).json(),
    /** Whether the token can read the repository's issues, and when it expires (a Date or null). */
    async check() {
      const res = await call('GET', '/issues?per_page=1&state=all');
      const header = res.headers.get('github-authentication-token-expiration');
      const expires = header ? new Date(header.replace(' UTC', 'Z').replace(' ', 'T')) : null;
      return { expires: expires && !Number.isNaN(expires.getTime()) ? expires : null };
    },
  };
}

// ---- Health -------------------------------------------------------------------------------

/** Checks GitHub and storage now, and what the last reports met. */
export async function deepCheck(env) {
  const now = nowSeconds();
  const out = { github: false, storage: null, tokenExpiresInDays: null, lastReportFailed: false, checkedAt: now * 1000 };
  try {
    const { expires } = await github(env).check();
    out.github = true;
    if (expires) out.tokenExpiresInDays = Math.floor((expires.getTime() / 1000 - now) / DAY);
  } catch {
    out.github = false;
  }
  if (env.ATTACHMENTS) {
    try {
      await env.ATTACHMENTS.head('health-probe');
      // Without its signing key no attachment can be linked: storage doesn't work either.
      out.storage = Boolean(env.FILES_SECRET);
    } catch {
      out.storage = false;
    }
  }
  const upstream = await meter(env).upstream();
  out.lastReportFailed = upstream.lastFailure > upstream.lastSuccess;
  out.ok = out.github && out.storage !== false && !out.lastReportFailed && (out.tokenExpiresInDays === null || out.tokenExpiresInDays > 7);
  return out;
}

/** What /health/deep shows: no token dates or counts, only what works. */
function publicHealth(h) {
  return {
    ok: h.ok,
    github: h.github,
    storage: h.storage,
    tokenExpiresSoon: h.tokenExpiresInDays !== null && h.tokenExpiresInDays <= TOKEN_WARNING_DAYS,
    lastReportFailed: h.lastReportFailed,
    checkedAt: h.checkedAt,
  };
}

/** The deployed version (wrangler.toml `[version_metadata]`), or null without the binding. */
const versionId = (env) => env.VERSION?.id ?? null;

/** This isolate's last answer to /health/deep: anyone can ask, so most answers come from here. */
let healthMemory = null;

/** Forgets the remembered /health/deep answer, for tests. */
export function forgetHealth() {
  healthMemory = null;
}

async function deepHealth(request, env) {
  const now = nowSeconds();
  if (healthMemory && now >= healthMemory.at && now - healthMemory.at < HEALTH_MEMORY) {
    return json(healthMemory.body, healthMemory.body.ok ? 200 : 503);
  }
  // Past the memory, each network may ask as often as it may ask for tickets.
  await rateLimit(env, await client(request, env));
  const m = meter(env);
  let h = await m.getState('health');
  // A new deployment (a new version, also after `wrangler secret put`) checks again at once, so
  // the deploy's own check sees the token and storage it was just given.
  if (!h || h.version !== versionId(env) || now * 1000 - h.checkedAt > HEALTH_FRESH * 1000) {
    h = { ...(await deepCheck(env)), version: versionId(env) };
    await m.setState('health', h);
  }
  const body = publicHealth(h);
  healthMemory = { at: now, body };
  return json(body, body.ok ? 200 : 503);
}

/** The cron trigger: check, log, and tell the maintainer what needs them. */
export async function scheduledCheck(env) {
  const m = meter(env);
  const h = { ...(await deepCheck(env)), version: versionId(env) };
  await m.setState('health', h);
  log(h.ok ? 'info' : 'error', 'health', publicHealth(h));
  const problems = [];
  if (!h.github) problems.push('GitHub refuses the relay (token expired or revoked, or GitHub is down)');
  if (h.storage === false) {
    problems.push(env.FILES_SECRET ? 'the attachment storage (R2) fails' : 'FILES_SECRET is not set: reports arrive without attachments');
  }
  if (h.lastReportFailed) problems.push('the last report could not be filed');
  if (h.tokenExpiresInDays !== null && h.tokenExpiresInDays <= TOKEN_WARNING_DAYS) {
    problems.push(`the GitHub token expires in ${h.tokenExpiresInDays} days`);
  }
  if (problems.length) await alert(env, `Piuma report relay: ${problems.join('; ')}.`);
  // The token reminder also goes to the feedback repository, once per expiry date.
  if (h.github && h.tokenExpiresInDays !== null && h.tokenExpiresInDays <= TOKEN_WARNING_DAYS) {
    const day = utcDay(nowSeconds() + h.tokenExpiresInDays * DAY);
    if (!(await m.getState(`token-reminder:${day}`))) {
      try {
        await github(env).createIssue({
          title: `Report relay: the GitHub token expires around ${day}`,
          body: 'The report relay\'s GitHub token expires soon. Make a new fine-grained token (Issues: read and write, on this repository only) and deploy the relay again: see relay/README.md, "When the GitHub token expires". Until then reports wait in the apps\' queues.\n\n_Opened by the relay\'s scheduled check._',
        });
        await m.setState(`token-reminder:${day}`, true);
      } catch {
        // Logged by the GitHub call; the webhook (if any) already said it.
      }
    }
  }
  return h;
}

async function alert(env, text) {
  if (!env.ALERT_WEBHOOK) return;
  try {
    // Slack- and Discord-style incoming webhooks read `text` and `content`.
    await fetch(env.ALERT_WEBHOOK, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ text, content: text }),
    });
  } catch {
    log('warn', 'alert_failed');
  }
}

// ---- Client identity and rate limiting ----------------------------------------------------

/**
 * The caller's network, keyed by an HMAC of its IP (IPv6 by /48, the block a site or a server
 * provider customer usually gets), and its autonomous system number when Cloudflare knows it.
 */
async function client(request, env) {
  const prefix = ipPrefix(request.headers.get('cf-connecting-ip'));
  const asn = Number(request.cf?.asn);
  return {
    ipKey: prefix ? await hmacHex(env.TICKET_SECRET, `ip:${prefix}`) : null,
    asn: Number.isInteger(asn) && asn > 0 ? asn : null,
  };
}

export function ipPrefix(ip) {
  if (!ip) return null;
  ip = ip.trim().toLowerCase();
  if (!ip.includes(':')) return ip;
  const [head, tail] = ip.split('::');
  const h = head ? head.split(':') : [];
  const t = tail ? tail.split(':') : [];
  const groups = tail === undefined ? h : [...h, ...Array(Math.max(0, 8 - h.length - t.length)).fill('0'), ...t];
  return `${groups.slice(0, 3).map((g) => (parseInt(g, 16) || 0).toString(16)).join(':')}::/48`;
}

/** Cloudflare's rate limiter, when the binding is there (wrangler.toml `[[ratelimits]]`). */
async function rateLimit(env, who) {
  if (!env.RATE_LIMITER) return;
  const { success } = await env.RATE_LIMITER.limit({ key: who.ipKey ?? 'unknown' });
  if (!success) throw new HttpError(429, 'slow down', { 'retry-after': '60' });
}

// ---- Metering -----------------------------------------------------------------------------

const meter = (env) => env.METER.get(env.METER.idFromName('global'));
/**
 * Counter keys: the installation and the network get the spacing and the per-network cap; the ASN
 * only its own cap, a lower one for cloud providers. `install` names the installation for the
 * established lane.
 */
export const meterKeys = (ih, who, env = {}) => ({
  install: ih,
  spaced: [`install:${ih}`, ...(who.ipKey ? [`ip:${who.ipKey}`] : [])],
  asn: who.asn ? `asn:${who.asn}` : null,
  cloud: who.asn ? cloudAsns(env).has(who.asn) : false,
});

/** CLOUD_ASNS as a set: the default list when unset, none when set empty. */
export function cloudAsns(env) {
  if (env.CLOUD_ASNS === undefined || env.CLOUD_ASNS === null) return new Set(DEFAULT_CLOUD_ASNS);
  return new Set(String(env.CLOUD_ASNS).split(/[\s,]+/).map(Number).filter((n) => Number.isInteger(n) && n > 0));
}
const num = (v, fallback) => {
  const n = Number(v ?? fallback);
  return Number.isFinite(n) && n >= 0 ? n : fallback;
};
export const limits = (env) => {
  const daily = num(env.DAILY_LIMIT, 200);
  return {
    daily,
    network: num(env.NETWORK_DAILY_LIMIT, 6),
    asn: num(env.ASN_DAILY_LIMIT, 40),
    cloudAsn: num(env.CLOUD_ASN_DAILY_LIMIT, 5),
    establishedAfter: num(env.ESTABLISHED_HOURS, 24) * 60 * 60,
    // A quarter of the day unless set; never more than all of it.
    reserve: Math.min(daily, num(env.ESTABLISHED_RESERVE, Math.floor(daily / 4))),
    dailyBytes: num(env.DAILY_BYTES, 500 * MiB),
    networkBytes: num(env.NETWORK_DAILY_BYTES, 100 * MiB),
  };
};
const retentionDays = (env) => num(env.RETENTION_DAYS, 90);
/** The wait before a report, after `sent` reports in the current day. */
const waitAfter = (sent) => Math.min(5 * 2 ** sent, MAX_WAIT);
const utcDay = (seconds) => new Date(seconds * 1000).toISOString().slice(0, 10);
const untilTomorrow = (now) => DAY - (now % DAY);
const SIX_HOURS = 6 * 60 * 60;

/**
 * One global instance (idFromName('global')) holding used tickets, per-key report counters, the
 * daily totals, which report opened which issue, and the health state, in its SQLite storage.
 * Each method runs synchronous SQL with no await, so a check and the write that follows can't
 * interleave with another request: that's what makes the single-use ticket, the caps and the
 * one-issue-per-report rule hold under parallel requests (Workers KV could not).
 */
export class Meter extends DurableObject {
  constructor(ctx, env) {
    super(ctx, env);
    this.sql = ctx.storage.sql;
    // `counts` and `days` from the first relay are left alone (they only ever held a day).
    this.sql.exec(`
      CREATE TABLE IF NOT EXISTS used (id TEXT PRIMARY KEY, exp INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS meter_counts (key TEXT PRIMARY KEY, count INTEGER NOT NULL, bytes INTEGER NOT NULL, since INTEGER NOT NULL, last INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS meter_days (day TEXT PRIMARY KEY, total INTEGER NOT NULL, bytes INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS reports (key TEXT PRIMARY KEY, number INTEGER, url TEXT, exp INTEGER NOT NULL);
      CREATE TABLE IF NOT EXISTS state (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS installs (ih TEXT PRIMARY KEY, first INTEGER NOT NULL, exp INTEGER NOT NULL);
    `);
  }

  /**
   * Before a ticket: whether this caller may report today, and how many it sent. A ticket given
   * is the installation's first one, if none was given before: it starts its way to established.
   */
  status(keys, limits) {
    const now = nowSeconds();
    const refusal = this.#refusal(keys, limits, now);
    if (refusal) return refusal;
    let sent = 0;
    for (const row of this.#rows(keys.spaced, now)) sent = Math.max(sent, row.count);
    if (keys.install) {
      this.sql.exec('INSERT OR IGNORE INTO installs (ih, first, exp) VALUES (?, ?, ?)', keys.install, now, now + INSTALL_MEMORY);
    }
    return { ok: true, sent };
  }

  /** The issue a report already opened, if any. */
  lookup(reportKey) {
    const row = this.sql.exec('SELECT number, url FROM reports WHERE key = ? AND number IS NOT NULL AND exp >= ?', reportKey, nowSeconds()).toArray()[0];
    return row ? { number: row.number, url: row.url } : null;
  }

  /**
   * Uses the ticket and counts the report, or says why not: 409 ticket used or the same report on
   * its way, 503 the global cap, 429 a per-installation, network or ASN cap, 403 a report from the
   * same installation or network came sooner than its wait allows. Its attachments count against
   * the byte budgets only when they fit (`keepFiles`); otherwise the report goes without them.
   */
  claim({ ticketId, keys, reportKey, bytes, limits }) {
    const now = nowSeconds();
    this.#expire(now);
    if (this.sql.exec('SELECT 1 FROM used WHERE id = ?', ticketId).toArray().length) {
      return { ok: false, status: 409, error: 'duplicate' };
    }
    if (reportKey) {
      const row = this.sql.exec('SELECT number, url FROM reports WHERE key = ? AND exp >= ?', reportKey, now).toArray()[0];
      if (row?.number != null) return { ok: false, existing: { number: row.number, url: row.url } };
      if (row) return { ok: false, status: 409, error: 'in progress' };
    }
    const refusal = this.#refusal(keys, limits, now);
    if (refusal) return refusal;
    let ready = now;
    for (const row of this.#rows(keys.spaced, now)) ready = Math.max(ready, row.last + waitAfter(row.count));
    if (ready > now) return { ok: false, status: 403, error: 'early', retryAfter: ready - now };

    const day = this.#day(now);
    const today = utcDay(now);
    const fits = bytes > 0
      && day.bytes + bytes <= limits.dailyBytes
      && this.#rows(keys.spaced, now).every((row) => row.bytes + bytes <= limits.networkBytes)
      && bytes <= limits.networkBytes;
    const counted = fits ? bytes : 0;

    this.sql.exec('INSERT INTO used (id, exp) VALUES (?, ?)', ticketId, now + 2 * DAY);
    // Established installations outside the cloud providers don't use up their provider's day.
    const asnCounted = Boolean(keys.asn) && (keys.cloud || !this.#established(keys, limits, now));
    for (const key of [...keys.spaced, ...(asnCounted ? [keys.asn] : [])]) {
      // A fixed day from the first report: later reports don't push the reset further away.
      this.sql.exec(
        `INSERT INTO meter_counts (key, count, bytes, since, last) VALUES (?1, 1, ?4, ?2, ?2)
         ON CONFLICT (key) DO UPDATE SET
           count = CASE WHEN ?2 - since < ?3 THEN count + 1 ELSE 1 END,
           bytes = CASE WHEN ?2 - since < ?3 THEN bytes + ?4 ELSE ?4 END,
           since = CASE WHEN ?2 - since < ?3 THEN since ELSE ?2 END,
           last = ?2`,
        key, now, DAY, counted,
      );
    }
    this.sql.exec(
      'INSERT INTO meter_days (day, total, bytes) VALUES (?, 1, ?) ON CONFLICT (day) DO UPDATE SET total = total + 1, bytes = bytes + excluded.bytes',
      today, counted,
    );
    if (reportKey) {
      this.sql.exec('INSERT OR REPLACE INTO reports (key, number, url, exp) VALUES (?, NULL, NULL, ?)', reportKey, now + IN_PROGRESS);
    }
    if (keys.install) {
      // Remembered for longer once it has reported: it stays established.
      this.sql.exec(
        'INSERT INTO installs (ih, first, exp) VALUES (?1, ?2, ?3) ON CONFLICT (ih) DO UPDATE SET exp = MAX(exp, ?3)',
        keys.install, now, now + INSTALL_MEMORY_AFTER_REPORT,
      );
    }
    return { ok: true, keepFiles: fits, counted, day: today, asnCounted };
  }

  /**
   * Takes back a claim whose issue could not be opened: the ticket, the counts, the bytes, on the
   * day the claim counted them (`day`, which may be yesterday by now).
   */
  refund({ ticketId, keys, reportKey, counted, day = utcDay(nowSeconds()), asnCounted = Boolean(keys.asn) }) {
    this.sql.exec('DELETE FROM used WHERE id = ?', ticketId);
    for (const key of [...keys.spaced, ...(asnCounted && keys.asn ? [keys.asn] : [])]) {
      // Back to no wait when this was the only report; otherwise the wait for the count before.
      this.sql.exec(
        'UPDATE meter_counts SET last = CASE WHEN count <= 1 THEN 0 ELSE last END, count = MAX(count - 1, 0), bytes = MAX(bytes - ?, 0) WHERE key = ?',
        counted, key,
      );
    }
    this.sql.exec('UPDATE meter_days SET total = MAX(total - 1, 0), bytes = MAX(bytes - ?, 0) WHERE day = ?', counted, day);
    if (reportKey) this.sql.exec('DELETE FROM reports WHERE key = ? AND number IS NULL', reportKey);
  }

  /** The issue a report opened, for the same report sent again. */
  remember(reportKey, number, url) {
    this.sql.exec('INSERT OR REPLACE INTO reports (key, number, url, exp) VALUES (?, ?, ?, ?)', reportKey, number, url, nowSeconds() + REPORT_MEMORY);
  }

  /** Whether the last call to GitHub for a report worked. */
  noteUpstream(ok) {
    this.#set(ok ? 'last-success' : 'last-failure', nowSeconds());
  }

  upstream() {
    return { lastSuccess: this.#get('last-success') ?? 0, lastFailure: this.#get('last-failure') ?? 0 };
  }

  getState(key) {
    return this.#get(key);
  }

  setState(key, value) {
    this.#set(key, value);
  }

  #get(key) {
    const row = this.sql.exec('SELECT value FROM state WHERE key = ?', key).toArray()[0];
    return row ? JSON.parse(row.value) : null;
  }

  #set(key, value) {
    this.sql.exec('INSERT OR REPLACE INTO state (key, value) VALUES (?, ?)', key, JSON.stringify(value));
  }

  /** Whether the installation's first ticket is old enough for the established lane. */
  #established(keys, limits, now) {
    if (!keys.install) return false;
    const row = this.sql.exec('SELECT first FROM installs WHERE ih = ? AND exp >= ?', keys.install, now).toArray()[0];
    return Boolean(row) && now - row.first >= limits.establishedAfter;
  }

  /**
   * A cap that refuses this caller now, with how long until it lifts. New installations share the
   * global cap less the established reserve; established ones may use all of it, and skip the
   * per-ASN cap except on cloud providers.
   */
  #refusal(keys, limits, now) {
    const established = this.#established(keys, limits, now);
    const daily = established ? limits.daily : Math.max(0, limits.daily - (limits.reserve ?? 0));
    if (this.#day(now).total >= daily) {
      return { ok: false, status: 503, error: 'daily limit', retryAfter: Math.min(untilTomorrow(now), SIX_HOURS) };
    }
    const capped = (rows, cap) => rows.filter((row) => row.count >= cap);
    const asnCap = keys.cloud ? Math.min(limits.cloudAsn ?? limits.asn, limits.asn) : limits.asn;
    const over = [
      ...capped(this.#rows(keys.spaced, now), limits.network),
      ...(keys.asn && (keys.cloud || !established) ? capped(this.#rows([keys.asn], now), asnCap) : []),
    ];
    if (over.length) {
      const lifts = Math.max(...over.map((row) => row.since + DAY - now));
      return { ok: false, status: 429, error: 'network daily limit', retryAfter: Math.max(1, Math.min(lifts, SIX_HOURS)) };
    }
    return null;
  }

  #rows(keys, now) {
    return keys.flatMap((k) => this.sql.exec('SELECT count, bytes, since, last FROM meter_counts WHERE key = ? AND ? - since < ?', k, now, DAY).toArray());
  }

  #day(now) {
    return this.sql.exec('SELECT total, bytes FROM meter_days WHERE day = ?', utcDay(now)).toArray()[0] ?? { total: 0, bytes: 0 };
  }

  /** Drops expired rows; the tables stay small. */
  #expire(now) {
    this.sql.exec('DELETE FROM used WHERE exp < ?', now);
    this.sql.exec('DELETE FROM meter_counts WHERE ? - since >= ?', now, DAY);
    this.sql.exec('DELETE FROM meter_days WHERE day < ?', utcDay(now - DAY));
    this.sql.exec('DELETE FROM reports WHERE exp < ?', now);
    this.sql.exec('DELETE FROM installs WHERE exp < ?', now);
  }
}

// ---- Crypto -------------------------------------------------------------------------------

const enc = new TextEncoder();

async function hmac(secret, data) {
  if (!secret) throw new Error('TICKET_SECRET missing');
  const key = await crypto.subtle.importKey('raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return new Uint8Array(await crypto.subtle.sign('HMAC', key, enc.encode(data)));
}

async function hmacHex(secret, data) {
  return hex(await hmac(secret, data));
}

export async function sign(env, payload) {
  const body = b64url(enc.encode(JSON.stringify(payload)));
  return `${body}.${b64url(await hmac(env.TICKET_SECRET, body))}`;
}

export async function verify(env, ticket) {
  if (typeof ticket !== 'string' || !ticket.includes('.')) return null;
  const [body, sig] = ticket.split('.');
  const expected = b64url(await hmac(env.TICKET_SECRET, body));
  if (!timingSafeEqual(sig, expected)) return null;
  try {
    return JSON.parse(new TextDecoder().decode(fromB64url(body)));
  } catch {
    return null;
  }
}

/** sha256("seed:nonce") must start with `bits` zero bits — the same rule the app solves. */
export async function powOk(seed, nonce, bits) {
  if (typeof nonce !== 'string' || nonce.length > 20) return false;
  const digest = new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(`${seed}:${nonce}`)));
  return leadingZeroBits(digest) >= bits;
}

export function leadingZeroBits(bytes) {
  let n = 0;
  for (const b of bytes) {
    if (b === 0) { n += 8; continue; }
    n += Math.clz32(b) - 24;
    break;
  }
  return n;
}

// ---- Helpers ------------------------------------------------------------------------------

const nowSeconds = () => Math.floor(Date.now() / 1000);
const validInstallId = (v) => typeof v === 'string' && /^[0-9a-f-]{16,64}$/i.test(v);
const validReportId = (v) => typeof v === 'string' && /^[A-Za-z0-9-]{1,64}$/.test(v);
const hex = (bytes) => [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
const randomHex = (n) => hex(crypto.getRandomValues(new Uint8Array(n)));
const safeName = (n) => n.replace(/[^A-Za-z0-9._-]/g, '_').slice(-80) || 'file';
const encodePath = (p) => p.split('/').map(encodeURIComponent).join('/');
const formatSize = (b) => (b >= 1048576 ? `${(b / 1048576).toFixed(1)} MB` : `${Math.ceil(b / 1024)} KB`);

function b64url(bytes) {
  return base64(bytes).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function fromB64url(s) {
  const bin = atob(s.replace(/-/g, '+').replace(/_/g, '/'));
  return Uint8Array.from(bin, (c) => c.charCodeAt(0));
}

function base64(input) {
  const bytes = input instanceof Uint8Array ? input : new Uint8Array(input);
  let out = '';
  for (let i = 0; i < bytes.length; i += 0x8000) out += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
  return btoa(out);
}

function timingSafeEqual(a, b) {
  if (typeof a !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

function json(data, status = 200, headers = {}) {
  return new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json', ...headers } });
}
