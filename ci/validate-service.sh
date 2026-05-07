#!/usr/bin/env bash
set -euo pipefail

SERVICE="${1:?Usage: $0 <service-name>}"
SERVICE_PATH="services/$SERVICE"

echo "Validating service: $SERVICE"

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

if [[ ! -d "$SERVICE_PATH" ]]; then
  echo "Service directory not found: $SERVICE_PATH"
  exit 1
fi

for file in service.yml Dockerfile; do
  if [[ ! -f "$SERVICE_PATH/$file" ]]; then
    echo "Missing required file: $file"
    exit 1
  fi
done

if [[ ! -d "$SERVICE_PATH/src" ]]; then
  echo "Missing src/ directory"
  exit 1
fi

if [[ -z "$(find "$SERVICE_PATH/src" -type f 2>/dev/null)" ]]; then
  echo "src/ appears empty; add source files"
  exit 1
fi

get_yaml_value() {
  local file=$1
  shift

  if ! command -v yq >/dev/null 2>&1; then
    return 1
  fi

  for key in "$@"; do
    value=$(yq e "$key // \"\"" "$file" 2>/dev/null || echo "")
    if [[ -n "$value" && "$value" != "null" ]]; then
      echo "$value"
      return 0
    fi
  done

  echo ""
}

fallback_top_value() {
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

fallback_section_value() {
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

SERVICE_FILE="$SERVICE_PATH/service.yml"

if command -v yq >/dev/null 2>&1; then
  NAME=$(get_yaml_value "$SERVICE_FILE" '.name')
  LANGUAGE=$(get_yaml_value "$SERVICE_FILE" '.language' '.runtime')
  PORT=$(get_yaml_value "$SERVICE_FILE" '.docker.port' '.container.port' '.port')
  HEALTH=$(get_yaml_value "$SERVICE_FILE" '.deploy.healthcheck' '.healthcheck.path' '.health.path' '.health')
  READINESS=$(get_yaml_value "$SERVICE_FILE" '.deploy.readiness' '.readiness.path' '.ready.path')
else
  NAME=$(fallback_top_value "$SERVICE_FILE" name)
  LANGUAGE=$(fallback_top_value "$SERVICE_FILE" language)
  PORT=$(fallback_section_value "$SERVICE_FILE" docker port)
  HEALTH=$(fallback_section_value "$SERVICE_FILE" deploy healthcheck)
  READINESS=$(fallback_section_value "$SERVICE_FILE" deploy readiness)
fi

echo "Detected config:"
echo "  name      = $NAME"
echo "  language  = $LANGUAGE"
echo "  port      = $PORT"
echo "  health    = $HEALTH"
echo "  readiness = $READINESS"

[[ -n "$NAME" ]] || { echo "Missing service name"; exit 1; }
[[ -n "$LANGUAGE" ]] || { echo "Missing language/runtime"; exit 1; }
[[ -n "$PORT" ]] || { echo "Missing port"; exit 1; }
[[ -n "$HEALTH" ]] || { echo "Missing healthcheck"; exit 1; }
[[ -n "$READINESS" ]] || { echo "Missing readiness"; exit 1; }

echo "Service validation passed: $SERVICE"
