#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# 🩺 System Doctor — Pre-flight Diagnostics
# Read-only • Fast • CI-Safe • Client-Friendly
# ==========================================================

AWS_REGION="${AWS_REGION:-ap-south-1}"
ENV_FILE="${ENV_FILE:-.env}"

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# ---------------- HELPERS ----------------
pass() { echo "✅ $1"; ((PASS_COUNT++)); }
fail() { echo "❌ $1"; ((FAIL_COUNT++)); }
warn() { echo "⚠️  $1"; ((WARN_COUNT++)); }

section() {
  echo
  echo "▶ $1"
  echo "--------------------------------------------------"
}

check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    pass "$cmd available"
  else
    fail "$cmd missing"
  fi
}

# ---------------- SYSTEM INFO ----------------
section "System information"
uname -a || true

# ---------------- CLI TOOLS ----------------
section "Required CLI tools"

for cmd in git docker aws terraform jq curl; do
  check_cmd "$cmd"
done

# ---------------- DOCKER ----------------
section "Docker status"

if docker info >/dev/null 2>&1; then
  pass "Docker daemon running"
else
  fail "Docker daemon not running"
fi

# ---------------- AWS AUTH ----------------
section "AWS authentication"

if IDENTITY=$(aws sts get-caller-identity 2>/dev/null); then
  ACCOUNT_ID=$(echo "$IDENTITY" | jq -r '.Account')
  ARN=$(echo "$IDENTITY" | jq -r '.Arn')
  pass "AWS authenticated (Account: $ACCOUNT_ID)"
else
  fail "AWS authentication failed"
fi

# ---------------- ENV FILE ----------------
section "Environment configuration"

if [[ -f "$ENV_FILE" ]]; then
  pass "$ENV_FILE exists"
else
  fail "$ENV_FILE missing"
fi

# ---------------- TERRAFORM ----------------
section "Terraform validation"

if [[ -d "deploy/terraform" ]]; then
  if (cd deploy/terraform && terraform validate >/dev/null 2>&1); then
    pass "Terraform configuration valid"
  else
    fail "Terraform validation failed"
  fi
else
  warn "deploy/terraform directory not found"
fi

# ---------------- ECR ACCESS ----------------
section "ECR access"

if [[ -n "${ACCOUNT_ID:-}" ]]; then
  ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

  if aws ecr describe-repositories --region "$AWS_REGION" >/dev/null 2>&1; then
    pass "ECR accessible → $ECR_REGISTRY"
  else
    warn "ECR not accessible or no repositories"
  fi
fi

# ---------------- SUMMARY ----------------
section "Doctor summary"

echo "Passed:  $PASS_COUNT"
echo "Warnings: $WARN_COUNT"
echo "Failed:  $FAIL_COUNT"

if (( FAIL_COUNT > 0 )); then
  echo
  echo "❌ System not ready. Fix failures before deploying."
  exit 1
fi

echo
echo "🎉 System looks healthy. Safe to proceed with CI/CD or deploy."
