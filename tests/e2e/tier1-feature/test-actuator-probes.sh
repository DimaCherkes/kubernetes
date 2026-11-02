#!/usr/bin/env bash
# ==============================================================================
# Tier 1: Feature Tests — Spring Boot Actuator Probes (/health, /liveness, /readiness)
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier1-feature/test-actuator-probes.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "${SCRIPT_DIR}/../lib" && pwd)"
source "${LIB_DIR}/test-helpers.sh"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            TARGET_HOST="$2"
            shift 2
            ;;
        --namespace)
            TARGET_NAMESPACE="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [--host <url>] [--namespace <ns>]"
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            exit 1
            ;;
    esac
done

print_tier_header "Tier 1: Feature" "Spring Boot Actuator Health & Probes Verification"
log_info "Target Host: ${TARGET_HOST}"

# 1. Main Health endpoint
log_info "Testing /actuator/health endpoint..."
http_get "/actuator/health"
assert_status_code "200" "F5.1: GET /actuator/health returns HTTP 200 OK"
assert_json_field ".status" "UP" "F5.2: GET /actuator/health status is UP"

# 2. Kubernetes Liveness Probe
log_info "Testing /actuator/health/liveness probe endpoint..."
http_get "/actuator/health/liveness"
assert_status_code "200" "F5.3: GET /actuator/health/liveness returns HTTP 200 OK"
assert_json_field ".status" "UP" "F5.4: GET /actuator/health/liveness status is UP"

# 3. Kubernetes Readiness Probe
log_info "Testing /actuator/health/readiness probe endpoint..."
http_get "/actuator/health/readiness"
assert_status_code "200" "F5.5: GET /actuator/health/readiness returns HTTP 200 OK"
assert_json_field ".status" "UP" "F5.6: GET /actuator/health/readiness status is UP"

# 4. Content Type Verification
http_get "/actuator/health"
CONTENT_TYPE=$(printf "%s" "$RESPONSE_HEADERS" | grep -i "^content-type:" | tr -d '\r')
if [[ "$CONTENT_TYPE" == *"json"* ]]; then
    log_pass "F5.7: Actuator endpoint returns JSON-compatible Content-Type" "$CONTENT_TYPE"
else
    log_fail "F5.7: Actuator Content-Type unexpected" "$CONTENT_TYPE"
fi

print_summary "Tier 1: Actuator Probes Test Results"
