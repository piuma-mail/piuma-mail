# Incident runbook

What to do, in order, when something goes wrong. Each section starts with what to stop first. Keep
notes of what was done and when: they become the advisory or the post-mortem. Background: the
[threat model](threat-model.md). Reporters reach us through [SECURITY.md](../SECURITY.md).

Throughout, "the repository" is the one whose releases apps follow (`PIUMA_UPDATE_URL`); a fork
replaces names, secrets and services with its own.

## Signing key compromised

A signing key (Android keystore, Windows Authenticode certificate, Apple Developer ID) was leaked,
copied off a machine, or used for something we did not sign.

1. **Stop releases**: Settings › Environments › `release`: remove every deployment branch so nothing
   can publish; cancel running "Release" workflows.
2. **Find out what was signed**: compare every release's files with their attestations
   (`gh attestation verify <file> --repo <owner>/<repo> --signer-workflow
   <owner>/<repo>/.github/workflows/release.yml --source-ref refs/heads/main`, and
   `sha256sum -c SHA256SUMS`); a file without a matching attestation was
   not built by us.
3. **Revoke**:
   - Windows: ask the certificate authority to revoke the certificate (or disable the Azure Trusted
     Signing certificate profile) with the date of compromise, so earlier good signatures stay valid.
   - Apple: revoke the Developer ID certificate at developer.apple.com and tell Apple's product
     security; notarised malware can be blocked by Apple.
   - Android: an APK key cannot be revoked and a new key cannot update existing installs. Generate a
     new key; if the old one is still in our hands, ship a release signed with **key rotation**
     (`apksigner rotate` and a v3.1 signing lineage, Android 13+) so installs move to the new key;
     older Android versions need an uninstall and a fresh install (mail stays on the servers; local
     drafts and settings go). The Wear OS app moves with the phone app.
4. **Replace the secrets** (`WINDOWS_SIGN_*` or Azure, `APPLE_*`, `PIUMA_KEYSTORE_*`), update
   `PIUMA_ANDROID_CERT_SHA256`, store the new key's offline backup (see CONTRIBUTING.md).
5. **Tell users**: a GitHub security advisory and a pinned issue: what was affected, from when, how to
   check their copy, what to do. Delete releases carrying files we did not build (keep a copy for the
   investigation).
6. **Re-open releases** and ship a new release signed with the new key.

## Leaked GitHub token

A token with access to the repository (a personal access token, a leaked `GITHUB_TOKEN` from a run,
the relay's `FEEDBACK_GITHUB_TOKEN`) is public or used by someone else.

1. **Revoke it** at once: a personal or fine-grained token in its owner's settings; for the relay's
   token see [Relay abuse](#relay-abuse). A workflow's `GITHUB_TOKEN` expires when the job ends;
   cancel the run if it is still going.
2. **Look at what it did**: the organisation's audit log (Settings › Audit log), the repository's
   releases (any new or changed release or asset?), tags, branches, workflow files and settings
   (secrets, environments, branch protection, deploy keys, webhooks).
3. **Undo**: delete releases or assets it made (Windows apps take the highest version listed by the
   last ten releases: a fake release must go at once; then ship a new real one, with a higher number,
   so apps that took it move on; if the fake used a very high number, raise the offset added to the
   commit count in `release.yml` and `tools/windows-release.ps1` once, above it),
   restore protections, remove keys and webhooks it added.
4. **Rotate** anything it could read: the repository's Actions secrets are not readable through the
   API, but if it could change workflows assume every secret is leaked and rotate all of them.
5. **Advisory** if a release, the feedback repository or users' reports were touched.

## Bad release

A release crashes at launch, loses data, breaks sync or sending, or is otherwise harmful.

Velopack does not downgrade: installed apps only move to a **higher** version. The fix always ships as
a new release, N+1. Do not delete the bad release's tag to "go back": apps that took it stay on it.

1. **Stop the spread**:
   - Turn the bad release back into a draft (`gh release edit <tag> --draft=true`): apps no longer see
     it, so those that did not update yet stay where they are. Windows apps take the highest version
     listed by the last ten published releases, so the previous release becomes the newest again.
   - Users who already installed it: a Windows app that never reached its first frame looks for a
     newer release before it opens its engine on the next launch, so N+1 reaches them even if N
     crashes at once. Android, macOS and Linux users get the notice once N+1 is out.
2. **Fix forward**: revert or fix on `main` through a pull request; CI must pass. Release with
   **canary** first if there is any doubt, then beta.
3. **Database schema**: the bad release may have migrated users' databases. The next release opens
   them as they are:
   - Never remove, reorder or edit an entry of `MIGRATIONS` in `core/src/store.rs` once it shipped:
     databases already at that version would skip a different step. Undo a change with a **new**
     migration.
   - Migrations stay additive (new tables, new columns with defaults). An older build opening a newer
     database skips migrations it does not know, so additive changes keep it working too.
   - If the bad migration lost or damaged data, the new migration repairs what it can; mail comes back
     from the servers with a full resync, local-only data (drafts, outbox, settings) does not.
4. **Say what happened** in the new release's notes; a security issue also gets an advisory.

## Relay abuse

The report relay is flooded, used to post spam or abuse into the feedback repository, or its token
is suspected leaked.

1. **Stop it**: Cloudflare dashboard › Workers › the relay: disable its route (or deploy a version that
   answers 503). Reports that could not be sent stay in the app (Settings › Help & feedback › Your
   reports) and can be sent again later.
2. **If the token may be leaked**: revoke `FEEDBACK_GITHUB_TOKEN` (the fine-grained token, scoped to
   the feedback repository), make a new one with the same scope, update the repository secret and the
   Worker secret (`wrangler secret put GITHUB_TOKEN`, or re-run the "Report relay" workflow).
   Rotate `TICKET_SECRET` too (`wrangler secret put TICKET_SECRET` with a new random value): earlier
   tickets stop working.
3. **Clean up** the feedback repository: lock and close spam issues (keep them for the investigation;
   do not run anything they contain: issue text is untrusted data).
4. **Limit**: tighten the relay's rate limits or Cloudflare's WAF rules before turning it back on.
5. If users' reports were exposed, say so in an advisory.
