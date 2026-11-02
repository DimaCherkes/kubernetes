#!/usr/bin/env bash
# ==============================================================================
# Tier 2: Boundary Tests — Extreme Field Lengths & Boundaries
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier2-boundary/test-extreme-lengths.sh
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

print_tier_header "Tier 2: Boundary" "Extreme Field Lengths & Boundary Values"
log_info "Target Host: ${TARGET_HOST}"

CLEANUP_IDS=()
cleanup() {
    for id in "${CLEANUP_IDS[@]}"; do
        http_delete "/api/tasks/${id}" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

# 1. 1-character title (minimal valid length)
log_info "Testing 1-character title..."
http_post "/api/tasks" '{"title":"X","description":"Minimal title length"}'
assert_status_code "201" "B2.1: Single-character title returns HTTP 201 Created"
TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
[ -n "$TID" ] && CLEANUP_IDS+=("$TID")
assert_json_field ".title" "X" "B2.2: Single-character title is stored accurately"

# 2. 255-character title
log_info "Testing 255-character title..."
TITLE_255=$(python3 -c "print('T' * 255)" 2>/dev/null || printf '%*s' 255 | tr ' ' 'T')
PAYLOAD_255=$(jq -n --arg t "$TITLE_255" '{"title": $t, "description": "255 char title"}')
http_post "/api/tasks" "$PAYLOAD_255"
assert_status_code "201" "B2.3: 255-character title returns HTTP 201 Created"
TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
[ -n "$TID" ] && CLEANUP_IDS+=("$TID")
assert_json_field ".title" "$TITLE_255" "B2.4: 255-character title matches exactly"

# 3. 1000-character description
log_info "Testing 1000-character description..."
DESC_1000=$(python3 -c "print('D' * 1000)" 2>/dev/null || printf '%*s' 1000 | tr ' ' 'D')
PAYLOAD_1000=$(jq -n --arg d "$DESC_1000" '{"title": "1000-char desc test", "description": $d}')
http_post "/api/tasks" "$PAYLOAD_1000"
assert_status_code "201" "B2.5: 1000-character description returns HTTP 201 Created"
TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
[ -n "$TID" ] && CLEANUP_IDS+=("$TID")
assert_json_field ".description" "$DESC_1000" "B2.6: 1000-character description matches exactly"

# 4. 5000-character extreme description
log_info "Testing 5000-character description..."
DESC_5000=$(python3 -c "print('E' * 5000)" 2>/dev/null || printf '%*s' 5000 | tr ' ' 'E')
PAYLOAD_5000=$(jq -n --arg d "$DESC_5000" '{"title": "5000-char desc test", "description": $d}')
http_post "/api/tasks" "$PAYLOAD_5000"
assert_status_code "201" "B2.7: 5000-character description returns HTTP 201 Created"
TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
[ -n "$TID" ] && CLEANUP_IDS+=("$TID")

# 5. Empty description string
log_info "Testing empty description string..."
http_post "/api/tasks" '{"title":"Empty Description Test","description":""}'
assert_status_code "201" "B2.8: Empty string description returns HTTP 201 Created"
TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
[ -n "$TID" ] && CLEANUP_IDS+=("$TID")

# 6. Omitted description field
log_info "Testing omitted description field..."
http_post "/api/tasks" '{"title":"Omitted Description Test"}'
assert_status_code "201" "B2.9: Omitted description field returns HTTP 201 Created"
TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
[ -n "$TID" ] && CLEANUP_IDS+=("$TID")

print_summary "Tier 2: Extreme Lengths Test Results"
