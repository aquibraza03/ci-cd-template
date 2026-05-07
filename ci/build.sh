#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET="${1:-app-examples/backend}"
TAG="${2:-${IMAGE_TAG:-dev}}"
REGISTRY="${REGISTRY:-${IMAGE_REGISTRY:-}}"
PLATFORMS="${PLATFORMS:-linux/amd64}"
PUSH_IMAGE="${PUSH_IMAGE:-false}"

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  echo "$value"
}

yaml_top_value() {
  local file="$1"
  local key="$2"
  awk -F ':' -v key="$key" '
    $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
      sub("^[^:]*:[[:space:]]*", "", $0)
      gsub(/^"|"$/, "", $0)
      print $0
      exit
    }
  ' "$file"
}

yaml_section_value() {
  local file="$1"
  local section="$2"
  local key="$3"
  awk -F ':' -v section="$section" -v key="$key" '
    $0 ~ "^" section ":[[:space:]]*$" { in_section=1; next }
    in_section && $0 ~ "^[^[:space:]]" { in_section=0 }
    in_section && $0 ~ "^[[:space:]]+" key ":[[:space:]]*" {
      sub("^[^:]*:[[:space:]]*", "", $0)
      gsub(/^"|"$/, "", $0)
      print $0
      exit
    }
  ' "$file"
}

if [[ -d "$ROOT_DIR/services/$TARGET" ]]; then
  APP_PATH="$ROOT_DIR/services/$TARGET"
  SERVICE_NAME="$(trim "$(yaml_top_value "$APP_PATH/service.yml" name)")"
  SERVICE_NAME="${SERVICE_NAME:-$TARGET}"
  DOCKERFILE="$(trim "$(yaml_section_value "$APP_PATH/service.yml" build dockerfile)")"
  DOCKERFILE="${DOCKERFILE:-Dockerfile}"
elif [[ -d "$ROOT_DIR/$TARGET" ]]; then
  APP_PATH="$ROOT_DIR/$TARGET"
  SERVICE_NAME="$(basename "$APP_PATH")"
  DOCKERFILE="Dockerfile"
else
  echo "Build target not found: $TARGET"
  echo "Use a service name from services/ or an app path such as app-examples/backend."
  exit 1
fi

if [[ ! -f "$APP_PATH/$DOCKERFILE" ]]; then
  echo "Dockerfile not found: $APP_PATH/$DOCKERFILE"
  exit 1
fi

IMAGE="${REGISTRY:+$REGISTRY/}$SERVICE_NAME:$TAG"
LATEST_IMAGE="${REGISTRY:+$REGISTRY/}$SERVICE_NAME:latest"

echo "Building $IMAGE"
echo "Context: $APP_PATH"
echo "Dockerfile: $DOCKERFILE"

if ! docker info >/dev/null 2>&1; then
  echo "Docker daemon is not reachable"
  exit 1
fi

cd "$APP_PATH"

if docker buildx version >/dev/null 2>&1; then
  BUILD_ARGS=(
    build
    --platform "$PLATFORMS"
    --tag "$IMAGE"
    --tag "$LATEST_IMAGE"
    --file "$DOCKERFILE"
  )

  if [[ "$PUSH_IMAGE" == "true" ]]; then
    BUILD_ARGS+=(--push)
  elif [[ "$PLATFORMS" != *,* ]]; then
    BUILD_ARGS+=(--load)
  else
    echo "Multi-platform local builds cannot use --load. Set PUSH_IMAGE=true or use a single platform."
    exit 1
  fi

  BUILD_ARGS+=(.)
  docker buildx "${BUILD_ARGS[@]}"
else
  docker build \
    --tag "$IMAGE" \
    --tag "$LATEST_IMAGE" \
    --file "$DOCKERFILE" \
    .
fi

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "image=$IMAGE" >> "$GITHUB_OUTPUT"
fi

echo "Build completed for $SERVICE_NAME"
