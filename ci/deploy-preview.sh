#!/usr/bin/env bash
set -euo pipefail

APP_TYPE="${APP_TYPE:-frontend}"          # frontend | backend | microservice
PREVIEW_ID="${PREVIEW_ID:-pr-${PR_NUMBER:-local}}"
AWS_REGION="${AWS_REGION:-ap-south-1}"
TTL_HOURS="${TTL_HOURS:-24}"

echo "🚀 Preview deploy | type=$APP_TYPE | id=$PREVIEW_ID"

# ---------- helpers ----------
expire_tag() {
  date -u -d "+$TTL_HOURS hours" +"%Y-%m-%dT%H:%M:%SZ"
}

comment_pr() {
  [[ -z "${GITHUB_TOKEN:-}" || -z "${PR_NUMBER:-}" ]] && return 0

  gh pr comment "$PR_NUMBER" \
    --body "🔎 Preview ready: $1 (expires in ${TTL_HOURS}h)" \
    || true
}

# ================= FRONTEND (S3) =================
deploy_frontend() {
  : "${S3_PREVIEW_BUCKET:?Missing bucket}"
  : "${BUILD_DIR:=out}"

  DEST="s3://$S3_PREVIEW_BUCKET/$PREVIEW_ID/"

  aws s3 sync "$BUILD_DIR" "$DEST" --delete \
    --cache-control "public,max-age=31536000,immutable" \
    --exclude "*.html"

  aws s3 sync "$BUILD_DIR" "$DEST" --delete \
    --cache-control "no-cache" --include "*.html"

  URL="https://$S3_PREVIEW_BUCKET.s3.$AWS_REGION.amazonaws.com/$PREVIEW_ID/"
  echo "✅ Frontend preview → $URL"

  comment_pr "$URL"
}

# ================= BACKEND (ECS) =================
deploy_backend() {
  : "${IMAGE_URI:?Missing IMAGE_URI}"
  : "${ECS_CLUSTER:?Missing ECS_CLUSTER}"
  : "${SUBNETS:?Missing SUBNETS}"
  : "${SECURITY_GROUPS:?Missing SECURITY_GROUPS}"

  SERVICE="preview-$PREVIEW_ID"

  echo "🐳 Creating/Updating ECS service: $SERVICE"

  aws ecs create-service \
    --cluster "$ECS_CLUSTER" \
    --service-name "$SERVICE" \
    --task-definition "$IMAGE_URI" \
    --desired-count 1 \
    --launch-type FARGATE \
    --network-configuration \
"awsvpcConfiguration={subnets=[$SUBNETS],securityGroups=[$SECURITY_GROUPS],assignPublicIp=ENABLED}" \
    --tags "key=ttl,value=$(expire_tag)" \
    >/dev/null 2>&1 || \
  aws ecs update-service \
    --cluster "$ECS_CLUSTER" \
    --service "$SERVICE" \
    --task-definition "$IMAGE_URI" >/dev/null

  echo "⏳ Waiting for ECS stability..."
  aws ecs wait services-stable --cluster "$ECS_CLUSTER" --services "$SERVICE"

  echo "✅ ECS preview ready: $SERVICE"
}

# ================= MICROSERVICE (EKS) =================
deploy_microservice() {
  : "${IMAGE_URI:?Missing IMAGE_URI}"

  NS="preview-$PREVIEW_ID"

  kubectl create ns "$NS" 2>/dev/null || true

  kubectl apply -n "$NS" -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app
  labels: { ttl: "$(expire_tag)" }
spec:
  replicas: 1
  selector: { matchLabels: { app: app } }
  template:
    metadata: { labels: { app: app } }
    spec:
      containers:
        - name: app
          image: $IMAGE_URI
          ports: [{ containerPort: 3000 }]
EOF

  kubectl rollout status deployment/app -n "$NS" --timeout=180s
  echo "✅ K8s preview namespace ready: $NS"
}

# ================= ROUTER =================
case "$APP_TYPE" in
  frontend) deploy_frontend ;;
  backend) deploy_backend ;;
  microservice) deploy_microservice ;;
  *) echo "❌ Unknown APP_TYPE=$APP_TYPE"; exit 1 ;;
esac

echo "🎉 Preview deployment complete"
