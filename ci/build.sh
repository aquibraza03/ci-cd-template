name: 🏗 Build Docker Image

on:
  # Automatic CI
  push:
    branches: ["main"]
    paths:
      - "app-examples/**"
      - "ci/**"

  pull_request:
    branches: ["main"]

  # Manual run button in GitHub UI
  workflow_dispatch:

permissions:
  id-token: write     # needed for AWS OIDC
  contents: read

env:
  AWS_REGION: ap-south-1

jobs:
  build:
    name: Build & Sign Image
    runs-on: ubuntu-latest
    timeout-minutes: 30

    steps:
# ---------------------------------------
# Checkout code
# ---------------------------------------
      - name: Checkout repository
        uses: actions/checkout@v4

# ---------------------------------------
# Install SBOM + signing tools
# ---------------------------------------
      - name: Install Syft & Cosign
        run: |
          curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
          curl -sSfL https://raw.githubusercontent.com/sigstore/cosign/main/install.sh | sh -s -- -b /usr/local/bin

# ---------------------------------------
# Configure AWS credentials via OIDC
# ---------------------------------------
      - name: Configure AWS
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: ${{ secrets.AWS_GITHUB_ROLE }}
          aws-region: ${{ env.AWS_REGION }}

# ---------------------------------------
# Run shared enterprise build script
# ---------------------------------------
      - name: Run enterprise build
        id: build
        run: bash ci/build.sh

# ---------------------------------------
# Upload SBOM if generated
# ---------------------------------------
      - name: Upload SBOM artifact
        if: hashFiles('sbom.json') != ''
        uses: actions/upload-artifact@v4
        with:
          name: sbom
          path: sbom.json

# ---------------------------------------
# Print built image (for logs/debugging)
# ---------------------------------------
      - name: Show built image
        run: echo "Built image → ${{ steps.build.outputs.image }}"
