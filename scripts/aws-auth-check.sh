#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# 🔐 AWS Authentication & ECR Access Validation
# Fast • Clear • CI-Compatible • Enterprise-Safe
# ==========================================================

AWS_REGION="${AWS_REGION:-ap-south-1}"
ECR_REPOSITORY="${ECR_REPOSITORY:-}"
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

require() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required tool: $1"
}

# ---------------- DEPENDENCY CHECK ----------------
section "Checking required tools"

for cmd in aws docker; do
  require "$cmd"
done

ok "AWS CLI and Docker detected"

# ---------------- AWS AUTH ----------------
section "Validating AWS credentials"

IDENTITY_JSON=$(aws sts get-caller-identity 2>/dev/null) \
  || fail "AWS authentication failed. Run: aws configure or SSO login."

ACCOUNT_ID=$(echo "$IDENTITY_JSON" | jq -r '.Account')
ARN=$(echo "$IDENTITY_JSON" | jq -r '.Arn')

ok "Authenticated to AWS"
echo "   Account: $ACCOUNT_ID"
echo "   ARN:     $ARN"
echo "   Region:  $AWS_REGION"

# ---------------- ECR LOGIN ----------------
section "Validating ECR login"

ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"

aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY" \
  >/dev/null

ok "Docker authenticated to ECR → $ECR_REGISTRY"

# ---------------- ECR REPOSITORY ACCESS ----------------
if [[ -n "$ECR_REPOSITORY" ]]; then
  section "Checking ECR repository access → $ECR_REPOSITORY"

  if aws ecr describe-repositories \
    --repository-names "$ECR_REPOSITORY" \
    --region "$AWS_REGION" >/dev/null 2>&1; then

    ok "Repository exists and is accessible"
  else
    warn "Repository not found or no access"

    if [[ "$NON_INTERACTIVE" == "false" ]]; then
      echo "Attempting to create repository..."

      aws ecr create-repository \
        --repository-name "$ECR_REPOSITORY" \
        --image-scanning-configuration scanOnPush=true \
        --region "$AWS_REGION" >/dev/null

      ok "Repository created successfully"
    else
      fail "Missing ECR repository access in non-interactive mode"
    fi
  fi
else
  warn "ECR_REPOSITORY not provided — skipping repo validation"
fi

# ---------------- SUCCESS ----------------
section "AWS authentication check complete"
ok "IAM + ECR access verified successfully"
