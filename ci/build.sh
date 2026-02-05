#!/usr/bin/env bash
set -euo pipefail

APP_PATH="${1:-app-examples/backend}"
IMAGE_NAME="${IMAGE_NAME:-app}"
PRIMARY_REGION="${PRIMARY_REGION:-ap-south-1}"
DR_REGION="${DR_REGION:-ap-south-2}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PRIMARY_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${PRIMARY_REGION}.amazonaws.com"
REPO="${ECR_REPOSITORY:-$IMAGE_NAME}"

IMAGE_URI="${PRIMARY_REGISTRY}/${REPO}:${IMAGE_TAG}"

echo "🇮🇳 Building in primary region: $PRIMARY_REGION"

# login
aws ecr get-login-password --region "$PRIMARY_REGION" \
  | docker login --username AWS --password-stdin "$PRIMARY_REGISTRY"

# ensure repo
aws ecr describe-repositories --repository-names "$REPO" \
  --region "$PRIMARY_REGION" >/dev/null 2>&1 || \
aws ecr create-repository --repository-name "$REPO" \
  --image-scanning-configuration scanOnPush=true \
  --region "$PRIMARY_REGION" >/dev/null

# ensure buildx
docker buildx inspect multiarch >/dev/null 2>&1 || \
docker buildx create --name multiarch --use
docker buildx inspect --bootstrap

# build once
docker buildx build \
  --platform "$PLATFORMS" \
  -t "$IMAGE_URI" \
  -t "${PRIMARY_REGISTRY}/${REPO}:latest" \
  --push \
  --provenance=false \
  "$APP_PATH"

echo "✅ Built: $IMAGE_URI"

echo "ℹ️ Replication to $DR_REGION should be handled by ECR Cross-Region Replication"

# GitHub output
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "image=$IMAGE_URI" >> "$GITHUB_OUTPUT"
fi

