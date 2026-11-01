# Security policy

Piuma Mail is beta software. Security fixes go into `main` and ship with the next beta; older
betas are not patched.

## Reporting a vulnerability

Please do not open a public issue, pull request or in-app report for a vulnerability.

Report it privately through GitHub: on this repository, open the **Security** tab and choose
**Report a vulnerability** ([direct link](https://github.com/piuma-mail/piuma-mail/security/advisories/new)).
Include what is affected, how to reproduce it, the version or commit, and the impact you expect.
Leave real credentials and mail content out of the report.

Once a fix is available, the advisory is published and you are credited, unless you prefer
otherwise.

## Scope

- The app and its Rust engine ([`app/`](app/), [`core/`](core/), [`wear/`](wear/)).
- The report relay ([`relay/`](relay/)).
- The release workflow and the published betas.

Problems in a mail provider's own servers belong to that provider.
