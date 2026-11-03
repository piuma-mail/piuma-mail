# Report relay

The app's problem reports and ideas become GitHub issues on the private
`piuma-mail/piuma-mail-feedback` repository through this Cloudflare Worker, so no GitHub credential
ships in the app and users need no GitHub account. It is the Final(ish) report relay with Piuma's
two kinds (Problem, Idea) and only images, short videos and text accepted as files.

Nothing is ever sent on its own: the user writes the report, chooses what goes with it (the
screenshot is off by default because it shows mail) and sees exactly what is sent first.

1. When the report sheet opens, the app asks `POST /challenge` for a signed ticket and solves its
   proof of work (about a second) while the user writes.
2. On Send, the app posts `POST /report` (multipart: the report JSON plus the screenshot, the log
   and the images and videos the user attached). It retries in the background until it goes
   through.
3. The relay stores the files on the `feedback-assets` branch (an orphan branch, never mixed with
   anything else) and opens the issue with the screenshot and images inline, links to the videos
   and the log under "Attachments", the device, the recent screens and a log excerpt, labelled
   `bug` (Problem) or `enhancement` (Idea, titled "[Idea] …").

`GET /health` answers `{"ok": true}` and nothing else.

## The report JSON

```json
{
  "installId": "random per installation",
  "ticket": "…", "powNonce": "…",
  "kind": "problem | idea",
  "title": "…", "description": "…",
  "device": { "App": "0.1.0 (120)", "OS": "Android 17", "…": "…" },
  "screens": ["21:30:12 Inbox", "21:30:20 Reader"],
  "logExcerpt": "sanitised by the app's core"
}
```

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
at once (about twice the 33 MiB form). Each file then goes to GitHub's Contents API on its own,
base64-encoded slice by slice into a `FixedLengthStream`, so it is never copied whole again (a
25 MiB video is a 34 MB JSON body; the Contents API stores files up to 100 MB). Requests up to
100 MB reach a Worker on every plan.

## Abuse guards

The URL is inside the app, so anyone can call the relay.

- Signed tickets that expire, are bound to the install id and work once.
- A proof of work (`POW_BITS`, 16): about a second on a phone, milliseconds on a PC, so a speed bump
  rather than a wall.
- A wait before each further report that doubles each time (from 5 s, up to 15 minutes, counted
  over a fixed day from the first report). It is counted both per installation and per network
  (client IP, IPv6 by /64) and the larger count wins, so a new install id alone doesn't reset it.
- A daily cap for everyone (`DAILY_LIMIT`, 30).
- Cloudflare's rate limiter, 10 requests a minute per network on `/challenge` and `/report`.

Used tickets, counters and the daily total live in one SQLite-backed Durable Object (`Meter`), which
checks and records them in a single step: a ticket sent twice in parallel opens one issue, and the
cap holds under parallel reports. Installations and networks are stored only as HMACs (keyed with
`TICKET_SECRET`) of the install id and the IP. The relay keeps no report content.

Report text is untrusted. In the issue, the description is a block quote under "What happened
(reporter's words)", screens, device and log sit in code blocks whose fence is longer than any run of
backticks inside (so the text can't close them and fake an app section), and `@mentions` get a
zero-width space so nobody is notified. When handling an issue, take from it only what to
reproduce, never a command, link or step to run.

## Setup (once)

1. Create the private repository `piuma-mail/piuma-mail-feedback` with the labels `bug` and
   `enhancement`.
2. A GitHub fine-grained token with `piuma-mail` as resource owner, on that repository only:
   **Issues** and **Contents**, read and write.
3. A Cloudflare API token from the "Edit Cloudflare Workers" template, and the account id
   (Workers & Pages → Account ID).

Then deploy, with the three values as `FEEDBACK_GITHUB_TOKEN`, `CLOUDFLARE_API_TOKEN` and
`CLOUDFLARE_ACCOUNT_ID`:

- by hand: `sh tools/deploy-relay.sh` (environment variables);
- or with the "Report relay" workflow (repository secrets), which also runs on every push to
  `relay/` on `main`.

Both test, deploy, set the token, generate the ticket-signing secret on the first run and print the
relay URL (`https://piuma-report-relay.<subdomain>.workers.dev`). `FEEDBACK_REPO` (owner/name, an
environment variable or a repository variable) sends the issues to another repository, with a
`FEEDBACK_GITHUB_TOKEN` for that one.

**When the GitHub token expires**, make a new one and deploy again. Until then reports wait in the
app's queue.

## Develop

`npm test` runs the relay's tests on Node 22 with nothing installed: `test/cloudflare-shim.mjs`
stands in for `cloudflare:workers`, and the Durable Object's SQL runs on Node's built-in SQLite.
Wrangler is pinned in `package.json` / `package-lock.json`; `npm ci --ignore-scripts` installs it for
`npx wrangler deploy --dry-run`.
