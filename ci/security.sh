#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET="${1:-.}"
TAG="${2:-${IMAGE_TAG:-dev}}"
REGISTRY="${REGISTRY:-${IMAGE_REGISTRY:-}}"
SEVERITY="${SEVERITY:-HIGH,CRITICAL}"
FAIL_ON_SEVERITY="${FAIL_ON_SEVERITY:-true}"
TRIVY_SCANNERS="${TRIVY_SCANNERS:-vuln}"
TRIVY_PKG_TYPES="${TRIVY_PKG_TYPES:-os}"
TRIVY_TIMEOUT="${TRIVY_TIMEOUT:-5m}"
OUTPUT_DIR="${OUTPUT_DIR:-security-reports}"
TRIVY_BIN="${TRIVY_BIN:-}"

if [[ -z "$TRIVY_BIN" ]]; then
  if command -v trivy >/dev/null 2>&1; then
    TRIVY_BIN="$(command -v trivy)"
  elif command -v trivy.exe >/dev/null 2>&1; then
    TRIVY_BIN="$(command -v trivy.exe)"
  elif [[ -x "$ROOT_DIR/bin/trivy" ]]; then
    TRIVY_BIN="$ROOT_DIR/bin/trivy"
  elif [[ -x "$ROOT_DIR/bin/trivy.exe" ]]; then
    TRIVY_BIN="$ROOT_DIR/bin/trivy.exe"
  fi
fi

if [[ -z "$TRIVY_BIN" ]]; then
  echo "Trivy is not installed; skipping security scan"
  exit 0
fi

if [[ -d "$ROOT_DIR/services/$TARGET" ]]; then
  IMAGE="${REGISTRY:+$REGISTRY/}$TARGET:$TAG"
  echo "Running image security scan for $IMAGE"

  if ! docker info >/dev/null 2>&1; then
    echo "Docker daemon is not reachable"
    exit 1
  fi

  if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
    echo "Image $IMAGE not found locally. Run ci/build.sh before security scanning."
    exit 1
  fi

  "$TRIVY_BIN" image \
    --scanners "$TRIVY_SCANNERS" \
    --pkg-types "$TRIVY_PKG_TYPES" \
    --severity "$SEVERITY" \
    --exit-code 1 \
    --no-progress \
    --timeout "$TRIVY_TIMEOUT" \
    "$IMAGE"
else
  if [[ -d "$ROOT_DIR/$TARGET" ]]; then
    SCAN_PATH="$ROOT_DIR/$TARGET"
  elif [[ "$TARGET" == "." ]]; then
    SCAN_PATH="$ROOT_DIR"
  else
    echo "Security target not found: $TARGET"
    echo "Use a service name from services/ or an app path such as app-examples/backend."
    exit 1
  fi

  mkdir -p "$ROOT_DIR/$OUTPUT_DIR"
  echo "Running filesystem security scan for $SCAN_PATH"

  set +e
  "$TRIVY_BIN" fs "$SCAN_PATH" \
    --scanners vuln,secret,config \
    --severity "$SEVERITY" \
    --format sarif \
    --output "$ROOT_DIR/$OUTPUT_DIR/trivy.sarif" \
    --exit-code 1 \
    --no-progress
  scan_status=$?
  set -e

  if [[ "$FAIL_ON_SEVERITY" == "true" && "$scan_status" -ne 0 ]]; then
    exit "$scan_status"
  fi
fi

echo "Security scan completed for $TARGET"
