#!/usr/bin/env bash
set -euo pipefail

# ================= CONFIG =================
AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER="${CLUSTER:?ECS cluster required}"
SERVICE="${SERVICE:?ECS service required}"
TIMEOUT="${TIMEOUT:-300}"

echo "↩️ Starting ECS rollback"
echo "Cluster=$CLUSTER | Service=$SERVICE | Region=$AWS_REGION"

command -v aws >/dev/null || { echo "❌ aws CLI missing"; exit 1; }

# ================= FETCH DEPLOYMENT HISTORY =================
echo "📦 Fetching recent task definitions..."

TASK_DEFS=$(aws ecs describe-services \
  --cluster "$CLUSTER" \
  --services "$SERVICE" \
  --query "services[0].deployments[].taskDefinition" \
  --output text)

CURRENT_TASK_DEF=$(echo "$TASK_DEFS" | awk '{print $1}')
PREVIOUS_TASK_DEF=$(echo "$TASK_DEFS" | awk '{print $2}')

if [[ -z "$PREVIOUS_TASK_DEF" ]]; then
  echo "❌ No previous task definition found — cannot rollback"
  exit 1
fi

echo "Current:  $CURRENT_TASK_DEF"
echo "Previous: $PREVIOUS_TASK_DEF"

# ================= PERFORM ROLLBACK =================
echo "🚑 Rolling back to previous stable task definition..."

aws ecs update-service \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --task-definition "$PREVIOUS_TASK_DEF" \
  --force-new-deployment \
  --deployment-circuit-breaker "enable=true,rollback=true" \
  >/dev/null

# ================= WAIT FOR STABILITY =================
echo "⏳ Waiting for rollback stability (timeout=${TIMEOUT}s)"

if ! timeout "$TIMEOUT" aws ecs wait services-stable \
  --cluster "$CLUSTER" \
  --services "$SERVICE"; then
  echo "❌ Rollback failed or timed out"
  exit 1
fi

echo "✅ Rollback successful — service restored to last stable version"
