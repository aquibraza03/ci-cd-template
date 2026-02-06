#!/usr/bin/env bash
set -euo pipefail

AWS_REGION="${AWS_REGION:-ap-south-1}"
ENVIRONMENT="${ENVIRONMENT:-production}"
TF_DIR="${TF_DIR:-deploy/terraform}"
AUTO_APPROVE="${AUTO_APPROVE:-false}"
WORKSPACE="${WORKSPACE:-$ENVIRONMENT}"
TF_VAR_FILE="${TF_VAR_FILE:-terraform.tfvars}"

echo "🏗️ Enterprise Terraform Provisioning"
echo "Env: $ENVIRONMENT | Workspace: $WORKSPACE | Region: $AWS_REGION"

# ================= STRICT PREREQS =================
command -v aws >/dev/null || { echo "❌ aws CLI missing"; exit 1; }
command -v terraform >/dev/null || { echo "❌ terraform missing"; exit 1; }

aws sts get-caller-identity >/dev/null || { echo "❌ AWS auth failed"; exit 1; }

# ================= BACKEND BUCKET CHECK =================
if ! aws s3api head-bucket --bucket "tf-state-$AWS_REGION" 2>/dev/null; then
  echo "❌ Terraform backend bucket tf-state-$AWS_REGION not found"
  echo "Create it before running provisioning."
  exit 1
fi

cd "$TF_DIR"

# ================= FORMAT & VALIDATE =================
terraform fmt -check -recursive
terraform validate

# ================= INIT =================
terraform init -upgrade \
  -backend-config="bucket=tf-state-$AWS_REGION" \
  -backend-config="key=$ENVIRONMENT/terraform.tfstate" \
  -backend-config="dynamodb_table=tf-locks-$ENVIRONMENT" \
  -backend-config="region=$AWS_REGION"

# ================= WORKSPACE =================
terraform workspace select "$WORKSPACE" 2>/dev/null \
  || terraform workspace new "$WORKSPACE"

# ================= DRIFT DETECTION =================
set +e
terraform plan -detailed-exitcode \
  -var="aws_region=$AWS_REGION" \
  -var="environment=$ENVIRONMENT" \
  -var-file="$TF_VAR_FILE" \
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
  -var-file="$TF_VAR_FILE" \
  -out=tfplan

# ================= GITHUB PLAN SUMMARY =================
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  echo "### Terraform Plan" >> "$GITHUB_STEP_SUMMARY"
  echo '```' >> "$GITHUB_STEP_SUMMARY"
  cat terraform-plan.txt >> "$GITHUB_STEP_SUMMARY"
  echo '```' >> "$GITHUB_STEP_SUMMARY"
fi

# ================= APPLY =================
if [[ "$AUTO_APPROVE" == "true" ]]; then
  terraform apply -auto-approve tfplan
else
  terraform apply tfplan
fi

# ================= OUTPUTS =================
terraform output -json > terraform-outputs.json

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  echo "outputs=$(cat terraform-outputs.json)" >> "$GITHUB_OUTPUT"
fi

echo "✅ Provisioning complete"


