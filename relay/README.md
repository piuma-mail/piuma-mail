# Report relay

The app's problem reports and ideas become GitHub issues on the private
`piuma-mail/piuma-mail-feedback` repository through this Cloudflare Worker, so no GitHub credential
ships in the app and users need no GitHub account. It is the Final(ish) report relay with Piuma's
two kinds (Problem, Idea) and only images, short videos and text accepted as files. What reports
carry, where they go and how long they stay is in [PRIVACY.md](../PRIVACY.md).

Nothing is ever sent on its own: the user writes the report, chooses what goes with it (the
screenshot is off by default because it shows mail) and sees exactly what is sent first.

1. When the report sheet opens, the app asks `POST /challenge` for a signed ticket and solves its
   proof of work (about a second) while the user writes. The answer carries the relay's clock, so
   the app reads the ticket's times right even when its own clock is off.
2. On Send, the app posts `POST /report` (multipart: the report JSON plus the screenshot, the log
   and the images and videos the user attached). If it can't, it tries again in the background
   while the app is open and at each start: after 1 min, 5 min, 30 min, 2 h, then every 6 h, for
   7 days. Then the report shows as failed in Your reports, where it can be sent again or by
   email.
3. The relay keeps the files in an R2 bucket (deleted after 90 days by the bucket's lifecycle rule)
   and opens the issue: a note that its content is untrusted, the description and every other
   field from the app in fenced blocks, the screenshot and images inline and links to the videos
   and the log, all served by the relay at `/files/…` with a signature; the device, the recent
   screens and a log excerpt. Labelled `bug` (Problem) or `enhancement` (Idea, titled
   "[Idea] …").

Nothing is committed to git: reports before this version stored their files on the feedback
repository's `feedback-assets` branch, which can be deleted once those issues are closed.

## Endpoints and answers

| Request | Answer |
| --- | --- |
| `POST /challenge {installId}` | `{ticket, seed, bits, nbf, exp, now}`, or 429/503 with `retry-after` when a cap is reached |
| `POST /report` | `201 {url, number}`, also for a report already filed (`existing: true`) |
| `GET /files/<key>?s=<signature>` | the file while it is kept, else 404 |
| `GET /health` | `{"ok": true}`, nothing else |
| `GET /health/deep` | `{ok, github, storage, tokenExpiresSoon, lastReportFailed, checkedAt}`, 503 when not ok; checked at most every 10 minutes |

What the app does with each `/report` answer:

| Status | Meaning | The app |
| --- | --- | --- |
| 201 | filed (or already filed) | marks it sent with the issue number |
| 403 + `retry-after` | the ticket's wait isn't over | keeps the ticket, tries then |
| 401 (or 403 without `retry-after`) | the ticket can't work: bad signature (a rotated `TICKET_SECRET`), another installation's, expired, wrong proof of work | drops the ticket and counts a try (backoff) |
| 409 | the ticket was used, or the same report is on its way | a new ticket after a backoff; the relay then answers with the issue already opened |
| 413 | too large | sends it again without the attachments, saying so |
| 429, 503 + `retry-after` | a cap or the rate limit | tries after `retry-after` |
| 502 | GitHub failed; the report was not counted and its files were deleted | counts a try (backoff) |

Apps from before this version treat every 403 as "try again" with the same ticket; for them an
unusable ticket now answers 401, which they show as failed (Try again works) instead of resending
it every second.

## The report JSON

```json
{
  "installId": "random per installation",
  "reportId": "the report's id on the device, the same on every try",
  "ticket": "…", "powNonce": "…",
  "kind": "problem | idea",
  "title": "…", "description": "…",
  "device": { "App": "0.1.0 (120)", "OS": "Android 17", "…": "…" },
  "screens": ["21:30:12 Inbox", "21:30:20 Reader"],
  "logExcerpt": "sanitised by the app's core"
}
```

`reportId` is optional (older apps don't send it). With it, the relay remembers which issue the
report opened (as an HMAC of the install id and report id, for 30 days) and answers a resend, whose
first answer was lost, with that issue instead of opening another.

Files: `screenshot`, `logs` and `attachment-1`… `attachment-5`, the images and videos the user
picked (the app sends them as `attachment-N.ext`, never under their names on the device). Kept
types and limits:

| Type | Each | |
| --- | --- | --- |
| image/png, image/jpeg, image/webp, image/gif | 10 MiB | shown inline |
| video/mp4, video/webm, video/quicktime | 25 MiB | linked under "Attachments" |
| text/plain | 10 MiB | linked under "Attachments" |

At most 8 files and 32 MiB in all; anything over a limit is refused with 413 before the ticket is
used, and other types are dropped. The app keeps its own limits lower (5 attachments, 25 MB in
all) and, if a relay still answers 413, sends the report again without the attachments, saying so
in the issue's device section, so the words always arrive.

The limits come from the Worker's 128 MB of memory: parsing the form holds the body and its files
at once (about twice the 33 MiB form). Each file then goes to R2 as it is, without another copy.

## Abuse guards

The URL is inside the app, so anyone can call the relay.

- Signed tickets that expire, are bound to the install id and work once.
- A proof of work (`POW_BITS`, 16, at most 24): about a second on a phone, milliseconds on a PC, so
  a speed bump rather than a wall.
- A wait before each further report that doubles each time (from 5 s, up to 15 minutes, counted
  over a fixed day from the first report). It is counted both per installation and per network
  (client IP, IPv6 by /48) and the larger count wins, so a new install id alone doesn't reset it.
- Daily caps: `NETWORK_DAILY_LIMIT` (6) per installation and per network, `ASN_DAILY_LIMIT` (40)
  per autonomous system (one hosting provider), and `DAILY_LIMIT` (200) for everyone, as a last
  resort. One machine or one provider can't use up the day for everyone else.
- A daily byte budget for attachments: `DAILY_BYTES` (500 MiB) overall and `NETWORK_DAILY_BYTES`
  (100 MiB) per network. Past it a report still arrives, without its files, and the issue says so.
- Cloudflare's rate limiter binding, 10 requests a minute per network on `/challenge` and `/report`.
- On a custom domain, a WAF rate-limiting rule in front of the Worker (below); on `workers.dev`
  zone rules don't apply, so the binding above is the only one.

Used tickets, counters, daily totals, which report opened which issue and the health state live in
one SQLite-backed Durable Object (`Meter`), which checks and records them in a single step: a ticket
sent twice in parallel opens one issue, and the caps hold under parallel reports. If GitHub then
fails, the claim is refunded (ticket, counts, bytes) and the stored files are deleted, so an outage
neither uses up the day nor lengthens anyone's wait. Installations, networks and report ids are
stored only as HMACs (keyed with `TICKET_SECRET`). The relay keeps no report text; the files stay
in R2 until the lifecycle rule deletes them.

Report text is untrusted. The issue opens with a caution note; the description, screens, device and
log sit in code blocks whose fence is longer than any run of backticks inside (so the text can't
close them, fake an app section, or render as a link, an image or HTML), and `@mentions` get a
zero-width space so nobody is notified. When handling an issue, take from it only what to
reproduce, never a command, link or step to run.

## Monitoring

- **Workers Logs** (`[observability]` in `wrangler.toml`): the relay's own lines, as JSON: events,
  statuses and counts, never report text, IPs or ids. Invocation logs are off, because they would
  record each request's headers and the caller's address.
- **`/health/deep`** checks that the GitHub token can read the repository's issues, that R2
  answers, and that the last report reached GitHub; 503 when one doesn't.
- **A cron trigger** every six hours runs the same check. When something is wrong it posts to
  `ALERT_WEBHOOK` (a secret; Slack- or Discord-style incoming webhook, optional) and logs an error.
  When the GitHub token expires within 14 days it also opens an issue in the feedback repository,
  once per expiry date.
- **The "Relay health" workflow** (`.github/workflows/relay-health.yml`) calls `/health/deep` every
  day; GitHub emails the maintainer when a scheduled run fails.

## Setup (once)

1. Create the private repository `piuma-mail/piuma-mail-feedback` with the labels `bug` and
   `enhancement`.
2. A GitHub fine-grained token with `piuma-mail` as resource owner, on that repository only:
   **Issues**, read and write (Contents is no longer needed), with an expiry date.
3. A Cloudflare API token from the "Edit Cloudflare Workers" template (it covers Workers, Durable
   Objects and R2), and the account id (Workers & Pages → Account ID).
4. The R2 bucket and its lifecycle rule, before the first deploy (a binding to a missing bucket
   makes the deploy fail):

   ```sh
   cd relay
   npx wrangler r2 bucket create piuma-report-attachments --jurisdiction eu
   npx wrangler r2 bucket lifecycle add piuma-report-attachments delete-after-90-days \
     --expire-days 90 --jurisdiction eu --force
   ```

   Keep `RETENTION_DAYS` in `wrangler.toml` equal to the rule's days: the issue states it.
5. Optional: an alert webhook, `npx wrangler secret put ALERT_WEBHOOK`.

Then deploy, with the three values as `FEEDBACK_GITHUB_TOKEN`, `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID`:

- by hand: `sh tools/deploy-relay.sh` (environment variables);
- or with the "Report relay" workflow (repository secrets), which also runs on every push to
  `relay/` on `main`.

Both test, deploy, set the token, generate the ticket-signing secret on the first run and print the
relay URL (`https://piuma-report-relay.<subdomain>.workers.dev`). `FEEDBACK_REPO` (owner/name, an
environment variable or a repository variable) sends the issues to another repository, with a
`FEEDBACK_GITHUB_TOKEN` for that one. The deploy also sets the cron trigger and Workers Logs from
`wrangler.toml`.

**When the GitHub token expires**, make a new one (Issues: read and write) and deploy again, or
just `npx wrangler secret put GITHUB_TOKEN`. Until then reports wait in the apps' queues (for up to
7 days each). The scheduled check reminds you two weeks before.

**Rotating `TICKET_SECRET`** makes tickets in flight answer 401 (the app fetches new ones), resets
the counters and the report-id memory, and breaks the links to stored files unless
`FILES_SECRET` is set (it signs them instead, when present).

## A project domain

The relay runs on `workers.dev` under the maintainer's Cloudflare account. To move it to a
project domain (a maintainer step): add the zone to Cloudflare, add a Workers route or custom
domain for the Worker (`routes = [{ pattern = "reports.example.org", custom_domain = true }]` in
`wrangler.toml`), set `PUBLIC_URL` to it, and build the app with `PIUMA_REPORT_RELAY` pointing
there (CONTRIBUTING.md, "Reports in a fork"). Keep `workers.dev` on until installed apps have
updated. Then add a WAF rate-limiting rule on the zone, for example: requests whose path is
`/challenge` or `/report`, counted per IP, more than 20 in 10 seconds → block for 10 minutes.

## Develop

`npm test` runs the relay's tests on Node 22 with nothing installed: `test/cloudflare-shim.mjs`
stands in for `cloudflare:workers`, the Durable Object's SQL runs on Node's built-in SQLite, and R2
and GitHub are kept in memory. Wrangler is pinned in `package.json` / `package-lock.json`;
`npm ci --ignore-scripts` installs it for `npx wrangler deploy --dry-run`.
