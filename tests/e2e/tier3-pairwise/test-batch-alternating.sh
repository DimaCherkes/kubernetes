#!/usr/bin/env bash
# ==============================================================================
# Tier 3: Pairwise Tests — Batch Alternating State Transitions & Deletions
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier3-pairwise/test-batch-alternating.sh
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

print_tier_header "Tier 3: Pairwise" "Batch Creation, State Inversion & Selective Deletion"
log_info "Target Host: ${TARGET_HOST}"

BATCH_IDS=()
cleanup() {
    for id in "${BATCH_IDS[@]}"; do
        http_delete "/api/tasks/${id}" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

# 1. Create a batch of 6 tasks with alternating initial completion states
log_info "Creating batch of 6 tasks with alternating completion targets..."
for i in {1..6}; do
    WANT_COMPLETED="false"
    if [ $((i % 2)) -eq 0 ]; then
        WANT_COMPLETED="true"
    fi

    PAYLOAD=$(jq -n --arg t "Batch Task $i" --arg d "Batch description $i" '{"title": $t, "description": $d}')
    http_post "/api/tasks" "$PAYLOAD"
    assert_status_code "201" "P2.$i: Create batch task $i returns 201"
    TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
    BATCH_IDS+=("$TID")

    if [ "$WANT_COMPLETED" = "true" ]; then
        PUT_PAYLOAD=$(jq -n --arg t "Batch Task $i" --arg d "Batch description $i" '{"title": $t, "description": $d, "completed": true}')
        http_put "/api/tasks/${TID}" "$PUT_PAYLOAD"
        assert_status_code "200" "P2.${i}_init: Set task $i completed to true"
    fi
done

# 2. Verify all 6 exist with expected alternating completed states
log_info "Verifying batch initial states in GET /api/tasks..."
http_get "/api/tasks"
assert_status_code "200" "P2.7: Retrieve tasks list returns 200"

for idx in "${!BATCH_IDS[@]}"; do
    i=$((idx + 1))
    tid="${BATCH_IDS[$idx]}"
    EXPECTED_STATUS="false"
    if [ $((i % 2)) -eq 0 ]; then
        EXPECTED_STATUS="true"
    fi
    ACTUAL_STATUS=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$tid" '.[] | select(.id == ($id | tonumber)) | .completed' 2>/dev/null)
    if [ "$ACTUAL_STATUS" = "$EXPECTED_STATUS" ]; then
        log_pass "P2.8.$i: Task $i (ID $tid) initial completed status matches ($EXPECTED_STATUS)"
    else
        log_fail "P2.8.$i: Task $i (ID $tid) status mismatch" "Expected $EXPECTED_STATUS, got $ACTUAL_STATUS"
    fi
done

# 3. Invert completion status for all 6 tasks
log_info "Inverting completion status for all 6 tasks..."
for idx in "${!BATCH_IDS[@]}"; do
    i=$((idx + 1))
    tid="${BATCH_IDS[$idx]}"
    # If it was false, invert to true; if true, invert to false
    NEW_STATUS="true"
    if [ $((i % 2)) -eq 0 ]; then
        NEW_STATUS="false"
    fi

    INVERT_PAYLOAD=$(jq -n --arg t "Batch Task $i Inverted" --arg d "Batch desc $i" --argjson c "$NEW_STATUS" '{"title": $t, "description": $d, "completed": $c}')
    http_put "/api/tasks/${tid}" "$INVERT_PAYLOAD"
    assert_status_code "200" "P2.9.$i: Invert status for task $i returns 200"
    assert_json_field ".completed" "$NEW_STATUS" "P2.9.${i}_field: Status inverted to $NEW_STATUS"
done

# 4. Verify full list reflects inversion
log_info "Verifying inverted status in GET /api/tasks list..."
http_get "/api/tasks"
for idx in "${!BATCH_IDS[@]}"; do
    i=$((idx + 1))
    tid="${BATCH_IDS[$idx]}"
    EXPECTED_INVERTED="true"
    if [ $((i % 2)) -eq 0 ]; then
        EXPECTED_INVERTED="false"
    fi
    ACTUAL_INVERTED=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$tid" '.[] | select(.id == ($id | tonumber)) | .completed' 2>/dev/null)
    if [ "$ACTUAL_INVERTED" = "$EXPECTED_INVERTED" ]; then
        log_pass "P2.10.$i: Task $i in list reflects inverted state ($EXPECTED_INVERTED)"
    else
        log_fail "P2.10.$i: Task $i list state mismatch" "Expected $EXPECTED_INVERTED, got $ACTUAL_INVERTED"
    fi
done

# 5. Selectively delete odd-indexed tasks (tasks 1, 3, 5)
log_info "Selectively deleting odd tasks (1, 3, 5)..."
DELETE_INDICES=(0 2 4)
for idx in "${DELETE_INDICES[@]}"; do
    tid="${BATCH_IDS[$idx]}"
    http_delete "/api/tasks/${tid}"
    assert_status_code "204" "P2.11.${idx}: Delete task (ID $tid) returns 204"
done

# 6. Verify deleted tasks are gone and even-indexed tasks remain intact
log_info "Verifying selective deletion state in list..."
http_get "/api/tasks"
for idx in "${DELETE_INDICES[@]}"; do
    tid="${BATCH_IDS[$idx]}"
    FOUND=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$tid" '.[] | select(.id == ($id | tonumber)) | .id' 2>/dev/null)
    if [ -z "$FOUND" ]; then
        log_pass "P2.12.del_${idx}: Task ID $tid is confirmed absent from list"
    else
        log_fail "P2.12.del_${idx}: Task ID $tid was supposed to be deleted but is still in list"
    fi
done

REMAINING_INDICES=(1 3 5)
for idx in "${REMAINING_INDICES[@]}"; do
    tid="${BATCH_IDS[$idx]}"
    FOUND=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$tid" '.[] | select(.id == ($id | tonumber)) | .id' 2>/dev/null)
    if [ -n "$FOUND" ]; then
        log_pass "P2.12.rem_${idx}: Task ID $tid is verified intact in list"
    else
        log_fail "P2.12.rem_${idx}: Task ID $tid should remain intact but is missing"
    fi
done

print_summary "Tier 3: Batch Alternating Test Results"
