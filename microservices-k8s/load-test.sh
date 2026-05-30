#!/bin/bash
#
# load-test.sh — run k6 load tests as Kubernetes Jobs against the
# ecommerce app deployed by helm-cnpg-vault-deploy.sh.
#
# Usage:
#   ./load-test.sh smoke      # Stage 1: smoke test
#   ./load-test.sh clean      # delete all k6 jobs/configmaps
#
# More stages get added as we build them. Each stage is fully independent.

set -e

NAMESPACE="ecommerce"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
K6_DIR="${SCRIPT_DIR}/load-tests/k6"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()    { echo -e "${YELLOW}INFO:${NC} $1"; }
ok()      { echo -e "${GREEN}✓${NC} $1"; }
err()     { echo -e "${RED}✗ ERROR:${NC} $1" >&2; exit 1; }
header()  {
  echo -e "\n${BLUE}===========================================================${NC}"
  echo -e "${GREEN}$1${NC}"
  echo -e "${BLUE}===========================================================${NC}"
}

# ---- Preflight ----
preflight() {
  command -v kubectl >/dev/null 2>&1 || err "kubectl not found"
  kubectl get ns "${NAMESPACE}" >/dev/null 2>&1 \
    || err "namespace '${NAMESPACE}' not found — did you run helm-cnpg-vault-deploy.sh?"
  kubectl get svc api-gateway -n "${NAMESPACE}" >/dev/null 2>&1 \
    || err "api-gateway service not found in '${NAMESPACE}'"
}

# ---- Stage runner ----
# Takes:
#   $1 stage name (e.g. "smoke")
#   $2 entrypoint script path relative to K6_DIR (e.g. "smoke.js"
#      or "scenarios/browse-products.js"). Its basename is the
#      ConfigMap key the k6 Job runs.
#   $3 job name
#   $4+ optional extra file specs as "key=relpath" pairs (e.g.
#      "auth.lib.js=lib/auth.js"). Used when the scenario imports
#      from another local file — that file needs to be in the same
#      ConfigMap so it can be mounted alongside the script.
run_stage() {
  local stage="$1"
  local script_rel="$2"
  local job_name="$3"
  shift 3
  local extras=("$@")  # remaining args are "key=relpath" pairs

  local manifest="${K6_DIR}/k8s/${stage}-job.yaml"
  local script_path="${K6_DIR}/${script_rel}"
  local script_basename
  script_basename="$(basename "${script_rel}")"
  local cm_name="k6-${stage}-script"

  [ -f "${manifest}" ]    || err "manifest not found: ${manifest}"
  [ -f "${script_path}" ] || err "script not found: ${script_path}"

  header "Running Stage: ${stage}"

  # Clean up any previous run so we don't get "AlreadyExists" errors.
  info "Cleaning up previous run (if any)..."
  kubectl delete job "${job_name}" -n "${NAMESPACE}" --ignore-not-found >/dev/null
  kubectl delete configmap "${cm_name}" -n "${NAMESPACE}" --ignore-not-found >/dev/null

  # Build the kubectl create configmap args:
  #   --from-file=auth.js=load-tests/k6/scenarios/auth.js
  #   --from-file=auth.lib.js=load-tests/k6/lib/auth.js
  local from_file_args=(--from-file="${script_basename}=${script_path}")
  for extra in "${extras[@]}"; do
    # extra looks like "auth.lib.js=lib/auth.js"
    local key="${extra%%=*}"
    local rel="${extra#*=}"
    local abs="${K6_DIR}/${rel}"
    [ -f "${abs}" ] || err "extra file not found: ${abs}"
    from_file_args+=(--from-file="${key}=${abs}")
  done

  info "Creating ConfigMap '${cm_name}' (${#from_file_args[@]} file(s))..."
  kubectl create configmap "${cm_name}" \
    "${from_file_args[@]}" \
    -n "${NAMESPACE}" >/dev/null
  ok "ConfigMap created"

  # Apply the Job (and the placeholder ConfigMap definition — but our
  # `kubectl create configmap` above will have already created the real
  # one with the right content; the apply will just no-op or update it).
  # To avoid overwriting our content, we extract and apply only the Job.
  info "Applying Job manifest..."
  # Use yq if available, otherwise awk to extract just the Job document.
  awk '/^---/{p++} p>=2 || /^kind: Job/{flag=1} flag' "${manifest}" \
    | kubectl apply -n "${NAMESPACE}" -f - >/dev/null
  ok "Job '${job_name}' created"

  # Stream logs as the job runs. kubectl logs -f waits for the pod to
  # start, then follows stdout until the container exits.
  info "Waiting for pod to start..."
  kubectl wait --for=condition=PodScheduled \
    pod -l job-name="${job_name}" -n "${NAMESPACE}" --timeout=60s >/dev/null 2>&1 || true

  # Small pause so the container actually starts before we attach.
  sleep 2

  info "Streaming k6 output:"
  echo ""
  kubectl logs -f "job/${job_name}" -n "${NAMESPACE}" || true
  echo ""

  # Read final job status.
  local succeeded
  succeeded=$(kubectl get job "${job_name}" -n "${NAMESPACE}" -o jsonpath='{.status.succeeded}' 2>/dev/null || echo "")
  local failed
  failed=$(kubectl get job "${job_name}" -n "${NAMESPACE}" -o jsonpath='{.status.failed}' 2>/dev/null || echo "")

  if [ "${succeeded}" = "1" ]; then
    ok "Stage '${stage}' PASSED (all k6 thresholds met)"
  elif [ "${failed}" = "1" ]; then
    err "Stage '${stage}' FAILED (k6 thresholds breached or runtime error — see output above)"
  else
    info "Job status unclear; check: kubectl describe job/${job_name} -n ${NAMESPACE}"
  fi
}

# ---- Cleanup ----
clean() {
  header "Cleaning up k6 jobs and ConfigMaps"
  kubectl delete job,configmap -l app=k6 -n "${NAMESPACE}" --ignore-not-found
  ok "Cleaned"
}

# ---- Dispatch ----
case "${1:-}" in
  smoke)
    preflight
    run_stage "smoke" "smoke.js" "k6-smoke"
    ;;
  browse)
    preflight
    run_stage "browse" "scenarios/browse-products.js" "k6-browse"
    ;;
  auth)
    preflight
    run_stage "auth" "scenarios/auth.js" "k6-auth" \
      "auth.lib.js=lib/auth.js"
    ;;
  checkout)
    preflight
    run_stage "checkout" "scenarios/checkout.js" "k6-checkout" \
      "auth.lib.js=lib/auth.js"
    ;;
  clean)
    clean
    ;;
  ""|-h|--help)
    cat <<EOF
Usage: $0 <stage>

Stages:
  smoke    Stage 1: 1 VU x 30s hitting /health. Sanity check.
  browse   Stage 2: 5 VUs x 1min browsing products (list + detail). Real DB load.
  auth     Stage 3: 5 VUs x 1min — login in setup(), hit /profile with JWTs.
  checkout Stage 4: 5 VUs x 2min — full journey: add-to-cart → get cart →
           create order → create payment. Mixed cross-service load.
  clean    Remove all k6 jobs and ConfigMaps from the ${NAMESPACE} namespace.

More stages will be added as you progress.
EOF
    ;;
  *)
    err "Unknown stage: '$1'. Run '$0 --help' for options."
    ;;
esac
