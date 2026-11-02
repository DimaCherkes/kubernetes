#!/usr/bin/env bash
# ==============================================================================
# Tier 2: Boundary Tests — Invalid Inputs & Blank Title Validation
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier2-boundary/test-invalid-inputs.sh
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

print_tier_header "Tier 2: Boundary" "Input Validation & Blank Title Handling"
log_info "Target Host: ${TARGET_HOST}"

# Helper to create a valid baseline task for PUT boundary tests
SEED_ID=""
cleanup() {
    if [ -n "$SEED_ID" ]; then
        http_delete "/api/tasks/${SEED_ID}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# 1. POST with empty string title
log_info "Testing POST with empty string title..."
http_post "/api/tasks" '{"title":"","description":"Valid description"}'
assert_status_code "400" "B1.1: POST with empty title returns HTTP 400 Bad Request"

# 2. POST with whitespace-only title
log_info "Testing POST with whitespace-only title..."
http_post "/api/tasks" '{"title":"   \t   \n   ","description":"Valid description"}'
assert_status_code "400" "B1.2: POST with whitespace-only title returns HTTP 400 Bad Request"

# 3. POST with missing title property
log_info "Testing POST with missing title property..."
http_post "/api/tasks" '{"description":"Missing title field"}'
assert_status_code "400" "B1.3: POST with missing title property returns HTTP 400 Bad Request"

# 4. POST with null title
log_info "Testing POST with null title..."
http_post "/api/tasks" '{"title":null,"description":"Valid description"}'
assert_status_code "400" "B1.4: POST with null title returns HTTP 400 Bad Request"

# Seed a baseline task for PUT tests
http_post "/api/tasks" '{"title":"Seed for PUT validation","description":"Initial state"}'
if [ "$RESPONSE_CODE" = "201" ]; then
    SEED_ID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
    log_info "Created seed task with ID: $SEED_ID"
fi

if [ -n "$SEED_ID" ]; then
    # 5. PUT with empty string title
    log_info "Testing PUT with empty string title..."
    http_put "/api/tasks/${SEED_ID}" '{"title":"","description":"Updated desc","completed":false}'
    assert_status_code "400" "B1.5: PUT with empty title returns HTTP 400 Bad Request"

    # 6. PUT with whitespace-only title
    log_info "Testing PUT with whitespace-only title..."
    http_put "/api/tasks/${SEED_ID}" '{"title":"    ","description":"Updated desc","completed":false}'
    assert_status_code "400" "B1.6: PUT with whitespace title returns HTTP 400 Bad Request"

    # 7. PUT with null title
    log_info "Testing PUT with null title..."
    http_put "/api/tasks/${SEED_ID}" '{"title":null,"description":"Updated desc","completed":false}'
    assert_status_code "400" "B1.7: PUT with null title returns HTTP 400 Bad Request"
else
    log_skip "B1.5: PUT with empty title" "Could not seed prerequisite task"
    log_skip "B1.6: PUT with whitespace title" "Could not seed prerequisite task"
    log_skip "B1.7: PUT with null title" "Could not seed prerequisite task"
fi

print_summary "Tier 2: Invalid Inputs Test Results"
