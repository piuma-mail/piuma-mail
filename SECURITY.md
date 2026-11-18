# Security policy

Piuma Mail is beta software. Security fixes go into `main` and ship with the next beta; older
betas are not patched.

## Reporting a vulnerability

Please do not open a public issue, pull request or in-app report for a vulnerability.

Report it privately through GitHub: on this repository, open the **Security** tab and choose
**Report a vulnerability** ([direct link](https://github.com/piuma-mail/piuma-mail/security/advisories/new)).
Include what is affected, how to reproduce it, the version or commit, and the impact you expect.
Leave real credentials and mail content out of the report.

## What happens next

Piuma Mail is maintained by a small team, mostly one person. What you can expect:

| Step | When |
|---|---|
| We confirm we received your report | within 5 days |
| First assessment: whether we can reproduce it and how serious it is | within 14 days |
| A fix released, for serious issues | as soon as we can, and we aim for 30 days |
| Public disclosure | when the fix is out, or after 90 days, agreed with you |

We keep you posted in the advisory's private thread. Once a fix is available, the advisory is
published and you are credited, unless you prefer otherwise. If you hear nothing within the times
above, comment on the advisory again.

## Checking a download

Every file of a release is built by the "Release" workflow from a commit of `main` and carries a
build provenance attestation; `SHA256SUMS` in the same release lists every file's checksum and is
attested too. Check a file with the GitHub CLI, naming the workflow and the branch it must come from
(without them any workflow of the repository, on any branch, would pass):

```sh
gh attestation verify PiumaMail-android-arm64.apk --repo piuma-mail/piuma-mail \
  --signer-workflow piuma-mail/piuma-mail/.github/workflows/release.yml \
  --source-ref refs/heads/main
sha256sum -c SHA256SUMS --ignore-missing
```

How the project defends itself, and what it does when something goes wrong:
[docs/threat-model.md](docs/threat-model.md) and [docs/incident-runbook.md](docs/incident-runbook.md).

## Scope

- The app and its Rust engine ([`app/`](app/), [`core/`](core/), [`wear/`](wear/)).
- The report relay ([`relay/`](relay/)).
- The release workflow and the published betas.

Problems in a mail provider's own servers belong to that provider.
