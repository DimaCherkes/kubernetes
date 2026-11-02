#!/usr/bin/env bash
# ==============================================================================
# Tier 2: Boundary Tests — Malformed Payloads & Media Types (400 / 415)
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier2-boundary/test-malformed-payloads.sh
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

print_tier_header "Tier 2: Boundary" "Malformed Payloads & Content-Type Handling"
log_info "Target Host: ${TARGET_HOST}"

# 1. Broken JSON syntax (unclosed curly brace)
log_info "Testing unclosed JSON syntax..."
http_post "/api/tasks" '{"title": "broken payload"'
assert_status_code "400" "B5.1: Unclosed JSON syntax returns HTTP 400 Bad Request"

# 2. Broken JSON syntax (trailing comma)
log_info "Testing JSON syntax with trailing comma..."
http_post "/api/tasks" '{"title": "trailing comma", "description": "invalid",}'
assert_status_code "400" "B5.2: Trailing comma JSON returns HTTP 400 Bad Request"

# 3. JSON Array instead of Object
log_info "Testing JSON array payload instead of object..."
http_post "/api/tasks" '[{"title": "Array Payload"}]'
assert_status_code "400" "B5.3: Array payload when object expected returns HTTP 400 Bad Request"

# 4. JSON Primitive string instead of Object
log_info "Testing primitive string instead of JSON object..."
http_post "/api/tasks" '"just a plain json string"'
assert_status_code "400" "B5.4: Primitive JSON value returns HTTP 400 Bad Request"

# 5. Empty body with application/json header
log_info "Testing empty body with application/json header..."
http_post "/api/tasks" ""
assert_status_code "400" "B5.5: Empty body with json content-type returns HTTP 400 Bad Request"

# 6. Type mismatch on completed boolean
# First seed a task to update
SEED_ID=""
http_post "/api/tasks" '{"title":"Type mismatch seed","description":"desc"}'
if [ "$RESPONSE_CODE" = "201" ]; then
    SEED_ID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
fi

if [ -n "$SEED_ID" ]; then
    log_info "Testing invalid type for completed boolean on PUT..."
    http_put "/api/tasks/${SEED_ID}" '{"title":"Test","description":"desc","completed":"not-a-bool"}'
    assert_status_code "400" "B5.6: Invalid type for boolean field returns HTTP 400 Bad Request"
    http_delete "/api/tasks/${SEED_ID}" >/dev/null 2>&1 || true
else
    log_skip "B5.6: Invalid boolean type test" "Could not seed prerequisite task"
fi

# 7. Unsupported Media Type (text/plain)
log_info "Testing request with text/plain Content-Type..."
do_request "POST" "/api/tasks" "title=test" "text/plain"
if [ "$RESPONSE_CODE" = "415" ] || [ "$RESPONSE_CODE" = "400" ]; then
    log_pass "B5.7: Unsupported Media Type (text/plain) returns HTTP $RESPONSE_CODE"
else
    log_fail "B5.7: Unsupported Media Type returned $RESPONSE_CODE" "Expected 415 or 400"
fi

print_summary "Tier 2: Malformed Payloads Test Results"
