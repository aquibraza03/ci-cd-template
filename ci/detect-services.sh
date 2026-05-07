#!/usr/bin/env bash
set -euo pipefail

SERVICES_DIR="${SERVICES_DIR:-services}"
ALL_SERVICES_ON_NO_CHANGES="${ALL_SERVICES_ON_NO_CHANGES:-true}"

log() {
  echo "[DETECT-SERVICES] $*" >&2
}

has_service_contract() {
  local service="$1"
  [[ -f "$SERVICES_DIR/$service/service.yml" ]]
}

service_enabled() {
  local service="$1"
  local service_file="$SERVICES_DIR/$service/service.yml"

  if command -v yq >/dev/null 2>&1; then
    enabled="$(yq e '.ci.enabled' "$service_file" 2>/dev/null || echo "null")"
    [[ "$enabled" != "false" ]]
    return
  fi

  ! grep -Eq '^[[:space:]]*enabled:[[:space:]]*false[[:space:]]*$' "$service_file"
}

list_all_services() {
  find "$SERVICES_DIR" -mindepth 1 -maxdepth 1 -type d -print |
    while read -r service_path; do
      service="$(basename "$service_path")"
      if has_service_contract "$service" && service_enabled "$service"; then
        echo "$service"
      fi
    done |
    sort -u
}

emit_services() {
  local services=("$@")

  if [[ ${#services[@]} -eq 0 ]]; then
    log "No services selected"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
      echo "services=[]" >> "$GITHUB_OUTPUT"
    fi
    return 0
  fi

  printf '%s\n' "${services[@]}"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    json=$(printf '%s\n' "${services[@]}" | jq -R -s -c 'split("\n")[:-1]')
    echo "services=$json" >> "$GITHUB_OUTPUT"
  fi
}

log "Detecting changed services"

if [[ -n "${SERVICE:-}" ]]; then
  has_service_contract "$SERVICE" || {
    log "Service has no platform contract: $SERVICE"
    exit 1
  }
  service_enabled "$SERVICE" || {
    log "Service disabled by service.yml: $SERVICE"
    emit_services
    exit 0
  }
  emit_services "$SERVICE"
  exit 0
fi

if [[ -n "${CI_SERVICE_LIST:-}" ]]; then
  IFS=',' read -ra requested_services <<< "$CI_SERVICE_LIST"
  selected=()
  for service in "${requested_services[@]}"; do
    service="$(echo "$service" | xargs)"
    [[ -n "$service" ]] || continue
    if has_service_contract "$service" && service_enabled "$service"; then
      selected+=("$service")
    fi
  done
  emit_services "${selected[@]}"
  exit 0
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  log "No git metadata found; selecting all contract-enabled services"
  mapfile -t selected < <(list_all_services)
  emit_services "${selected[@]}"
  exit 0
fi

if git rev-parse HEAD~1 >/dev/null 2>&1; then
  CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD || true)
else
  log "No previous commit found; selecting all contract-enabled services"
  mapfile -t selected < <(list_all_services)
  emit_services "${selected[@]}"
  exit 0
fi

selected=()
for file in $CHANGED_FILES; do
  if [[ "$file" == $SERVICES_DIR/* ]]; then
    service=$(echo "$file" | cut -d'/' -f2)
    if has_service_contract "$service" && service_enabled "$service"; then
      selected+=("$service")
    fi
  fi
done

if [[ ${#selected[@]} -eq 0 && "$ALL_SERVICES_ON_NO_CHANGES" == "true" ]]; then
  log "No changed services found; selecting all contract-enabled services"
  mapfile -t selected < <(list_all_services)
fi

mapfile -t selected < <(printf '%s\n' "${selected[@]}" | sort -u)
emit_services "${selected[@]}"
