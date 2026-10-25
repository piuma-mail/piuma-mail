#!/bin/sh
# Deploys the report relay (relay/) to Cloudflare Workers by hand, the same
# steps as .github/workflows/report-relay.yml: test, deploy, set the GitHub
# token, create the ticket-signing secret once, check /health.
#
# The credentials come from the environment, never from the repository:
#   CLOUDFLARE_API_TOKEN   token from the "Edit Cloudflare Workers" template
#   CLOUDFLARE_ACCOUNT_ID  the Cloudflare account id
#   FEEDBACK_GITHUB_TOKEN  fine-grained token on the feedback repository only:
#                          Issues + Contents, read and write
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
if ! npx --no-install wrangler secret list | grep -q '"TICKET_SECRET"'; then
  openssl rand -hex 32 | tr -d '\n' | npx --no-install wrangler secret put TICKET_SECRET
fi

url=$(grep -Eo 'https://[a-z0-9.-]+\.workers\.dev' "$log" | head -1)
echo "Relay: $url"
sleep 5
curl -fsS "$url/health"
echo
