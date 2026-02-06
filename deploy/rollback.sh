#!/usr/bin/env bash
set -euo pipefail

# ================= CONFIG =================
AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER="${CLUSTER:?ECS cluster required}"
SERVICE="${SERVICE:?ECS service required}"
TIMEOUT="${TIMEOUT:-300}"
HEALTH_URL="${HEALTH_URL:-}"
NOTIFY_SCRIPT="${NOTIFY_SCRIPT:-ci/notify.sh}"

START_TIME=$(date +%s)

echo "↩️ Principal ECS rollback"
echo "Cluster=$CLUSTER | Service=$SERVICE"

for cmd in aws jq curl timeout; do
  command -v "$cmd" >/dev/null || { echo "❌ Missing dependency: $cmd"; exit 1; }
done

# ================= FETCH DEPLOYMENTS SAFELY =================
DEPLOYMENTS_JSON=$(aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query "services[0].deployments" \
  --output json)

CURRENT_TASK_DEF=$(echo "$DEPLOYMENTS_JSON" | jq -r '.[] | select(.status=="PRIMARY") | .taskDefinition')
PREVIOUS_TASK_DEF=$(echo "$DEPLOYMENTS_JSON" | jq -r '.[] | select(.status!="PRIMARY") | .taskDefinition' | head -n1)

if [[ -z "$PREVIOUS_TASK_DEF" || "$PREVIOUS_TASK_DEF" == "null" ]]; then
  echo "❌ No previous task definition found — cannot rollback"
  exit 1
fi

echo "Current:  $CURRENT_TASK_DEF"
echo "Previous: $PREVIOUS_TASK_DEF"

# ================= EXECUTE ROLLBACK =================
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "$PREVIOUS_TASK_DEF" \
  --force-new-deployment \
  --deployment-circuit-breaker "enable=true,rollback=true" \
  >/dev/null

FAILED=false

# ================= WAIT FOR ECS STABILITY =================
if ! timeout "$TIMEOUT" aws ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE"; then
  echo "❌ Rollback ECS stabilization failed"
  FAILED=true
fi

# ================= HEALTH CHECK =================
if [[ "$FAILED" == "false" && -n "$HEALTH_URL" ]]; then
  echo "🔍 Verifying application health..."

  if ! timeout 60 bash -c "until curl -fsS '$HEALTH_URL' >/dev/null; do sleep 5; done"; then
    echo "❌ Rollback health check failed"
    FAILED=true
  fi
fi

# ================= OBSERVABILITY =================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

STATUS=$([[ "$FAILED" == "true" ]] && echo "failure" || echo "success")

echo "📊 Rollback status: $STATUS | Duration: ${DURATION}s"

if [[ -f "$NOTIFY_SCRIPT" ]]; then
  STATUS="$STATUS" IMAGE_URI="$PREVIOUS_TASK_DEF" ENVIRONMENT="production" \
  bash "$NOTIFY_SCRIPT" || true
fi

# ================= FINAL EXIT =================
[[ "$FAILED" == "true" ]] && exit 1 || exit 0

