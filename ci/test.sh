#!/usr/bin/env bash
set -euo pipefail

# ================= CONFIG =================
APP_PATH="${1:-app-examples/backend}"
PARALLEL="${PARALLEL:-false}"
COVERAGE="${COVERAGE:-true}"

echo "🧪 Running tests for: $APP_PATH"
echo "Parallel: $PARALLEL | Coverage: $COVERAGE"

cd "$APP_PATH"

# ================= DETECT PROJECT TYPE =================
if [[ -f "package.json" ]]; then
  PROJECT_TYPE="node"
elif [[ -f "requirements.txt" || -f "pyproject.toml" ]]; then
  PROJECT_TYPE="python"
elif [[ -f "go.mod" ]]; then
  PROJECT_TYPE="go"
else
  echo "⚠️ No supported project type detected — skipping tests"
  exit 0
fi

echo "🔎 Detected project type: $PROJECT_TYPE"

# ================= NODE TESTS =================
run_node_tests() {
  echo "📦 Installing Node dependencies"
  npm ci --no-audit --no-fund

  if npm run | grep -q "lint"; then
    echo "🧹 Running linter"
    npm run lint
  fi

  if [[ "$COVERAGE" == "true" ]]; then
    echo "🧪 Running unit tests with coverage"
    npm test -- --coverage
  else
    echo "🧪 Running unit tests"
    npm test
  fi
}

# ================= PYTHON TESTS =================
run_python_tests() {
  echo "🐍 Setting up Python venv"
  python -m venv .venv
  source .venv/bin/activate

  pip install --upgrade pip

  if [[ -f "requirements.txt" ]]; then
    pip install -r requirements.txt
  fi

  pip install pytest pytest-cov flake8

  echo "🧹 Running flake8"
  flake8 . || true

  if [[ "$COVERAGE" == "true" ]]; then
    echo "🧪 Running pytest with coverage"
    pytest --cov --cov-report=term-missing
  else
    pytest
  fi
}

# ================= GO TESTS =================
run_go_tests() {
  echo "🐹 Running go mod tidy"
  go mod tidy

  if [[ "$COVERAGE" == "true" ]]; then
    echo "🧪 Running go tests with coverage"
    go test ./... -coverprofile=coverage.out
  else
    go test ./...
  fi
}

# ================= EXECUTION =================
case "$PROJECT_TYPE" in
  node)
    run_node_tests
    ;;
  python)
    run_python_tests
    ;;
  go)
    run_go_tests
    ;;
esac

# ================= OPTIONAL E2E (Playwright) =================
if [[ -f "playwright.config.ts" || -f "playwright.config.js" ]]; then
  echo "🌐 Playwright detected — running E2E tests"

  if command -v npx >/dev/null 2>&1; then
    npx playwright install --with-deps
    npx playwright test
  fi
fi

echo "✅ Tests completed successfully"
