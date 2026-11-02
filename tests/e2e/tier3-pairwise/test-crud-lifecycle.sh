#!/usr/bin/env bash
# ==============================================================================
# Tier 3: Pairwise Tests — Full Entity CRUD Lifecycle Transition
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier3-pairwise/test-crud-lifecycle.sh
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

print_tier_header "Tier 3: Pairwise" "End-to-End Single Entity Lifecycle Sequence"
log_info "Target Host: ${TARGET_HOST}"

TASK_ID=""
cleanup() {
    if [ -n "$TASK_ID" ]; then
        http_delete "/api/tasks/${TASK_ID}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# Step 1: Create
log_info "Step 1: Create new task..."
http_post "/api/tasks" '{"title":"Lifecycle Alpha","description":"Lifecycle step 1"}'
assert_status_code "201" "P1.1: Task creation returns HTTP 201"
TASK_ID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
assert_json_field ".title" "Lifecycle Alpha" "P1.2: Created task has correct title"
assert_json_field ".completed" "false" "P1.3: Created task initialized to completed=false"

# Step 2: Verify in List
log_info "Step 2: Verify entity presence in full task list..."
http_get "/api/tasks"
assert_status_code "200" "P1.4: List retrieval returns HTTP 200"
MATCHING_COMPLETED=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$TASK_ID" '.[] | select(.id == ($id | tonumber)) | .completed' 2>/dev/null)
if [ "$MATCHING_COMPLETED" = "false" ]; then
    log_pass "P1.5: Task present in list with completed=false"
else
    log_fail "P1.5: Task missing or completed status mismatch in list" "Got: '$MATCHING_COMPLETED'"
fi

# Step 3: Update completion status to true
log_info "Step 3: Update status to completed=true..."
http_put "/api/tasks/${TASK_ID}" '{"title":"Lifecycle Alpha","description":"Lifecycle step 1","completed":true}'
assert_status_code "200" "P1.6: Status update returns HTTP 200"
assert_json_field ".completed" "true" "P1.7: Response reflects completed=true"

# Step 4: Update description and title
log_info "Step 4: Update title and description while keeping completed=true..."
http_put "/api/tasks/${TASK_ID}" '{"title":"Lifecycle Alpha Updated","description":"Lifecycle step 4 revised","completed":true}'
assert_status_code "200" "P1.8: Title/description update returns HTTP 200"
assert_json_field ".title" "Lifecycle Alpha Updated" "P1.9: Response reflects updated title"
assert_json_field ".description" "Lifecycle step 4 revised" "P1.10: Response reflects updated description"
assert_json_field ".completed" "true" "P1.11: Completion remains true after content update"

# Step 5: Verify updated state in full list
log_info "Step 5: Verify updated state in list..."
http_get "/api/tasks"
UPDATED_TITLE=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$TASK_ID" '.[] | select(.id == ($id | tonumber)) | .title' 2>/dev/null)
UPDATED_STATUS=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$TASK_ID" '.[] | select(.id == ($id | tonumber)) | .completed' 2>/dev/null)
if [ "$UPDATED_TITLE" = "Lifecycle Alpha Updated" ] && [ "$UPDATED_STATUS" = "true" ]; then
    log_pass "P1.12: List accurately reflects modified title and completed status"
else
    log_fail "P1.12: List state mismatch" "Title: '$UPDATED_TITLE', Completed: '$UPDATED_STATUS'"
fi

# Step 6: Delete entity
log_info "Step 6: Delete entity..."
http_delete "/api/tasks/${TASK_ID}"
assert_status_code "204" "P1.13: Deletion returns HTTP 204 No Content"

# Step 7: Verify absent from list
log_info "Step 7: Verify entity no longer appears in list..."
http_get "/api/tasks"
ID_IN_LIST=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$TASK_ID" '.[] | select(.id == ($id | tonumber)) | .id' 2>/dev/null)
if [ -z "$ID_IN_LIST" ]; then
    log_pass "P1.14: Entity is verified absent from list after deletion"
else
    log_fail "P1.14: Deleted entity still found in list" "ID: $TASK_ID"
fi

# Step 8: Verify subsequent DELETE returns 404
log_info "Step 8: Re-attempt DELETE on deleted entity..."
http_delete "/api/tasks/${TASK_ID}"
assert_status_code "404" "P1.15: Subsequent DELETE returns HTTP 404 Not Found"

# Step 9: Verify subsequent PUT returns 404
log_info "Step 9: Re-attempt PUT on deleted entity..."
http_put "/api/tasks/${TASK_ID}" '{"title":"Should Fail","description":"Zombie task","completed":false}'
assert_status_code "404" "P1.16: Subsequent PUT returns HTTP 404 Not Found"

# Mark task as already deleted so trap doesn't fail
TASK_ID=""

print_summary "Tier 3: Lifecycle Test Results"
