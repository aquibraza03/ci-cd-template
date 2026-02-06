#!/usr/bin/env bash
set -euo pipefail

# ================= CONFIG =================
AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER="${CLUSTER:?ECS cluster required}"
SERVICE="${SERVICE:?ECS service required}"
IMAGE_URI="${IMAGE_URI:?Image URI required}"
HEALTH_URL="${HEALTH_URL:-}"
TIMEOUT="${TIMEOUT:-300}"
HEALTH_RETRIES="${HEALTH_RETRIES:-12}"
HEALTH_INTERVAL="${HEALTH_INTERVAL:-5}"
NOTIFY_SCRIPT="${NOTIFY_SCRIPT:-ci/notify.sh}"

START_TIME=$(date +%s)

echo "🚀 Principal Zero-Downtime Deploy"
echo "Cluster=$CLUSTER | Service=$SERVICE | Image=$IMAGE_URI"

# ================= DEPENDENCY CHECKS =================
for cmd in aws jq curl timeout; do
  command -v "$cmd" >/dev/null || { echo "❌ Missing dependency: $cmd"; exit 1; }
done

# ================= CURRENT TASK DEF =================
CURRENT_TASK_DEF_ARN=$(aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query "services[0].taskDefinition" \
  --output text)

echo "Current task definition: $CURRENT_TASK_DEF_ARN"

# ================= CREATE NEW REVISION =================
aws ecs describe-task-definition \
  --task-definition "$CURRENT_TASK_DEF_ARN" \
  --query "taskDefinition" > task-def.json

jq --arg IMAGE "$IMAGE_URI" \
  '.containerDefinitions[0].image = $IMAGE
   | del(.taskDefinitionArn,.revision,.status,.requiresAttributes,.compatibilities,.registeredAt,.registeredBy)' \
  task-def.json > new-task-def.json

NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \
  --cli-input-json file://new-task-def.json \
  --query "taskDefinition.taskDefinitionArn" \
  --output text)

echo "New task definition: $NEW_TASK_DEF_ARN"

# ================= SAFE DEPLOY =================
aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "$NEW_TASK_DEF_ARN" \
  --force-new-deployment \
  --deployment-circuit-breaker "enable=true,rollback=true" \
  >/dev/null

# ================= WAIT FOR ECS STABILITY =================
FAILED=false

if ! timeout "$TIMEOUT" aws ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE"; then
  echo "❌ ECS did not stabilize"
  FAILED=true
fi

# ================= APPLICATION HEALTH CHECK =================
if [[ "$FAILED" == "false" && -n "$HEALTH_URL" ]]; then
  echo "🔍 Verifying application health..."

  for ((i=1; i<=HEALTH_RETRIES; i++)); do
    if curl -fsS "$HEALTH_URL" >/dev/null; then
      echo "✅ Health check passed"
      break
    fi

    echo "⏳ Health retry $i/$HEALTH_RETRIES..."
    sleep "$HEALTH_INTERVAL"

    if [[ "$i" -eq "$HEALTH_RETRIES" ]]; then
      echo "❌ Health check failed"
      FAILED=true
    fi
  done
fi

# ================= AUTO ROLLBACK =================
if [[ "$FAILED" == "true" ]]; then
  echo "↩️ Rolling back to previous task definition..."

  aws ecs update-service \
    --cluster "$CLUSTER" \
    --service "$SERVICE" \
    --task-definition "$CURRENT_TASK_DEF_ARN" \
    --force-new-deployment >/dev/null

  if ! timeout "$TIMEOUT" aws ecs wait services-stable \
    --cluster "$CLUSTER" \
    --services "$SERVICE"; then
    echo "❌ Rollback FAILED — manual intervention required"
    exit 2
  fi

  STATUS="failure"
else
  STATUS="success"
fi

# ================= OBSERVABILITY =================
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "📊 Deploy status: $STATUS | Duration: ${DURATION}s"

# GitHub summary
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## Deployment Result"
    echo "- Status: **$STATUS**"
    echo "- Image: \`$IMAGE_URI\`"
    echo "- Duration: ${DURATION}s"
  } >> "$GITHUB_STEP_SUMMARY"
fi

# External notify
if [[ -f "$NOTIFY_SCRIPT" ]]; then
  STATUS="$STATUS" IMAGE_URI="$IMAGE_URI" ENVIRONMENT="production" \
  bash "$NOTIFY_SCRIPT" || true
fi

# ================= FINAL EXIT =================
[[ "$STATUS" == "success" ]] && exit 0 || exit 1

