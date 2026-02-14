#!/usr/bin/env bash
set -Eeuo pipefail

# -------------------------------
# Simple logging helper
# -------------------------------
log() {
  echo -e "\n[$(date -u +'%Y-%m-%dT%H:%M:%SZ')] $*\n"
}

# -------------------------------
# Config (with safe defaults)
# -------------------------------
APP_PATH="${1:-app-examples/backend}"
IMAGE_NAME="${IMAGE_NAME:-app}"
PRIMARY_REGION="${PRIMARY_REGION:-ap-south-1}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short HEAD)}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
KMS_KEY_ALIAS="${KMS_KEY_ALIAS:-alias/aws/ecr}"

# -------------------------------
# AWS info
# -------------------------------
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
PRIMARY_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${PRIMARY_REGION}.amazonaws.com"
REPO="${ECR_REPOSITORY:-$IMAGE_NAME}"
IMAGE_URI="${PRIMARY_REGISTRY}/${REPO}:${IMAGE_TAG}"

log "AWS Account: $ACCOUNT_ID"
log "Building image: $IMAGE_URI"

# -------------------------------
# Retry helper (for AWS/network)
# -------------------------------
retry() {
  local attempts=0
  local max=3
  until "$@"; do
    attempts=$((attempts+1))
    if [[ $attempts -ge $max ]]; then
      log "❌ Failed after $max attempts: $*"
      return 1
    fi
    log "⚠️ Retry $attempts/$max..."
    sleep 3
  done
}

# -------------------------------
# Login to ECR
# -------------------------------
log "Logging into ECR..."
retry aws ecr get-login-password --region "$PRIMARY_REGION" \
  | docker login --username AWS --password-stdin "$PRIMARY_REGISTRY"

# -------------------------------
# Ensure secure ECR repository
# -------------------------------
if ! aws ecr describe-repositories --repository-names "$REPO" --region "$PRIMARY_REGION" >/dev/null 2>&1; then
  log "Creating secure ECR repository..."

  aws ecr create-repository \
    --repository-name "$REPO" \
    --image-tag-mutability IMMUTABLE \
    --image-scanning-configuration scanOnPush=true \
    --encryption-configuration encryptionType=KMS,kmsKey="$KMS_KEY_ALIAS" \
    --region "$PRIMARY_REGION" >/dev/null
fi

# -------------------------------
# Ensure Docker buildx exists
# -------------------------------
log "Preparing Docker buildx..."
docker buildx inspect multiarch >/dev/null 2>&1 || \
  docker buildx create --name multiarch --use
docker buildx inspect --bootstrap >/dev/null

# -------------------------------
# Build & push Docker image
# -------------------------------
log "Building and pushing multi-arch image..."
docker buildx build \
  --platform "$PLATFORMS" \
  -t "$IMAGE_URI" \
  -t "${PRIMARY_REGISTRY}/${REPO}:latest" \
  --push \
  --provenance=false \
  "$APP_PATH"

log "Image pushed successfully: $IMAGE_URI"

# -------------------------------
# Generate SBOM (optional)
# -------------------------------
if command -v syft >/dev/null 2>&1; then
  log "Generating SBOM..."
  syft "$IMAGE_URI" -o cyclonedx-json > sbom.json
else
  log "Syft not installed → skipping SBOM"
fi

# -------------------------------
# Sign image with Cosign (optional)
# -------------------------------
if command -v cosign >/dev/null 2>&1; then
  log "Signing image with Cosign..."
  COSIGN_EXPERIMENTAL=1 cosign sign --yes "$IMAGE_URI"
else
  log "Cosign not installed → skipping signing"
fi

# -------------------------------
# Output for GitHub Actions
# -------------------------------
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "image=$IMAGE_URI" >> "$GITHUB_OUTPUT"
fi

log "🎉 Build completed successfully"

