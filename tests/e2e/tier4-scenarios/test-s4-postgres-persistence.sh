#!/usr/bin/env bash
# ==============================================================================
# Tier 4: Scenario S4 — PostgreSQL StatefulSet Pod Chaos & Persistence Acceptance
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier4-scenarios/test-s4-postgres-persistence.sh
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

print_tier_header "Tier 4: Scenario S4" "PostgreSQL Pod Kill & PVC Data Persistence Verification"
log_info "Target Host: ${TARGET_HOST}"
log_info "Target Namespace: ${TARGET_NAMESPACE}"

MARKER_ID=""
cleanup() {
    if [ -n "$MARKER_ID" ]; then
        http_delete "/api/tasks/${MARKER_ID}" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# 1. Seed unique persistence marker task
TIMESTAMP=$(date +%s)
RAND_HEX=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n' 2>/dev/null || echo "$RANDOM")
MARKER_TITLE="PERSISTENCE_MARKER_${TIMESTAMP}_${RAND_HEX}"
MARKER_DESC="Verification token asserting PVC data survival across postgres pod recreation"

log_info "Step 1: Creating unique marker task (${MARKER_TITLE})..."
PAYLOAD=$(jq -n --arg t "$MARKER_TITLE" --arg d "$MARKER_DESC" '{"title": $t, "description": $d}')
http_post "/api/tasks" "$PAYLOAD"
assert_status_code "201" "S4.1: Marker task created successfully"

MARKER_ID=$(printf "%s" "$RESPONSE_BODY" | jq -r '.id // empty' 2>/dev/null)
if [[ "$MARKER_ID" =~ ^[0-9]+$ ]] && [ "$MARKER_ID" -gt 0 ]; then
    log_pass "S4.2: Marker task received valid numeric ID ($MARKER_ID)"
else
    log_fail "S4.2: Marker task ID invalid" "Got: '$MARKER_ID'"
fi

# 2. Verify marker exists in database prior to pod kill
log_info "Step 2: Verifying marker presence in database..."
http_get "/api/tasks"
assert_status_code "200" "S4.3: Task list retrieved before chaos test"
PRE_KILL_MATCH=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$MARKER_ID" '.[] | select(.id == ($id | tonumber)) | .title' 2>/dev/null)
if [ "$PRE_KILL_MATCH" = "$MARKER_TITLE" ]; then
    log_pass "S4.4: Marker task confirmed present in database prior to disruption"
else
    log_fail "S4.4: Marker task not found before disruption" "Expected: $MARKER_TITLE"
fi

# 3. Terminate PostgreSQL pod if Kubernetes is accessible
log_info "Step 3: Checking cluster accessibility for PostgreSQL pod chaos..."
if ! k8s_is_available; then
    log_skip "S4.5: PostgreSQL pod kill disruption" "Kubernetes cluster is not reachable via kubectl"
    log_skip "S4.6: Automatic pod recreation" "Cluster offline"
    log_skip "S4.7: Post-disruption marker persistence" "Cluster offline"
    print_summary "Tier 4: Scenario S4 Results (Cluster Offline)"
    exit 0
fi

log_info "Deleting postgres-0 pod in namespace '${TARGET_NAMESPACE}'..."
if kubectl delete pod postgres-0 -n "${TARGET_NAMESPACE}" --now >/dev/null 2>&1; then
    log_pass "S4.5: Successfully issued delete command for pod postgres-0"
else
    log_fail "S4.5: Failed to delete pod postgres-0"
fi

# 4. Wait for postgres-0 recreation and Ready status
log_info "Step 4: Waiting for postgres-0 pod to recreate and reach Ready status (up to 120s)..."
if kubectl wait --for=condition=ready pod/postgres-0 -n "${TARGET_NAMESPACE}" --timeout=120s >/dev/null 2>&1; then
    log_pass "S4.6: Pod postgres-0 recreated and reached 1/1 Ready status"
else
    log_fail "S4.6: Timeout waiting for pod postgres-0 to reach Ready status"
fi

# 5. Wait for Spring Boot connection pool to recover
log_info "Step 5: Waiting for backend connection pool recovery..."
MAX_RETRIES=15
RETRY_COUNT=0
BACKEND_HEALTHY=false

while [ "$RETRY_COUNT" -lt "$MAX_RETRIES" ]; do
    http_get "/actuator/health/readiness"
    if [ "$RESPONSE_CODE" = "200" ]; then
        STATUS=$(printf "%s" "$RESPONSE_BODY" | jq -r '.status // empty' 2>/dev/null)
        if [ "$STATUS" = "UP" ]; then
            BACKEND_HEALTHY=true
            break
        fi
    fi
    RETRY_COUNT=$((RETRY_COUNT + 1))
    sleep 2
done

if [ "$BACKEND_HEALTHY" = "true" ]; then
    log_pass "S4.7: Backend readiness probe confirmed UP following database reconnection"
else
    log_fail "S4.7: Backend readiness probe did not recover within timeout"
fi

# 6. Verify marker task is intact after pod recreation
log_info "Step 6: Querying GET /api/tasks to verify marker task survived pod recreation..."
http_get "/api/tasks"
assert_status_code "200" "S4.8: GET /api/tasks returns HTTP 200 after pod restart"

POST_KILL_MATCH=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$MARKER_ID" '.[] | select(.id == ($id | tonumber)) | .title' 2>/dev/null)
POST_KILL_DESC=$(printf "%s" "$RESPONSE_BODY" | jq -r --arg id "$MARKER_ID" '.[] | select(.id == ($id | tonumber)) | .description' 2>/dev/null)

if [ "$POST_KILL_MATCH" = "$MARKER_TITLE" ] && [ "$POST_KILL_DESC" = "$MARKER_DESC" ]; then
    log_pass "S4.9: Marker task data survived PostgreSQL pod recreation (PVC Persistence Verified)"
else
    log_fail "S4.9: Marker task missing or corrupted after pod restart" "Got title: '$POST_KILL_MATCH'"
fi

# Clean up marker task
http_delete "/api/tasks/${MARKER_ID}"
assert_status_code "204" "S4.10: Persistence marker task cleaned up"
MARKER_ID=""

print_summary "Tier 4: Scenario S4 PostgreSQL Persistence Results"
