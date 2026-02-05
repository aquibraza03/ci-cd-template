#!/usr/bin/env bash
set -euo pipefail

# ================= CONFIG =================
STATUS="${STATUS:-success}"                 # success | failure | started
WEBHOOK_URL="${WEBHOOK_URL:-}"
ENVIRONMENT="${ENVIRONMENT:-ci}"
SERVICE="${SERVICE:-app}"
IMAGE_URI="${IMAGE_URI:-}"
COMMIT_SHA="${COMMIT_SHA:-$(git rev-parse --short HEAD)}"
BRANCH="${BRANCH:-$(git rev-parse --abbrev-ref HEAD)}"
ACTOR="${ACTOR:-unknown}"
RUN_ID="${RUN_ID:-local}"
TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

# ================= VALIDATION =================
if [[ -z "$WEBHOOK_URL" ]]; then
  echo "⚠️ WEBHOOK_URL not set — skipping notification"
  exit 0
fi

echo "🔔 Sending $STATUS notification to n8n"

# ================= BUILD JSON PAYLOAD =================
payload() {
  cat <<EOF
{
  "status": "$STATUS",
  "environment": "$ENVIRONMENT",
  "service": "$SERVICE",
  "image": "$IMAGE_URI",
  "commit": "$COMMIT_SHA",
  "branch": "$BRANCH",
  "actor": "$ACTOR",
  "run_id": "$RUN_ID",
  "timestamp": "$TIMESTAMP"
}
EOF
}

# ================= RETRY LOGIC =================
MAX_RETRIES=3
SLEEP_SECONDS=5

for ((i=1; i<=MAX_RETRIES; i++)); do
  echo "📡 Attempt $i → n8n webhook"

  if curl -sS -X POST "$WEBHOOK_URL" \
      -H "Content-Type: application/json" \
      -d "$(payload)"; then
    echo "✅ Notification sent"
    exit 0
  fi

  echo "⚠️ Failed attempt $i"
  sleep "$SLEEP_SECONDS"
done

echo "❌ All notification attempts failed"
exit 1
