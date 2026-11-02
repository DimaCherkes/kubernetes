#!/usr/bin/env bash
# ==============================================================================
# Tier 2: Boundary Tests — Non-Existent and Invalid Entity IDs (404 / 400)
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier2-boundary/test-nonexistent-entities.sh
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

print_tier_header "Tier 2: Boundary" "Non-Existent and Invalid Entity ID Handling"
log_info "Target Host: ${TARGET_HOST}"

DUMMY_BODY='{"title":"Phantom Task","description":"Should never be persisted","completed":false}'

# 1. Very large positive non-existent ID
log_info "Testing operations on large non-existent ID (99999999)..."
http_put "/api/tasks/99999999" "$DUMMY_BODY"
assert_status_code "404" "B4.1: PUT on non-existent ID 99999999 returns HTTP 404 Not Found"

http_delete "/api/tasks/99999999"
assert_status_code "404" "B4.2: DELETE on non-existent ID 99999999 returns HTTP 404 Not Found"

# 2. Zero ID boundary
log_info "Testing operations on ID 0..."
http_put "/api/tasks/0" "$DUMMY_BODY"
assert_status_code "404" "B4.3: PUT on ID 0 returns HTTP 404 Not Found"

http_delete "/api/tasks/0"
assert_status_code "404" "B4.4: DELETE on ID 0 returns HTTP 404 Not Found"

# 3. Negative ID boundary (-1)
log_info "Testing operations on negative ID (-1)..."
http_put "/api/tasks/-1" "$DUMMY_BODY"
if [ "$RESPONSE_CODE" = "404" ] || [ "$RESPONSE_CODE" = "400" ]; then
    log_pass "B4.5: PUT on negative ID (-1) rejected with HTTP $RESPONSE_CODE"
else
    log_fail "B4.5: PUT on negative ID (-1) unexpected status" "Expected 404 or 400, got $RESPONSE_CODE"
fi

http_delete "/api/tasks/-1"
if [ "$RESPONSE_CODE" = "404" ] || [ "$RESPONSE_CODE" = "400" ]; then
    log_pass "B4.6: DELETE on negative ID (-1) rejected with HTTP $RESPONSE_CODE"
else
    log_fail "B4.6: DELETE on negative ID (-1) unexpected status" "Expected 404 or 400, got $RESPONSE_CODE"
fi

# 4. Non-numeric ID string
log_info "Testing operations on non-numeric ID string..."
http_put "/api/tasks/not-a-number" "$DUMMY_BODY"
if [ "$RESPONSE_CODE" = "400" ] || [ "$RESPONSE_CODE" = "404" ]; then
    log_pass "B4.7: PUT on non-numeric ID rejected with HTTP $RESPONSE_CODE"
else
    log_fail "B4.7: PUT on non-numeric ID unexpected status" "Expected 400 or 404, got $RESPONSE_CODE"
fi

http_delete "/api/tasks/not-a-number"
if [ "$RESPONSE_CODE" = "400" ] || [ "$RESPONSE_CODE" = "404" ]; then
    log_pass "B4.8: DELETE on non-numeric ID rejected with HTTP $RESPONSE_CODE"
else
    log_fail "B4.8: DELETE on non-numeric ID unexpected status" "Expected 400 or 404, got $RESPONSE_CODE"
fi

print_summary "Tier 2: Non-Existent Entities Test Results"
