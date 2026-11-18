#!/bin/sh
# Deploys the report relay (relay/) to Cloudflare Workers by hand, the same
# steps as .github/workflows/report-relay.yml: test, deploy, set the GitHub
# token, create the ticket-signing and attachment-link secrets once (never
# rotated here), then check /health/deep: GitHub and storage must answer.
#
# The credentials come from the environment, never from the repository:
#   CLOUDFLARE_API_TOKEN   token from the "Edit Cloudflare Workers" template
#   CLOUDFLARE_ACCOUNT_ID  the Cloudflare account id
#   FEEDBACK_GITHUB_TOKEN  fine-grained token on the feedback repository only:
#                          Issues, read and write
#
# The R2 bucket and its lifecycle rule must exist first: relay/README.md, "Setup".
#   FEEDBACK_REPO          optional "owner/name"; REPO in relay/wrangler.toml
#                          when unset
#
# Usage: sh tools/deploy-relay.sh
set -eu

root=$(cd "$(dirname "$0")/.." && pwd)
cd "$root/relay"

for v in CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID FEEDBACK_GITHUB_TOKEN; do
  eval "val=\${$v:-}"
  if [ -z "$val" ]; then
    echo "$v must be set." >&2
    exit 1
  fi
done

npm ci --ignore-scripts
npm test

log=$(mktemp)
trap 'rm -f "$log"' EXIT
if [ -n "${FEEDBACK_REPO:-}" ]; then
  if ! printf '%s' "$FEEDBACK_REPO" | grep -Eq '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
    echo "FEEDBACK_REPO must be owner/name." >&2
    exit 1
  fi
  npx --no-install wrangler deploy --var "REPO:$FEEDBACK_REPO" | tee "$log"
else
  npx --no-install wrangler deploy | tee "$log"
fi

printf '%s' "$FEEDBACK_GITHUB_TOKEN" | npx --no-install wrangler secret put GITHUB_TOKEN
secrets=$(npx --no-install wrangler secret list)
# FILES_SECRET signs the attachment links in issues, apart from tickets, so
# rotating TICKET_SECRET never breaks them. Both are made once, here.
for name in TICKET_SECRET FILES_SECRET; do
  if ! printf '%s' "$secrets" | grep -q "\"$name\""; then
    openssl rand -hex 32 | tr -d '\n' | npx --no-install wrangler secret put "$name"
  fi
done
if ! npx --no-install wrangler secret list | grep -q '"FILES_SECRET"'; then
  echo "FILES_SECRET is missing: reports would arrive without attachments." >&2
  exit 1
fi

url=$(grep -Eo 'https://[a-z0-9.-]+\.workers\.dev' "$log" | head -1)
echo "Relay: $url"
sleep 5
curl -fsS "$url/health"
echo
# The deep check runs again for a new version: GitHub (the token) and R2
# (with FILES_SECRET) must work. A failed last report alone is only a warning:
# it clears with the next report that goes through.
deep=$(curl -sS --max-time 30 "$url/health/deep")
echo "$deep"
if ! printf '%s' "$deep" | grep -q '"github":true' || printf '%s' "$deep" | grep -q '"storage":false'; then
  echo "The relay is deployed but /health/deep fails: see relay/README.md, Monitoring." >&2
  exit 1
fi
if printf '%s' "$deep" | grep -q '"lastReportFailed":true'; then
  echo "Warning: the last report before this deploy could not be filed." >&2
fi
