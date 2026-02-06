#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# 🔎 Environment Variable Validation
# Fails fast on missing or empty required secrets
# Safe • Clear • CI-Compatible • Enterprise-Ready
# ==========================================================

ENV_FILE="${ENV_FILE:-.env}"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"

# ---------------- HELPERS ----------------
fail() { echo "❌ $1"; exit 1; }
warn() { echo "⚠️  $1"; }
ok()   { echo "✅ $1"; }

section() {
  echo
  echo "▶ $1"
  echo "--------------------------------------------------"
}

# ---------------- LOAD ENV FILE ----------------
section "Loading environment file"

if [[ ! -f "$ENV_FILE" ]]; then
  fail "$ENV_FILE not found. Copy from .env.example and fill secrets."
fi

# shellcheck disable=SC1090
set -a
source "$ENV_FILE"
set +a

ok "Loaded $ENV_FILE"

# ---------------- REQUIRED VARIABLES ----------------
section "Checking required environment variables"

# Define required variables here (edit per project)
REQUIRED_VARS=(
  AWS_REGION
  ECR_REPOSITORY
  ECS_CLUSTER
  ECS_SERVICE
  HEALTH_URL
  SLACK_WEBHOOK_URL
)

MISSING=()

for VAR in "${REQUIRED_VARS[@]}"; do
  VALUE="${!VAR:-}"

  if [[ -z "$VALUE" ]]; then
    MISSING+=("$VAR")
  fi
done

# ---------------- RESULT ----------------
if (( ${#MISSING[@]} > 0 )); then
  echo "❌ Missing required environment variables:"
  for VAR in "${MISSING[@]}"; do
    echo "   - $VAR"
  done

  echo
  echo "Fix: update $ENV_FILE with real values."

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    exit 1
  else
    fail "Environment validation failed."
  fi
fi

ok "All required environment variables are set"

# ---------------- OPTIONAL WARNINGS ----------------
section "Optional sanity checks"

if [[ "${AWS_REGION:-}" != "ap-south-1" ]]; then
  warn "AWS_REGION is not ap-south-1 (Mumbai). Ensure this is intentional."
fi

# ---------------- GITHUB OUTPUT (optional CI use) ----------------
if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf "env_valid=true\\n"
    printf "env_file=%s\\n" "$ENV_FILE"
  } >> "$GITHUB_OUTPUT"
fi

# ---------------- SUCCESS ----------------
section "Environment validation complete"
ok "Secrets configuration looks good"
