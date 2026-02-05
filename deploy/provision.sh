#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
ENVIRONMENT="${ENVIRONMENT:-production}"
TF_DIR="${TF_DIR:-deploy/terraform}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
WORKSPACE="${WORKSPACE:-$ENVIRONMENT}"

echo "🏗️ Enterprise Terraform Provisioning"
echo "Env: $ENVIRONMENT | Workspace: $WORKSPACE | Region: $AWS_REGION"

# ================= STRICT PREREQS =================
command -v aws >/dev/null || { echo "❌ aws CLI missing"; exit 1; }
command -v terraform >/dev/null || { echo "❌ terraform missing"; exit 1; }

# ================= AWS + TF VERSION CHECK =================
aws sts get-caller-identity >/dev/null || { echo "❌ AWS auth failed"; exit 1; }
terraform version | head -1 | grep -q "v1." || { echo "⚠️ Unexpected Terraform version"; }

cd "$TF_DIR"

# ================= FORMAT & VALIDATE =================
echo "🧹 terraform fmt check"
terraform fmt -check -recursive

echo "🔍 terraform validate"
terraform validate

# ================= INIT (REMOTE BACKEND) =================
terraform init -upgrade \
  -backend-config="bucket=tf-state-$AWS_REGION" \
  -backend-config="key=$ENVIRONMENT/terraform.tfstate" \
  -backend-config="dynamodb_table=tf-locks-$ENVIRONMENT" \
  -backend-config="region=$AWS_REGION"

# ================= WORKSPACE =================
terraform workspace select "$WORKSPACE" 2>/dev/null \
  || terraform workspace new "$WORKSPACE"

# ================= DRIFT DETECTION =================
echo "🔍 Drift detection (detailed exit code)"

set +e
terraform plan -detailed-exitcode \
  -var="aws_region=$AWS_REGION" \
  -var="environment=$ENVIRONMENT" \
  > terraform-plan.txt 2>&1
PLAN_EXIT=$?
set -e

if [[ "$PLAN_EXIT" -eq 1 ]]; then
  echo "❌ Terraform plan error"
  exit 1
elif [[ "$PLAN_EXIT" -eq 2 ]]; then
  echo "⚠️ Drift or changes detected"
else
  echo "✅ No drift"
fi

# ================= PLAN FOR APPLY =================
terraform plan \
  -var="aws_region=$AWS_REGION" \
  -var="environment=$ENVIRONMENT" \
  -out=tfplan

# ================= APPLY =================
if [[ "$AUTO_APPROVE" == "true" ]]; then
  echo "🚀 AUTO-APPLY"
  terraform apply -auto-approve tfplan
else
  echo "⏳ Manual approval required"
  terraform apply tfplan
fi

# ================= OUTPUTS =================
terraform output -json > terraform-outputs.json

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "outputs=$(cat terraform-outputs.json)" >> "$GITHUB_OUTPUT"
fi

echo "✅ Provisioning complete"

