#!/usr/bin/env bash
set -euo pipefail

# ==========================================================
# ⚡ Enterprise Project Setup — One-Command Bootstrap
# Safe • Idempotent • CI-Compatible • Client-Friendly
# ==========================================================

ENV_FILE=".env"
ENV_EXAMPLE=".env.example"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"

START_TIME=$(date +%s)

# ---------------- HELPERS ----------------
fail() { echo "❌ $1"; exit 1; }
warn() { echo "⚠️  $1"; }
ok()   { echo "✅ $1"; }

require() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required tool: $1"
}

section() {
  echo
  echo "▶ $1"
  echo "--------------------------------------------------"
}

# ---------------- SYSTEM INFO ----------------
section "System information"
uname -a || true

# ---------------- CORE DEPENDENCIES ----------------
section "Checking required CLI tools"

for cmd in git docker aws terraform; do
  require "$cmd"
done

ok "Core CLI tools detected"

# ---------------- OPTIONAL RUNTIMES ----------------
section "Checking optional runtimes"

for opt in node npm python3; do
  if command -v "$opt" >/dev/null 2>&1; then
    ok "$opt detected"
  else
    warn "$opt not found (may be optional)"
  fi
done

# ---------------- DOCKER STATUS ----------------
section "Validating Docker daemon"

docker info >/dev/null 2>&1 \
  || fail "Docker is not running. Start Docker and rerun setup."

ok "Docker daemon running"

# ---------------- AWS AUTH ----------------
section "Validating AWS authentication"

aws sts get-caller-identity >/dev/null 2>&1 \
  || fail "AWS authentication failed. Run: aws configure or SSO login."

ok "AWS credentials valid"

# ---------------- ENV FILE SETUP ----------------
section "Preparing environment configuration"

if [[ -f "$ENV_FILE" ]]; then
  ok ".env already exists (not overwritten)"
elif [[ -f "$ENV_EXAMPLE" ]]; then
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  ok "Created .env from .env.example"
  warn "Fill required secrets inside .env before deploying."
else
  warn "No .env.example found — skipping env setup"
fi

# ---------------- NODE DEPENDENCY INSTALL ----------------
install_node() {
  local dir="$1"

  [[ -f "$dir/package.json" ]] || return 0

  section "Installing Node dependencies → $dir"

  if [[ "$NON_INTERACTIVE" == "true" ]]; then
    (cd "$dir" && npm ci --silent)
  else
    (cd "$dir" && npm ci)
  fi

  ok "Dependencies installed in $dir"
}

install_node "app-examples/backend"
install_node "app-examples/frontend"

# ---------------- TERRAFORM VALIDATION ----------------
section "Validating Terraform configuration"

if [[ -d "deploy/terraform" ]]; then
  (
    cd deploy/terraform
    terraform fmt -check -recursive >/dev/null
    terraform validate >/dev/null
  ) || fail "Terraform configuration invalid"

  ok "Terraform configuration valid"
else
  warn "deploy/terraform directory not found — skipping"
fi

# ---------------- FINAL SUMMARY ----------------
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

section "Setup complete"

cat <<EOF
🎉 Environment ready in ${DURATION}s.

Next steps:
  1. Edit .env with real secrets
  2. Run tests:        bash ci/test.sh
  3. Provision infra:  bash deploy/provision.sh
  4. Deploy preview:   bash ci/deploy-preview.sh
  5. Deploy prod:      bash deploy/deploy.sh

Automation tip:
  NON_INTERACTIVE=true bash scripts/setup.sh
  → recommended for CI or scripted environments
EOF

echo
echo "🚀 Happy building."

