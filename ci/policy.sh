#!/usr/bin/env bash
set -Eeuo pipefail

SERVICES_DIR="${SERVICES_DIR:-services}"
CI_BUILD_ID="${CI_BUILD_ID:-${GITHUB_RUN_ID:-${BUILD_NUMBER:-unknownbuild}}}"
SERVICE="${1:-}"
SERVICE_DIR="${SERVICES_DIR}/${SERVICE}"

log() {
  local scope="${SERVICE:-platform}"
  echo "[POLICY/$scope/$CI_BUILD_ID] $*"
}

warn() {
  local scope="${SERVICE:-platform}"
  echo "[POLICY/$scope/$CI_BUILD_ID] WARN: $*" >&2
}

fail() {
  local scope="${SERVICE:-platform}"
  echo "[POLICY/$scope/$CI_BUILD_ID] ERROR: $*" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "$2"
}

require_dir() {
  [[ -d "$1" ]] || fail "$2"
}

if [[ -n "${CI_SERVICE_LIST:-}" && -z "$SERVICE" ]]; then
  IFS=',' read -ra services <<< "$CI_SERVICE_LIST"
  log "Matrix mode: validating ${#services[@]} services"

  for svc in "${services[@]}"; do
    svc="$(echo "$svc" | xargs)"
    [[ -n "$svc" ]] || continue
    "${BASH_SOURCE[0]}" "$svc"
  done

  exit 0
fi

if [[ -z "$SERVICE" ]]; then
  log "Validating platform policy"
  require_dir "$SERVICES_DIR" "Services directory missing: $SERVICES_DIR"
  require_dir "ci" "CI directory missing"
  require_dir "deploy" "Deploy directory missing"
  log "Platform policy checks passed"
  exit 0
fi

log "Validating service: $SERVICE"

require_dir "$SERVICE_DIR" "Service directory missing: $SERVICE_DIR"
require_file "$SERVICE_DIR/service.yml" "service.yml required"
require_file "$SERVICE_DIR/Dockerfile" "Dockerfile required"
require_dir "$SERVICE_DIR/src" "src directory required"

if [[ -f "$SERVICE_DIR/package.json" ]]; then
  grep -q '"scripts"' "$SERVICE_DIR/package.json" || warn "package.json missing scripts"
fi

if [[ -f "$SERVICE_DIR/requirements.txt" || \
      -f "$SERVICE_DIR/Pipfile" || \
      -f "$SERVICE_DIR/pyproject.toml" ]]; then
  log "Python service detected"
fi

shopt -s nullglob dotglob
files=("$SERVICE_DIR/src"/*)
(( ${#files[@]} )) || fail "src directory empty: $SERVICE_DIR/src"
shopt -u nullglob dotglob

grep -Eq '^[[:space:]]*FROM[[:space:]]' "$SERVICE_DIR/Dockerfile" || \
  fail "Dockerfile missing FROM instruction"

if command -v yq >/dev/null 2>&1; then
  yq e '.' "$SERVICE_DIR/service.yml" >/dev/null 2>&1 || \
    fail "Invalid YAML in service.yml"
else
  warn "yq unavailable, skipping YAML validation"
fi

[[ -f "$SERVICE_DIR/.dockerignore" ]] || warn ".dockerignore recommended"

log "$SERVICE passed all policy checks"
