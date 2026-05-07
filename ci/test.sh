#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

TARGET="${1:-app-examples/backend}"
COVERAGE="${COVERAGE:-false}"

if [[ -d "$ROOT_DIR/services/$TARGET" ]]; then
  APP_PATH="$ROOT_DIR/services/$TARGET"
elif [[ -d "$ROOT_DIR/$TARGET" ]]; then
  APP_PATH="$ROOT_DIR/$TARGET"
else
  echo "Test target not found: $TARGET"
  echo "Use a service name from services/ or an app path such as app-examples/backend."
  exit 1
fi

echo "Testing target: $TARGET"
echo "Path: $APP_PATH"

cd "$APP_PATH"

if [[ -f "package.json" ]]; then
  echo "Running Node tests"
  npm ci --no-audit --no-fund
  npm run lint --if-present
  if [[ "$COVERAGE" == "true" ]]; then
    npm test -- --coverage
  else
    npm test
  fi
elif compgen -G "src/*.java" >/dev/null; then
  echo "Running Java compile/tests"
  command -v javac >/dev/null 2>&1 || {
    echo "javac is required for Java services"
    exit 1
  }
  mkdir -p build/classes
  mapfile -t sources < <(find src -name "*.java" -print)
  javac -d build/classes "${sources[@]}"
  mapfile -t tests < <(find src -name "*Test.java" -print)
  for test_file in "${tests[@]}"; do
    test_class="$(basename "$test_file" .java)"
    java -cp build/classes "$test_class"
  done
elif compgen -G "src/*test*.py" >/dev/null || compgen -G "src/test_*.py" >/dev/null; then
  echo "Running Python tests"
  python -m unittest discover -s src -p "*test*.py"
elif [[ -f "requirements.txt" || -f "pyproject.toml" ]]; then
  echo "Running Python syntax checks"
  python -m compileall -q .
elif [[ -f "go.mod" ]]; then
  echo "Running Go tests"
  go test ./...
else
  echo "No supported test target detected; running source syntax smoke where possible"
  if [[ -d src ]]; then
    find src -type f -name "*.py" -print0 | xargs -0 -r python -m py_compile
  fi
fi

echo "Test stage completed for $TARGET"
