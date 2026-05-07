#!/usr/bin/env bash
set -Eeuo pipefail

SERVICE="${1:?Usage: $0 <service-name>}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

############################################
# Local override support (developer testing)
############################################

LOCAL_ENV_FILE="$ROOT_DIR/.env.local"

if [[ -f "$LOCAL_ENV_FILE" ]]; then
  echo "🧪 Loading local overrides from $LOCAL_ENV_FILE"
  while IFS='=' read -r key value; do
    [[ -n "$key" ]] || continue
    [[ "$key" =~ ^[[:space:]]*# ]] && continue
    key="$(echo "$key" | xargs)"
    value="$(echo "${value:-}" | xargs)"
    if [[ -z "${!key+x}" ]]; then
      export "$key=$value"
    fi
  done < "$LOCAL_ENV_FILE"
fi

############################################
# Environment driven configuration
############################################

SERVICE_PATH="$ROOT_DIR/services/$SERVICE"
SERVICE_FILE="$SERVICE_PATH/service.yml"

YQ_BIN=""
if command -v yq >/dev/null 2>&1; then
  YQ_BIN="$(command -v yq)"
elif [[ -x "$ROOT_DIR/bin/yq" ]]; then
  YQ_BIN="$ROOT_DIR/bin/yq"
elif [[ -x "$ROOT_DIR/bin/yq.exe" ]]; then
  YQ_BIN="$ROOT_DIR/bin/yq.exe"
fi

get_service_value() {
  local file="$1"
  shift

  if [[ ! -f "$file" ]]; then
    echo ""
    return 0
  fi

  if [[ -n "$YQ_BIN" ]]; then
    for key in "$@"; do
      value=$("$YQ_BIN" -r "$key // \"\"" "$file" 2>/dev/null || echo "")
      if [[ -n "$value" && "$value" != "null" ]]; then
        echo "$value"
        return 0
      fi
    done
  else
    for key in "$@"; do
      value="$(fallback_service_value "$file" "$key")"
      if [[ -n "$value" && "$value" != "null" ]]; then
        echo "$value"
        return 0
      fi
    done
  fi

  echo ""
}

fallback_top_value() {
  local file="$1"
  local key="$2"

  awk -F ':' -v key="$key" '
    $0 ~ "^[[:space:]]*" key ":[[:space:]]*" {
      sub("^[^:]*:[[:space:]]*", "", $0)
      gsub(/^"|"$/, "", $0)
      print $0
      exit
    }
  ' "$file"
}

fallback_section_value() {
  local file="$1"
  local section="$2"
  local key="$3"

  awk -F ':' -v section="$section" -v key="$key" '
    $0 ~ "^" section ":[[:space:]]*$" { in_section=1; next }
    in_section && $0 ~ "^[^[:space:]]" { in_section=0 }
    in_section && $0 ~ "^[[:space:]]+" key ":[[:space:]]*" {
      sub("^[^:]*:[[:space:]]*", "", $0)
      gsub(/^"|"$/, "", $0)
      print $0
      exit
    }
  ' "$file"
}

fallback_probe_value() {
  local file="$1"
  local probe="$2"
  local key="$3"

  awk -F ':' -v probe="$probe" -v key="$key" '
    /^deploy:[[:space:]]*$/ { in_deploy=1; next }
    in_deploy && /^[^[:space:]]/ { in_deploy=0 }
    in_deploy && /^[[:space:]]{2}probes:[[:space:]]*$/ { in_probes=1; next }
    in_probes && /^[[:space:]]{2}[^[:space:]]/ { in_probes=0 }
    in_probes && $0 ~ "^[[:space:]]{4}" probe ":[[:space:]]*$" { in_probe=1; next }
    in_probe && /^[[:space:]]{4}[^[:space:]]/ { in_probe=0 }
    in_probe && $0 ~ "^[[:space:]]{6}" key ":[[:space:]]*" {
      sub("^[^:]*:[[:space:]]*", "", $0)
      gsub(/^"|"$/, "", $0)
      print $0
      exit
    }
  ' "$file"
}

fallback_service_value() {
  local file="$1"
  local key="$2"

  case "$key" in
    .name) fallback_top_value "$file" name ;;
    .docker.port|.container.port) fallback_section_value "$file" docker port ;;
    .port) fallback_top_value "$file" port ;;
    .deploy.servicePort|.service.port) fallback_section_value "$file" deploy servicePort ;;
    .deploy.serviceType|.service.type) fallback_section_value "$file" deploy serviceType ;;
    .deploy.healthcheck|.healthcheck.path|.health.path|.health) fallback_section_value "$file" deploy healthcheck ;;
    .deploy.readiness|.readiness.path|.ready.path) fallback_section_value "$file" deploy readiness ;;
    .deploy.probes.readiness.initialDelaySeconds|.deploy.readinessProbe.initialDelaySeconds) fallback_probe_value "$file" readiness initialDelaySeconds ;;
    .deploy.probes.readiness.periodSeconds|.deploy.readinessProbe.periodSeconds) fallback_probe_value "$file" readiness periodSeconds ;;
    .deploy.probes.readiness.timeoutSeconds|.deploy.readinessProbe.timeoutSeconds) fallback_probe_value "$file" readiness timeoutSeconds ;;
    .deploy.probes.liveness.initialDelaySeconds|.deploy.livenessProbe.initialDelaySeconds) fallback_probe_value "$file" liveness initialDelaySeconds ;;
    .deploy.probes.liveness.periodSeconds|.deploy.livenessProbe.periodSeconds) fallback_probe_value "$file" liveness periodSeconds ;;
    .deploy.probes.liveness.timeoutSeconds|.deploy.livenessProbe.timeoutSeconds) fallback_probe_value "$file" liveness timeoutSeconds ;;
    *) echo "" ;;
  esac
}

CONFIG_SERVICE_NAME="$(get_service_value "$SERVICE_FILE" '.name')"
CONFIG_CONTAINER_PORT="$(get_service_value "$SERVICE_FILE" '.docker.port' '.container.port' '.port')"
CONFIG_SERVICE_PORT="$(get_service_value "$SERVICE_FILE" '.deploy.servicePort' '.service.port')"
CONFIG_SERVICE_TYPE="$(get_service_value "$SERVICE_FILE" '.deploy.serviceType' '.service.type')"
CONFIG_HEALTH_PATH="$(get_service_value "$SERVICE_FILE" '.deploy.healthcheck' '.healthcheck.path' '.health.path' '.health')"
CONFIG_READINESS_PATH="$(get_service_value "$SERVICE_FILE" '.deploy.readiness' '.readiness.path' '.ready.path')"
CONFIG_READINESS_INITIAL_DELAY="$(get_service_value "$SERVICE_FILE" '.deploy.probes.readiness.initialDelaySeconds' '.deploy.readinessProbe.initialDelaySeconds')"
CONFIG_READINESS_PERIOD="$(get_service_value "$SERVICE_FILE" '.deploy.probes.readiness.periodSeconds' '.deploy.readinessProbe.periodSeconds')"
CONFIG_READINESS_TIMEOUT="$(get_service_value "$SERVICE_FILE" '.deploy.probes.readiness.timeoutSeconds' '.deploy.readinessProbe.timeoutSeconds')"
CONFIG_LIVENESS_INITIAL_DELAY="$(get_service_value "$SERVICE_FILE" '.deploy.probes.liveness.initialDelaySeconds' '.deploy.livenessProbe.initialDelaySeconds')"
CONFIG_LIVENESS_PERIOD="$(get_service_value "$SERVICE_FILE" '.deploy.probes.liveness.periodSeconds' '.deploy.livenessProbe.periodSeconds')"
CONFIG_LIVENESS_TIMEOUT="$(get_service_value "$SERVICE_FILE" '.deploy.probes.liveness.timeoutSeconds' '.deploy.livenessProbe.timeoutSeconds')"

SERVICE_NAME="${CONFIG_SERVICE_NAME:-${SERVICE_NAME:-$SERVICE}}"
K8S_NAMESPACE="${K8S_NAMESPACE:-dev}"
IMAGE_REGISTRY="${IMAGE_REGISTRY:?IMAGE_REGISTRY required}"
IMAGE_TAG="${IMAGE_TAG:?IMAGE_TAG required}"

ENVIRONMENT="${ENVIRONMENT:-dev}"
SERVICE_TYPE="${CONFIG_SERVICE_TYPE:-${SERVICE_TYPE:-ClusterIP}}"
SERVICE_PORT="${CONFIG_SERVICE_PORT:-${SERVICE_PORT:-80}}"
CONTAINER_PORT="${CONFIG_CONTAINER_PORT:-${CONTAINER_PORT:-3000}}"
REPLICAS="${REPLICAS:-1}"
HEALTH_PATH="${CONFIG_HEALTH_PATH:-${HEALTH_PATH:-/health}}"
READINESS_PATH="${CONFIG_READINESS_PATH:-${READINESS_PATH:-/ready}}"
READINESS_INITIAL_DELAY_SECONDS="${CONFIG_READINESS_INITIAL_DELAY:-${READINESS_INITIAL_DELAY_SECONDS:-10}}"
READINESS_PERIOD_SECONDS="${CONFIG_READINESS_PERIOD:-${READINESS_PERIOD_SECONDS:-5}}"
READINESS_TIMEOUT_SECONDS="${CONFIG_READINESS_TIMEOUT:-${READINESS_TIMEOUT_SECONDS:-1}}"
LIVENESS_INITIAL_DELAY_SECONDS="${CONFIG_LIVENESS_INITIAL_DELAY:-${LIVENESS_INITIAL_DELAY_SECONDS:-30}}"
LIVENESS_PERIOD_SECONDS="${CONFIG_LIVENESS_PERIOD:-${LIVENESS_PERIOD_SECONDS:-10}}"
LIVENESS_TIMEOUT_SECONDS="${CONFIG_LIVENESS_TIMEOUT:-${LIVENESS_TIMEOUT_SECONDS:-1}}"

CPU_REQUEST="${CPU_REQUEST:-100m}"
MEMORY_REQUEST="${MEMORY_REQUEST:-128Mi}"
CPU_LIMIT="${CPU_LIMIT:-500m}"
MEMORY_LIMIT="${MEMORY_LIMIT:-256Mi}"

ENABLE_HPA="${ENABLE_HPA:-true}"
HPA_MIN_REPLICAS="${HPA_MIN_REPLICAS:-1}"
HPA_MAX_REPLICAS="${HPA_MAX_REPLICAS:-3}"
HPA_CPU_UTILIZATION="${HPA_CPU_UTILIZATION:-80}"

ENABLE_PDB="${ENABLE_PDB:-true}"
PDB_MIN_AVAILABLE="${PDB_MIN_AVAILABLE:-1}"

ENABLE_NETWORK_POLICY="${ENABLE_NETWORK_POLICY:-true}"
RENDER_ONLY="${RENDER_ONLY:-false}"
RENDER_OUTPUT_DIR="${RENDER_OUTPUT_DIR:-}"

# Deployment version (CI or timestamp)
DEPLOY_VERSION="${DEPLOY_VERSION:-$(date +%s)}"

CREATE_NAMESPACE="${CREATE_NAMESPACE:-false}"

############################################
# Logging helper
############################################

log() {
  echo "[K8S-DEPLOY/$SERVICE_NAME] $*"
}

############################################
# Check kubectl connectivity
############################################

check_cluster() {

  if ! command -v kubectl >/dev/null 2>&1; then
    echo "❌ kubectl not installed"
    exit 1
  fi

  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "❌ Kubernetes cluster not reachable"
    exit 1
  fi
}

############################################
# Optional namespace creation
############################################

ensure_namespace() {

  if [[ "$CREATE_NAMESPACE" == "true" ]]; then

    if ! kubectl get namespace "$K8S_NAMESPACE" >/dev/null 2>&1; then
      log "Creating namespace $K8S_NAMESPACE"
      kubectl create namespace "$K8S_NAMESPACE"
    fi

  else
    log "Using namespace $K8S_NAMESPACE (creation disabled)"
  fi
}

############################################
# Render and apply manifests
############################################

deploy_manifests() {

  BASE_DIR="$ROOT_DIR/deploy/k8s/base"
  if [[ -n "$RENDER_OUTPUT_DIR" ]]; then
    RENDER_DIR="$RENDER_OUTPUT_DIR"
  else
    RENDER_DIR="$(mktemp -d)"
  fi

  log "Rendering manifests"

  # Prevent Git Bash/MSYS from converting Kubernetes HTTP paths such as /health
  # into Windows paths when native tools like envsubst are invoked.
  export MSYS2_ENV_CONV_EXCL="${MSYS2_ENV_CONV_EXCL:-*}"

  export SERVICE_NAME
  export IMAGE_REGISTRY
  export IMAGE_TAG
  export K8S_NAMESPACE
  export SERVICE_PORT
  export CONTAINER_PORT
  export REPLICAS
  export DEPLOY_VERSION
  export ENVIRONMENT
  export SERVICE_TYPE
  export HEALTH_PATH
  export READINESS_PATH
  export READINESS_INITIAL_DELAY_SECONDS
  export READINESS_PERIOD_SECONDS
  export READINESS_TIMEOUT_SECONDS
  export LIVENESS_INITIAL_DELAY_SECONDS
  export LIVENESS_PERIOD_SECONDS
  export LIVENESS_TIMEOUT_SECONDS
  export CPU_REQUEST
  export MEMORY_REQUEST
  export CPU_LIMIT
  export MEMORY_LIMIT
  export HPA_MIN_REPLICAS
  export HPA_MAX_REPLICAS
  export HPA_CPU_UTILIZATION
  export PDB_MIN_AVAILABLE

  mkdir -p "$RENDER_DIR/base"

  render_resource() {
    local file="$1"
    local target="$RENDER_DIR/base/$(basename "$file")"

    envsubst < "$file" > "$target"
  }

  render_resource "$BASE_DIR/serviceaccount.yaml"

  # Optional ConfigMap
  if [[ -f "$BASE_DIR/configmap.yaml" ]]; then
    render_resource "$BASE_DIR/configmap.yaml"
  fi

  # Optional Secret
  if [[ -f "$BASE_DIR/secret.yaml" ]]; then
    render_resource "$BASE_DIR/secret.yaml"
  fi

  render_resource "$BASE_DIR/deployment.yaml"
  render_resource "$BASE_DIR/service.yaml"

  if [[ "$ENABLE_HPA" == "true" ]]; then
    render_resource "$BASE_DIR/hpa.yaml"
  fi

  if [[ "$ENABLE_PDB" == "true" ]]; then
    render_resource "$BASE_DIR/pdb.yaml"
  fi

  if [[ "$ENABLE_NETWORK_POLICY" == "true" ]]; then
    render_resource "$BASE_DIR/networkpolicy.yaml"
  fi

  {
    echo "apiVersion: kustomize.config.k8s.io/v1beta1"
    echo "kind: Kustomization"
    echo ""
    echo "resources:"
    find "$RENDER_DIR/base" -maxdepth 1 -type f -name "*.yaml" -print |
      sort |
      sed "s#^$RENDER_DIR/#  - #"
    echo ""
    echo "labels:"
    echo "  - pairs:"
    echo "      app.kubernetes.io/managed-by: kustomize"
    echo "      app.kubernetes.io/part-of: microservice-platform"
    echo "    includeSelectors: false"
    echo "    includeTemplates: true"
    echo ""
    echo "commonAnnotations:"
    echo "  platform.io/deployment-model: kustomize"
    echo "  platform.io/compliance-tier: standard"
  } > "$RENDER_DIR/kustomization.yaml"

  if [[ "$RENDER_ONLY" == "true" ]]; then
    log "Render-only mode enabled. Manifests written to $RENDER_DIR"
    return 0
  fi

  kubectl apply -k "$RENDER_DIR" -n "$K8S_NAMESPACE"

  if [[ -z "$RENDER_OUTPUT_DIR" ]]; then
    rm -rf "$RENDER_DIR"
  fi
}

############################################
# Wait for rollout
############################################

wait_for_rollout() {

  log "Waiting for rollout"

  if ! kubectl rollout status deployment/"$SERVICE_NAME" \
      -n "$K8S_NAMESPACE" \
      --timeout=300s; then

    echo "❌ Deployment failed. Rolling back..."

    kubectl rollout undo deployment/"$SERVICE_NAME" \
      -n "$K8S_NAMESPACE"

    echo "🔁 Rolled back to previous version"

    exit 1
  fi
}

############################################
# Main execution
############################################

main() {

  log "Deploying $SERVICE_NAME"

  if [[ "$RENDER_ONLY" == "true" ]]; then
    deploy_manifests
    return 0
  fi

  check_cluster

  # Optional AWS EKS kubeconfig setup
  if [[ -n "${AWS_REGION:-}" && -n "${K8S_CLUSTER_NAME:-}" ]]; then
    log "Configuring kubeconfig for EKS cluster ${K8S_CLUSTER_NAME}"
    aws eks update-kubeconfig \
      --name "${K8S_CLUSTER_NAME}" \
      --region "${AWS_REGION}"
  fi

  ensure_namespace
  deploy_manifests
  wait_for_rollout

  log "Deployment finished"
}

main "$@"



