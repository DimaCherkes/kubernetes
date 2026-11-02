#!/usr/bin/env bash
# ==============================================================================
# Tier 1: Feature Tests — Static Frontend Single Page Application & Health Probe
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier1-feature/test-frontend.sh
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

print_tier_header "Tier 1: Feature" "Frontend Single Page Application Verification"
log_info "Target Host: ${TARGET_HOST}"

# 1. Root / endpoint HTML check
log_info "Testing Frontend root endpoint (GET /)..."
http_get "/"
assert_status_code "200" "F6.1: GET / returns HTTP 200 OK"
assert_header_contains "Content-Type" "text/html" "F6.2: GET / returns text/html Content-Type"

# 2. Key DOM structure and elements
log_info "Verifying required DOM elements and markup..."
assert_contains "$RESPONSE_BODY" "<!DOCTYPE html>" "F6.3: Root page includes HTML5 DOCTYPE"
assert_contains "$RESPONSE_BODY" "<form" "F6.4: Root page contains task creation form element"
assert_contains "$RESPONSE_BODY" "<input" "F6.5: Root page contains task input fields"
assert_contains "$RESPONSE_BODY" "<button" "F6.6: Root page contains interactive button elements"

# 3. Asset linkage check
log_info "Verifying static asset linkage in index.html..."
assert_contains "$RESPONSE_BODY" "styles.css" "F6.7: HTML references stylesheet styles.css"
assert_contains "$RESPONSE_BODY" "app.js" "F6.8: HTML references JavaScript bundle app.js"

# 4. Direct asset fetch checks
log_info "Testing direct static asset accessibility..."
http_get "/styles.css"
assert_status_code "200" "F6.9: GET /styles.css returns HTTP 200 OK"

http_get "/app.js"
assert_status_code "200" "F6.10: GET /app.js returns HTTP 200 OK"

# 5. Frontend /healthz probe
log_info "Testing Frontend Nginx healthz probe (GET /healthz)..."
http_get "/healthz"
assert_status_code "200" "F6.11: GET /healthz probe returns HTTP 200 OK"

print_summary "Tier 1: Frontend Test Results"
