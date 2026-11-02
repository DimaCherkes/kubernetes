#!/usr/bin/env bash
# ==============================================================================
# Tier 4: Scenario S1 — Realistic Multi-Task Workload Lifecycle
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier4-scenarios/test-s1-workload.sh
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

print_tier_header "Tier 4: Scenario S1" "Realistic Multi-Task End-to-End Workload Simulation"
log_info "Target Host: ${TARGET_HOST}"

WORKLOAD_IDS=()
cleanup() {
    for id in "${WORKLOAD_IDS[@]}"; do
        http_delete "/api/tasks/${id}" >/dev/null 2>&1 || true
    done
}
trap cleanup EXIT

# 1. Seed 5 distinct realistic tasks
log_info "Phase 1: Seeding 5 realistic tasks..."
TASK_TITLES=(
    "Deploy PostgreSQL StatefulSet"
    "Configure Spring Boot Backend"
    "Build Alpine Nginx Frontend"
    "Setup Ingress Routing Rules"
    "Execute Opaque-Box E2E Tests"
)
TASK_DESCS=(
    "StatefulSet with PVC on standard storage class"
    "Java 21 REST API with JPA and Actuator probes"
    "Lightweight static web UI client"
    "Unified host routing for / and /api"
    "Comprehensive verification across 4 tiers"
)

for i in "${!TASK_TITLES[@]}"; do
    PAYLOAD=$(jq -n --arg t "${TASK_TITLES[$i]}" --arg d "${TASK_DESCS[$i]}" '{"title": $t, "description": $d}')
    http_post "/api/tasks" "$PAYLOAD"
    assert_status_code "201" "S1.1.$((i+1)): Created task '${TASK_TITLES[$i]}'"
    TID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
    WORKLOAD_IDS+=("$TID")
done

# 2. Toggle 2 tasks to completed (Task 1 and Task 3)
log_info "Phase 2: Completing Task 1 and Task 3..."
TID_1="${WORKLOAD_IDS[0]}"
TID_3="${WORKLOAD_IDS[2]}"

PUT_1=$(jq -n --arg t "${TASK_TITLES[0]}" --arg d "${TASK_DESCS[0]}" '{"title": $t, "description": $d, "completed": true}')
http_put "/api/tasks/${TID_1}" "$PUT_1"
assert_status_code "200" "S1.2.1: Completed Task 1 (ID $TID_1)"
assert_json_field ".completed" "true" "S1.2.1_chk: Task 1 completed == true"

PUT_3=$(jq -n --arg t "${TASK_TITLES[2]}" --arg d "${TASK_DESCS[2]}" '{"title": $t, "description": $d, "completed": true}')
http_put "/api/tasks/${TID_3}" "$PUT_3"
assert_status_code "200" "S1.2.2: Completed Task 3 (ID $TID_3)"
assert_json_field ".completed" "true" "S1.2.2_chk: Task 3 completed == true"

# 3. Update description of Task 2
log_info "Phase 3: Updating description for Task 2..."
TID_2="${WORKLOAD_IDS[1]}"
REVISED_DESC="Java 21 REST API updated with robust error handling and DTO validations"
PUT_2=$(jq -n --arg t "${TASK_TITLES[1]}" --arg d "$REVISED_DESC" '{"title": $t, "description": $d, "completed": false}')
http_put "/api/tasks/${TID_2}" "$PUT_2"
assert_status_code "200" "S1.3: Updated Task 2 description (ID $TID_2)"
assert_json_field ".description" "$REVISED_DESC" "S1.3_chk: Task 2 description matches revised text"

# 4. Delete Task 4
log_info "Phase 4: Deleting Task 4..."
TID_4="${WORKLOAD_IDS[3]}"
http_delete "/api/tasks/${TID_4}"
assert_status_code "204" "S1.4: Deleted Task 4 (ID $TID_4)"

# 5. Validate full state
log_info "Phase 5: Validating final workload state in GET /api/tasks..."
http_get "/api/tasks"
assert_status_code "200" "S1.5: Retrieved current tasks list"

# Task 1 should be completed
T1_COMP=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$TID_1" '.[] | select(.id == ($id | tonumber)) | .completed' 2>/dev/null)
if [ "$T1_COMP" = "true" ]; then
    log_pass "S1.6: Task 1 verified completed in list"
else
    log_fail "S1.6: Task 1 state mismatch in list" "Expected true, got $T1_COMP"
fi

# Task 2 should have revised description
T2_DESC=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$TID_2" '.[] | select(.id == ($id | tonumber)) | .description' 2>/dev/null)
if [ "$T2_DESC" = "$REVISED_DESC" ]; then
    log_pass "S1.7: Task 2 verified with revised description in list"
else
    log_fail "S1.7: Task 2 description mismatch in list" "Got: '$T2_DESC'"
fi

# Task 3 should be completed
T3_COMP=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$TID_3" '.[] | select(.id == ($id | tonumber)) | .completed' 2>/dev/null)
if [ "$T3_COMP" = "true" ]; then
    log_pass "S1.8: Task 3 verified completed in list"
else
    log_fail "S1.8: Task 3 state mismatch in list" "Expected true, got $T3_COMP"
fi

# Task 4 should NOT exist
T4_EXISTS=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$TID_4" '.[] | select(.id == ($id | tonumber)) | .id' 2>/dev/null)
if [ -z "$T4_EXISTS" ]; then
    log_pass "S1.9: Task 4 verified removed from list"
else
    log_fail "S1.9: Task 4 was deleted but still found in list"
fi

# Task 5 should be present and not completed
TID_5="${WORKLOAD_IDS[4]}"
T5_COMP=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$TID_5" '.[] | select(.id == ($id | tonumber)) | .completed' 2>/dev/null)
if [ "$T5_COMP" = "false" ]; then
    log_pass "S1.10: Task 5 verified present and active in list"
else
    log_fail "S1.10: Task 5 state mismatch in list" "Expected false, got $T5_COMP"
fi

print_summary "Tier 4: Scenario S1 Test Results"
