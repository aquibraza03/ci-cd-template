#!/usr/bin/env bash
set -euo pipefail

# ================= CONFIG =================
APP_PATH="${1:-.}"
SEVERITY="${SEVERITY:-CRITICAL,HIGH}"
FAIL_ON_SEVERITY="${FAIL_ON_SEVERITY:-false}"
OUTPUT_DIR="${OUTPUT_DIR:-security-reports}"

mkdir -p "$OUTPUT_DIR"
cd "$APP_PATH"

echo "🔐 Running Enterprise Security Scans"
echo "Path: $APP_PATH"
echo "Severity threshold: $SEVERITY"
echo "Fail on severity: $FAIL_ON_SEVERITY"
echo "Reports dir: $OUTPUT_DIR"

EXIT_CODE=0

# ================= SCA + SECRETS + IaC → TRIVY =================
if command -v trivy >/dev/null 2>&1; then
  echo "📦 Trivy scan (SCA + Secrets + Config)"

  trivy fs . \
    --scanners vuln,secret,config \
    --severity "$SEVERITY" \
    --format sarif \
    --output "$OUTPUT_DIR/trivy.sarif" \
    --exit-code 1 || EXIT_CODE=$?
else
  echo "⚠️ Trivy not installed — skipping"
fi


# ================= SCA (DEEP) → SNYK =================
if [[ -n "${SNYK_TOKEN:-}" ]]; then
  echo "📦 Snyk dependency scan"

  snyk test --all-projects \
    --severity-threshold=high \
    --sarif-file-output="$OUTPUT_DIR/snyk.sarif" \
    || EXIT_CODE=$?
else
  echo "ℹ️ SNYK_TOKEN not set — skipping Snyk"
fi


# ================= SAST → SEMGREP =================
if command -v semgrep >/dev/null 2>&1; then
  echo "🔍 Semgrep SAST scan"

  semgrep ci \
    --config=auto \
    --sarif \
    --output="$OUTPUT_DIR/semgrep.sarif" \
    || EXIT_CODE=$?
else
  echo "⚠️ Semgrep not installed — skipping"
fi


# ================= IaC (TERRAFORM/K8S) → CHECKOV =================
if command -v checkov >/dev/null 2>&1; then
  echo "🏗️ Checkov IaC scan"

  checkov -d . \
    --framework terraform,kubernetes,dockerfile \
    --output sarif \
    --output-file-path "$OUTPUT_DIR/checkov.sarif" \
    || EXIT_CODE=$?
else
  echo "⚠️ Checkov not installed — skipping"
fi


# ================= ENFORCEMENT GATE =================
if [[ "$FAIL_ON_SEVERITY" == "true" && "$EXIT_CODE" -ne 0 ]]; then
  echo "❌ Security policy violated (severity ≥ $SEVERITY)"
  exit "$EXIT_CODE"
fi


# ================= RESULT =================
echo "✅ Security scans completed"
echo "📁 Generated reports:"
ls -la "$OUTPUT_DIR" || true
