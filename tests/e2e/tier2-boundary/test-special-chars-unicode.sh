#!/usr/bin/env bash
# ==============================================================================
# Tier 2: Boundary Tests — Special Characters, Unicode, Emoji & Injection Safety
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier2-boundary/test-special-chars-unicode.sh
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

print_tier_header "Tier 2: Boundary" "Special Characters, Unicode & Sanitization Testing"
log_info "Target Host: ${TARGET_HOST}"

CLEANUP_IDS=()
cleanup() {
    for id in "${CLEANUP_IDS[@]}"; do
        http_delete "/api/tasks/${id}" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

# 1. Emoji support in title & description
log_info "Testing emoji support in task creation..."
EMOJI_TITLE="🚀 Launch K8s App 🎯 ✨ ☸️"
EMOJI_DESC="Testing emoji encoding: 🐳 🐘 ☕ 💻 🌟"
PAYLOAD_EMOJI=$(jq -n --arg t "$EMOJI_TITLE" --arg d "$EMOJI_DESC" '{"title": $t, "description": $d}')
http_post "/api/tasks" "$PAYLOAD_EMOJI"
assert_status_code "201" "B3.1: Emoji payload returns HTTP 201 Created"
TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
[ -n "$TID" ] && CLEANUP_IDS+=("$TID")
assert_json_field ".title" "$EMOJI_TITLE" "B3.2: Exact emoji preserved in title"
assert_json_field ".description" "$EMOJI_DESC" "B3.3: Exact emoji preserved in description"

# 2. Multilingual Unicode characters (Cyrillic, CJK, Arabic, Greek)
log_info "Testing multilingual Unicode strings..."
UNICODE_TITLE="Задача / 任務 / tâche / مهمة / εργασία"
UNICODE_DESC="Проверка кодировки UTF-8: 简体中文, 繁體中文, 日本語, العربية"
PAYLOAD_UNICODE=$(jq -n --arg t "$UNICODE_TITLE" --arg d "$UNICODE_DESC" '{"title": $t, "description": $d}')
http_post "/api/tasks" "$PAYLOAD_UNICODE"
assert_status_code "201" "B3.4: Multilingual Unicode payload returns HTTP 201 Created"
TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
[ -n "$TID" ] && CLEANUP_IDS+=("$TID")
assert_json_field ".title" "$UNICODE_TITLE" "B3.5: Multilingual Unicode title stored without corruption"

# 3. SQL Injection metacharacters safety
log_info "Testing SQL injection payload safety..."
SQLI_TITLE="'; DROP TABLE tasks; SELECT * FROM tasks WHERE '1'='1"
SQLI_DESC="Testing standard SQL meta-characters: ' OR 1=1 -- /* */ ;"
PAYLOAD_SQLI=$(jq -n --arg t "$SQLI_TITLE" --arg d "$SQLI_DESC" '{"title": $t, "description": $d}')
http_post "/api/tasks" "$PAYLOAD_SQLI"
assert_status_code "201" "B3.6: SQL injection string treated as literal text (201 Created)"
TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
[ -n "$TID" ] && CLEANUP_IDS+=("$TID")
assert_json_field ".title" "$SQLI_TITLE" "B3.7: SQL injection string preserved as literal value"

# 4. HTML / Script injection safety
log_info "Testing HTML and Script injection payloads..."
XSS_TITLE="<script>alert('xss')</script>"
XSS_DESC="<img src=x onerror=alert(document.cookie)><b>bold</b>"
PAYLOAD_XSS=$(jq -n --arg t "$XSS_TITLE" --arg d "$XSS_DESC" '{"title": $t, "description": $d}')
http_post "/api/tasks" "$PAYLOAD_XSS"
assert_status_code "201" "B3.8: Script/HTML tags accepted and stored as literal data (201 Created)"
TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
[ -n "$TID" ] && CLEANUP_IDS+=("$TID")
assert_json_field ".title" "$XSS_TITLE" "B3.9: Script tags stored verbatim"

# 5. Multiline text with newlines and tabs
log_info "Testing multiline formatting (newlines, tabs)..."
FORMAT_TITLE="Formatted Text Task"
FORMAT_DESC=$'Line 1\nLine 2 with \ttab\nLine 3 with carriage return\r\nLine 4'
PAYLOAD_FORMAT=$(jq -n --arg t "$FORMAT_TITLE" --arg d "$FORMAT_DESC" '{"title": $t, "description": $d}')
http_post "/api/tasks" "$PAYLOAD_FORMAT"
assert_status_code "201" "B3.10: Multiline formatting returns HTTP 201 Created"
TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
[ -n "$TID" ] && CLEANUP_IDS+=("$TID")
assert_json_field ".title" "$FORMAT_TITLE" "B3.11: Formatted task title matches"

print_summary "Tier 2: Special Characters & Unicode Test Results"
