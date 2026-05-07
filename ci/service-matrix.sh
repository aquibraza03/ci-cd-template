#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SERVICES_DIR="${SERVICES_DIR:-services}"

log() {
  echo "[SERVICE-MATRIX] $*" >&2
}

service_enabled() {
  local service_file="$1"

  if command -v yq >/dev/null 2>&1; then
    enabled="$(yq e '.ci.enabled' "$service_file" 2>/dev/null || echo "null")"
    [[ "$enabled" != "false" ]]
    return
  fi

  ! grep -Eq '^[[:space:]]*enabled:[[:space:]]*false[[:space:]]*$' "$service_file"
}

log "Generating service matrix"

SERVICES=()

for service in "$SERVICES_DIR"/*/; do
  if [[ -f "$service/service.yml" && -r "$service/service.yml" ]]; then
    name=$(basename "$service")
    if service_enabled "$service/service.yml"; then
      log "Found service: $name"
      SERVICES+=("$name")
    else
      log "Skipping disabled service: $name"
    fi
  fi
done

if [[ ${#SERVICES[@]} -eq 0 ]]; then
  log "No services found"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "services=[]" >> "$GITHUB_OUTPUT"
  fi
  echo "[]"
  exit 0
fi

JSON_SERVICES=()
for svc in "${SERVICES[@]}"; do
  JSON_SERVICES+=("\"$svc\"")
done

MATRIX=$(printf ",%s" "${JSON_SERVICES[@]}")
MATRIX="[${MATRIX:1}]"

log "Generated matrix: $MATRIX"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "services=$MATRIX" >> "$GITHUB_OUTPUT"
fi

echo "$MATRIX"
