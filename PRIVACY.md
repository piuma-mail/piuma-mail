# Privacy notice: in-app reports

> The names, places and periods below are the project's defaults; a build made by someone else (a fork) can name its own, and the app shows the ones it
> was built with under Settings › Help & feedback › Reports and privacy.

Piuma Mail reads and sends your mail directly between your device and your mail servers: no server
of the project sees your mailbox. The only thing the app can send to the project is a **report** (a
problem or an idea) that you write and send yourself from Settings › Help & feedback, the report
sheet, or the line offered after a crash. This notice covers those reports.

## Who handles reports

- **Controller:** Matteo Maraffio, maintainer of Piuma Mail (a build can set another with
  `PIUMA_PRIVACY_CONTROLLER`).
- **Contact for anything about your data:** piuma@matteomaraffio.com (a build can set another with
  `PIUMA_PRIVACY_CONTACT`).

## What is sent

Only what you see under "See what's sent" before you send, and nothing on its own:

- the title and description you write;
- device and app details: app version, operating system, device model, screen size, language,
  network type (Wi-Fi or mobile), the screen you were on and the last screens you visited, how many
  accounts of each type you have and what their IMAP servers support;
- if you leave them on: the screenshot (off by default, with the parts you choose blurred), the
  app's recent log, and images or videos you attach (sent as `attachment-1.png`…, never under their
  names on your device).

The log is scrubbed on the device of addresses, account names, server names, subjects, mailbox
names, search terms, what servers wrote back, quoted text, links, file paths, tokens and the names of
the people in your mail. Scrubbing is a best effort: check the log under "See what's sent" before
sending, or switch it off.

To limit abuse, the relay also processes your IP address and a random id the app makes when it is
installed. It keeps only keyed hashes of them (the network as an IPv4 address or IPv6 /48 block, and
the provider's network number), for at most two days, to space out and cap reports. So that people
who already use the app can still report while someone floods the relay, it also keeps the keyed
hash of the installation's id with the time of its first report: for 7 days, or 90 days after
its last report.

## Where it goes

1. The report goes over HTTPS to the project's **report relay**, a Cloudflare Worker
   (`piuma-report-relay.matte-maraffio.workers.dev`; a build can set another with
   `PIUMA_REPORT_RELAY`). Cloudflare runs it in its data centres worldwide.
2. The relay stores the screenshot, log and attachments in **Cloudflare R2, in the EU
   jurisdiction**, and opens a **private issue on GitHub** in the repository
   `piuma-mail/piuma-mail-feedback`, with links to those files. GitHub stores issues in the
   **United States**.

Instead of the relay you can choose "Send by email instead": the report then goes as an email from
your own account to the contact above, and the rest of this section does not apply.

## Who sees it

The maintainer and the people who help maintain Piuma Mail with access to the private repository,
and the tools they use to sort and reproduce reports, AI coding assistants included. Reports are
never sold, shared for advertising, or published. Cloudflare and GitHub process them as service
providers.

## How long it is kept

- **Attachments** (screenshot, log, images, videos): deleted automatically **90 days** after the
  report (a lifecycle rule on the storage).
- **The issue** (your words, device details, log excerpt): kept while it helps fix the problem, and
  deleted when it is no longer needed, at the latest **two years** after it is closed (a scheduled
  job deletes older closed issues).
- **The relay's counters:** at most two days. Which report opened which issue (an id the app makes,
  hashed): 30 days, so a report sent twice opens one issue. When the installation first reported (its
  id, hashed): 7 days, or 90 days after its last report.
- **On your device:** Your reports keeps your reports until you delete them. Deleting a report there
  removes only the copy on your device; the app then offers to ask for the issue to be erased too.

## Your rights

You can ask to see what is kept about your reports, to correct it or to have it erased, by writing to
the contact above with the report number (shown as "Sent #N" in Your reports). Deleting a report
already sent in the app offers to write that email for you. You can also lodge a complaint with your
data protection authority (in Italy, the Garante per la protezione dei dati personali).

The legal basis is your consent, given each time you send a report; you can withdraw it at any time
for the future by asking for erasure.

## Changes

This notice lives in the repository, so every change to it is public in its history.
