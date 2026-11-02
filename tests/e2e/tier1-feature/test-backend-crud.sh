#!/usr/bin/env bash
# ==============================================================================
# Tier 1: Feature Tests — Backend REST API CRUD (GET, POST, PUT, DELETE)
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier1-feature/test-backend-crud.sh
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "${SCRIPT_DIR}/../lib" && pwd)"
source "${LIB_DIR}/test-helpers.sh"

# CLI argument parsing
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

print_tier_header "Tier 1: Feature" "Backend REST API CRUD Verification"
log_info "Target Host: ${TARGET_HOST}"

CREATED_TASK_IDS=()
cleanup() {
    for id in "${CREATED_TASK_IDS[@]}"; do
        http_delete "/api/tasks/${id}" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

# ------------------------------------------------------------------------------
# Feature 1: GET /api/tasks
# ------------------------------------------------------------------------------
log_info "Testing Feature 1: GET /api/tasks endpoint..."

http_get "/api/tasks"
assert_status_code "200" "F1.1: GET /api/tasks returns HTTP 200 OK"
assert_header_contains "Content-Type" "application/json" "F1.2: GET /api/tasks returns application/json Content-Type"
assert_json_array "F1.3: GET /api/tasks returns a valid JSON array"

# Check idempotency across consecutive calls
FIRST_BODY="$RESPONSE_BODY"
http_get "/api/tasks"
if [ "$FIRST_BODY" = "$RESPONSE_BODY" ]; then
    log_pass "F1.4: GET /api/tasks is idempotent across consecutive calls"
else
    log_fail "F1.4: GET /api/tasks idempotency check failed" "Body changed without mutations"
fi

# ------------------------------------------------------------------------------
# Feature 2: POST /api/tasks
# ------------------------------------------------------------------------------
log_info "Testing Feature 2: POST /api/tasks endpoint..."

POST_PAYLOAD='{"title":"E2E Feature Task","description":"Verifying primary CRUD flow"}'
http_post "/api/tasks" "$POST_PAYLOAD"
assert_status_code "201" "F2.1: POST /api/tasks returns HTTP 201 Created"

TASK_ID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
if [[ "$TASK_ID" =~ ^[0-9]+$ ]] && [ "$TASK_ID" -gt 0 ]; then
    CREATED_TASK_IDS+=("$TASK_ID")
    log_pass "F2.2: POST /api/tasks returns valid generated integer ID ($TASK_ID)"
else
    log_fail "F2.2: POST /api/tasks returned invalid ID" "Got: '$TASK_ID'"
fi

assert_header_contains "Location" "/api/tasks/" "F2.3: POST /api/tasks returns Location header"
assert_json_field ".title" "E2E Feature Task" "F2.4: POST /api/tasks echoes correct title"
assert_json_field ".description" "Verifying primary CRUD flow" "F2.5: POST /api/tasks echoes correct description"
assert_json_field ".completed" "false" "F2.6: POST /api/tasks defaults completed to false"
assert_json_field_not_empty ".createdAt" "F2.7: POST /api/tasks populates createdAt timestamp"

# Validate that the task now appears in the list (F1.5)
http_get "/api/tasks"
TASK_IN_LIST=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$TASK_ID" '.[] | select(.id == ($id | tonumber)) | .title' 2>/dev/null)
if [ "$TASK_IN_LIST" = "E2E Feature Task" ]; then
    log_pass "F1.5: GET /api/tasks list contains newly created task" "ID: $TASK_ID"
else
    log_fail "F1.5: Created task not found in GET /api/tasks list" "Expected ID: $TASK_ID"
fi

# ------------------------------------------------------------------------------
# Feature 3: PUT /api/tasks/{id}
# ------------------------------------------------------------------------------
log_info "Testing Feature 3: PUT /api/tasks/{id} endpoint..."

PUT_PAYLOAD_1='{"title":"Updated Feature Task","description":"Updated description text","completed":false}'
http_put "/api/tasks/${TASK_ID}" "$PUT_PAYLOAD_1"
assert_status_code "200" "F3.1: PUT /api/tasks/{id} updates title/description and returns 200 OK"
assert_json_field ".title" "Updated Feature Task" "F3.2: PUT /api/tasks/{id} reflects updated title"
assert_json_field ".description" "Updated description text" "F3.3: PUT /api/tasks/{id} reflects updated description"

# Toggle completion to true
PUT_PAYLOAD_2='{"title":"Updated Feature Task","description":"Updated description text","completed":true}'
http_put "/api/tasks/${TASK_ID}" "$PUT_PAYLOAD_2"
assert_status_code "200" "F3.4: PUT /api/tasks/{id} toggles completed status to true"
assert_json_field ".completed" "true" "F3.5: PUT /api/tasks/{id} reflects completed == true"

# Toggle completion back to false
PUT_PAYLOAD_3='{"title":"Updated Feature Task","description":"Updated description text","completed":false}'
http_put "/api/tasks/${TASK_ID}" "$PUT_PAYLOAD_3"
assert_status_code "200" "F3.6: PUT /api/tasks/{id} toggles completed status back to false"
assert_json_field ".completed" "false" "F3.7: PUT /api/tasks/{id} reflects completed == false"

# ------------------------------------------------------------------------------
# Feature 4: DELETE /api/tasks/{id}
# ------------------------------------------------------------------------------
log_info "Testing Feature 4: DELETE /api/tasks/{id} endpoint..."

http_delete "/api/tasks/${TASK_ID}"
assert_status_code "204" "F4.1: DELETE /api/tasks/{id} returns HTTP 204 No Content"

if [ -z "$RESPONSE_BODY" ]; then
    log_pass "F4.2: DELETE /api/tasks/{id} returns empty response body"
else
    log_fail "F4.2: DELETE response body is not empty" "Length: ${#RESPONSE_BODY}"
fi

# Verify task is absent from list
http_get "/api/tasks"
DELETED_STILL_PRESENT=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$TASK_ID" '.[] | select(.id == ($id | tonumber)) | .id' 2>/dev/null)
if [ -z "$DELETED_STILL_PRESENT" ]; then
    log_pass "F4.3: Deleted task is verified removed from GET /api/tasks list"
else
    log_fail "F4.3: Task still exists in list after DELETE" "ID: $TASK_ID"
fi

# Subsequent DELETE should return 404
http_delete "/api/tasks/${TASK_ID}"
assert_status_code "404" "F4.4: Subsequent DELETE on deleted task returns HTTP 404 Not Found"

# Subsequent PUT should return 404
http_put "/api/tasks/${TASK_ID}" '{"title":"Should Fail","description":"Non-existent","completed":true}'
assert_status_code "404" "F4.5: Subsequent PUT on deleted task returns HTTP 404 Not Found"

print_summary "Tier 1: Backend CRUD Test Results"
