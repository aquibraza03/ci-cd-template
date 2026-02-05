#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
CLUSTER="${CLUSTER:?ECS cluster required}"
SERVICE="${SERVICE:?ECS service required}"
IMAGE_URI="${IMAGE_URI:?Image URI required}"
TIMEOUT="${TIMEOUT:-300}"

echo "🚀 Zero-downtime ECS deploy"
echo "Cluster=$CLUSTER | Service=$SERVICE | Image=$IMAGE_URI"

command -v aws >/dev/null || { echo "❌ aws CLI missing"; exit 1; }

# ================= CURRENT TASK DEF =================
CURRENT_TASK_DEF_ARN=$(aws ecs describe-services \\
  --cluster "$CLUSTER" \\
  --services "$SERVICE" \\
  --query "services[0].taskDefinition" \\
  --output text)

echo "Current task definition: $CURRENT_TASK_DEF_ARN"

# ================= CREATE NEW REVISION =================
aws ecs describe-task-definition \\
  --task-definition "$CURRENT_TASK_DEF_ARN" \\
  --query "taskDefinition" > task-def.json

jq --arg IMAGE "$IMAGE_URI" \\
  '.containerDefinitions[0].image = $IMAGE
   | del(.taskDefinitionArn,.revision,.status,.requiresAttributes,.compatibilities,.registeredAt,.registeredBy)' \\
  task-def.json > new-task-def.json

NEW_TASK_DEF_ARN=$(aws ecs register-task-definition \\
  --cli-input-json file://new-task-def.json \\
  --query "taskDefinition.taskDefinitionArn" \\
  --output text)

echo "New task definition: $NEW_TASK_DEF_ARN"

# ================= SAFE DEPLOY =================
aws ecs update-service \\
  --cluster "$CLUSTER" \\
  --service "$SERVICE" \\
  --task-definition "$NEW_TASK_DEF_ARN" \\
  --force-new-deployment \\
  --deployment-circuit-breaker "enable=true,rollback=true" \\
  >/dev/null

# ================= ROLLOUT HEALTH VISIBILITY =================
echo "🔍 Checking rollout status..."
aws ecs describe-services \\
  --cluster "$CLUSTER" \\
  --services "$SERVICE" \\
  --query 'services[0].deployments[0].rolloutState' \\
  --output text

# ================= WAIT WITH TIMEOUT =================
echo "⏳ Waiting for stability (timeout=${TIMEOUT}s)"

if ! timeout "$TIMEOUT" aws ecs wait services-stable \\
  --cluster "$CLUSTER" \\
  --services "$SERVICE"; then

  echo "❌ Deployment did not stabilize in time"
  exit 1
fi

echo "✅ Deployment successful — service stable"
