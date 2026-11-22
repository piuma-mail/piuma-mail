# Files for the feedback repository

The in-app reports become issues in the private repository `piuma-mail/piuma-mail-feedback`.
The privacy notice ([PRIVACY.md](../../PRIVACY.md)) promises that an issue is deleted at the latest
two years after it is closed. GitHub has no setting for that, so the feedback repository runs a
workflow: [`.github/workflows/expire-issues.yml`](.github/workflows/expire-issues.yml).

It is kept here, where it is reviewed with the relay, and copied to the feedback repository by
hand. Nothing in this repository runs it.

## Enable it (maintainer)

1. Make a fine-grained token: resource owner `piuma-mail`, repository access **only**
   `piuma-mail/piuma-mail-feedback`, an expiry date, and the permissions **Issues: read and write**
   and **Administration: read and write** (GitHub lets only administrators delete issues).
   Nothing else.
2. In the feedback repository, Settings › Secrets and variables › Actions: add it as the secret
   `ISSUE_EXPIRY_TOKEN`.
3. Copy the workflow to the feedback repository's default branch, at the same path
   (`.github/workflows/expire-issues.yml`), through a pull request there.
4. Run it by hand once (Actions › Expire closed issues › Run workflow, "delete" unticked): it only
   lists what it would delete, by number and closing date, in the run's summary and in the
   `expire-issues-<run>` artifact.
5. When the list looks right, add the repository variable `EXPIRE_ISSUES_DELETE` = `true`. From
   then on the weekly run (Mondays, 04:23 UTC) deletes them, at most 200 a run, and keeps its log
   as an artifact for 90 days. A manual run deletes only with "delete" ticked.

Deleting needs both the secret `ISSUE_EXPIRY_TOKEN` and the variable `EXPIRE_ISSUES_DELETE` set to
`true`: without the variable, every run is a dry run, ticked or not.

An issue labelled `keep` is never deleted (for example one still waiting for a fix); remove the
label when it can go. `EXPIRE_ISSUES_AFTER_DAYS` changes the 730 days, never below them.

When the token expires, the run fails and GitHub emails the maintainer: make a new one with the
same permissions.
