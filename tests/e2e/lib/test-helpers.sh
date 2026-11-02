#!/usr/bin/env bash
# ==============================================================================
# E2E Test Suite Shared Helper Library
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/lib/test-helpers.sh
# ==============================================================================

# ANSI Color Codes
CLR_RESET="\033[0m"
CLR_BOLD="\033[1m"
CLR_GREEN="\033[32m"
CLR_RED="\033[31m"
CLR_YELLOW="\033[33m"
CLR_BLUE="\033[34m"
CLR_CYAN="\033[36m"

# Default configuration
TARGET_HOST="${TARGET_HOST:-http://localhost}"
TARGET_NAMESPACE="${TARGET_NAMESPACE:-full-stack-app}"

# Global Test Counters
TOTAL_COUNT=0
PASSED_COUNT=0
FAILED_COUNT=0
SKIPPED_COUNT=0

# Log functions
log_info() {
    printf "${CLR_BLUE}[INFO]${CLR_RESET} %s\n" "$*"
}

log_pass() {
    PASSED_COUNT=$((PASSED_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    local test_name="$1"
    local details="${2:-}"
    if [ -n "$details" ]; then
        printf "  ${CLR_GREEN}✓ PASS:${CLR_RESET} %s (${CLR_CYAN}%s${CLR_RESET})\n" "$test_name" "$details"
    else
        printf "  ${CLR_GREEN}✓ PASS:${CLR_RESET} %s\n" "$test_name"
    fi
}

log_fail() {
    FAILED_COUNT=$((FAILED_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    local test_name="$1"
    local reason="${2:-Assertion failed}"
    printf "  ${CLR_RED}✗ FAIL:${CLR_RESET} %s\n        ${CLR_RED}Reason: %s${CLR_RESET}\n" "$test_name" "$reason"
}

log_skip() {
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    TOTAL_COUNT=$((TOTAL_COUNT + 1))
    local test_name="$1"
    local reason="${2:-Skipped}"
    printf "  ${CLR_YELLOW}○ SKIP:${CLR_RESET} %s (${CLR_YELLOW}%s${CLR_RESET})\n" "$test_name" "$reason"
}

# Print tier / suite header
print_tier_header() {
    local tier_name="$1"
    local description="$2"
    printf "\n${CLR_BOLD}${CLR_CYAN}======================================================================${CLR_RESET}\n"
    printf "${CLR_BOLD}${CLR_CYAN}  %s: %s${CLR_RESET}\n" "$tier_name" "$description"
    printf "${CLR_BOLD}${CLR_CYAN}======================================================================${CLR_RESET}\n\n"
}

# Summary reporter
print_summary() {
    local suite_title="${1:-Test Suite Summary}"
    printf "\n${CLR_BOLD}======================================================================${CLR_RESET}\n"
    printf "${CLR_BOLD}%s${CLR_RESET}\n" "$suite_title"
    printf "======================================================================\n"
    printf "  Total Tests:   ${CLR_BOLD}%d${CLR_RESET}\n" "$TOTAL_COUNT"
    printf "  Passed:        ${CLR_GREEN}%d${CLR_RESET}\n" "$PASSED_COUNT"
    printf "  Failed:        ${CLR_RED}%d${CLR_RESET}\n" "$FAILED_COUNT"
    if [ "$SKIPPED_COUNT" -gt 0 ]; then
        printf "  Skipped:       ${CLR_YELLOW}%d${CLR_RESET}\n" "$SKIPPED_COUNT"
    fi
    printf "======================================================================\n"

    if [ "$FAILED_COUNT" -gt 0 ]; then
        printf "${CLR_RED}${CLR_BOLD}OVERALL RESULT: FAILED${CLR_RESET}\n\n"
        return 1
    else
        printf "${CLR_GREEN}${CLR_BOLD}OVERALL RESULT: PASSED${CLR_RESET}\n\n"
        return 0
    fi
}

# HTTP Request Dispatcher
# Sets:
#   RESPONSE_CODE    - HTTP status code (e.g. 200, 201, 400, 404, 000 on network failure)
#   RESPONSE_BODY    - Response payload string
#   RESPONSE_HEADERS - Response headers string
do_request() {
    local method="$1"
    local path="$2"
    local data="${3:-}"
    local content_type="${4:-application/json}"

    local url="${TARGET_HOST}${path}"
    local tmp_body
    tmp_body=$(mktemp)
    local tmp_headers
    tmp_headers=$(mktemp)

    local curl_cmd=(curl -s -S -o "$tmp_body" -D "$tmp_headers" -w "%{http_code}" -X "$method" --connect-timeout 10 --max-time 30)

    if [ "$method" = "POST" ] || [ "$method" = "PUT" ]; then
        if [ -n "$content_type" ]; then
            curl_cmd+=(-H "Content-Type: ${content_type}")
        fi
        curl_cmd+=(--data-binary "$data")
    fi

    curl_cmd+=("$url")

    RESPONSE_CODE=$("${curl_cmd[@]}" 2>/dev/null || echo "000")
    RESPONSE_BODY=$(cat "$tmp_body" 2>/dev/null || echo "")
    RESPONSE_HEADERS=$(cat "$tmp_headers" 2>/dev/null || echo "")

    rm -f "$tmp_body" "$tmp_headers"
}

# Convenience request wrappers
http_get() {
    do_request "GET" "$1"
}

http_post() {
    do_request "POST" "$1" "$2" "${3:-application/json}"
}

http_put() {
    do_request "PUT" "$1" "$2" "${3:-application/json}"
}

http_delete() {
    do_request "DELETE" "$1"
}

# Assertions
assert_status_code() {
    local expected="$1"
    local actual="$RESPONSE_CODE"
    local test_name="$2"

    if [ "$actual" = "$expected" ]; then
        log_pass "$test_name" "HTTP Status $actual"
        return 0
    else
        log_fail "$test_name" "Expected HTTP $expected, got $actual. Response: $RESPONSE_BODY"
        return 1
    fi
}

assert_json_field() {
    local filter="$1"
    local expected="$2"
    local test_name="$3"

    local actual
    actual=$(printf "%s" "$RESPONSE_BODY" | jq -r "$filter" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        log_pass "$test_name" "Field $filter == '$expected'"
        return 0
    else
        log_fail "$test_name" "Field $filter expected '$expected', got '$actual'"
        return 1
    fi
}

assert_json_field_not_empty() {
    local filter="$1"
    local test_name="$2"

    local actual
    actual=$(printf "%s" "$RESPONSE_BODY" | jq -r "$filter" 2>/dev/null)
    if [ -n "$actual" ] && [ "$actual" != "null" ]; then
        log_pass "$test_name" "Field $filter is present ('$actual')"
        return 0
    else
        log_fail "$test_name" "Field $filter is empty or null"
        return 1
    fi
}

assert_json_array() {
    local test_name="$1"
    local is_array
    is_array=$(printf "%s" "$RESPONSE_BODY" | jq 'type == "array"' 2>/dev/null)
    if [ "$is_array" = "true" ]; then
        local count
        count=$(printf "%s" "$RESPONSE_BODY" | jq 'length' 2>/dev/null)
        log_pass "$test_name" "Response is JSON array (count: $count)"
        return 0
    else
        log_fail "$test_name" "Response is not a valid JSON array"
        return 1
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local test_name="$3"

    if [[ "$haystack" == *"$needle"* ]]; then
        log_pass "$test_name" "Found '$needle'"
        return 0
    else
        log_fail "$test_name" "Target text does not contain '$needle'"
        return 1
    fi
}

assert_header_contains() {
    local header_name="$1"
    local needle="$2"
    local test_name="$3"

    local header_val
    header_val=$(printf "%s" "$RESPONSE_HEADERS" | grep -i "^${header_name}:" | tr -d '\r')
    if [[ "$header_val" == *"$needle"* ]]; then
        log_pass "$test_name" "$header_name matches '$needle'"
        return 0
    else
        log_fail "$test_name" "Header $header_name ('$header_val') does not contain '$needle'"
        return 1
    fi
}

# Kubernetes Cluster Verification Helpers
k8s_is_available() {
    kubectl cluster-info --request-timeout=3s >/dev/null 2>&1
}

k8s_require_cluster() {
    local test_name="$1"
    if ! k8s_is_available; then
        log_skip "$test_name" "Kubernetes cluster is not reachable via kubectl"
        return 1
    fi
    return 0
}
