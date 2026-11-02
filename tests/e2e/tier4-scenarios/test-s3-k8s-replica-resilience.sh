#!/usr/bin/env bash
# ==============================================================================
# Tier 4: Scenario S3 — Dual Replica Verification & Service Resilience
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier4-scenarios/test-s3-k8s-replica-resilience.sh
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

print_tier_header "Tier 4: Scenario S3" "Replica Count Verification & High Availability Resilience"
log_info "Target Host: ${TARGET_HOST}"
log_info "Target Namespace: ${TARGET_NAMESPACE}"

# 1. Ingress Single Entrypoint Routing Check
log_info "Phase 1: Validating unified ingress routing on host..."
http_get "/"
assert_status_code "200" "S3.1: Ingress routes / to frontend service"
assert_contains "$RESPONSE_BODY" "<!DOCTYPE html>" "S3.2: Ingress returns valid HTML for /"

http_get "/api/tasks"
assert_status_code "200" "S3.3: Ingress routes /api to backend service"
assert_json_array "S3.4: Ingress returns valid JSON array for /api/tasks"

# 2. Kubernetes Deployment Replicas Verification
log_info "Phase 2: Checking Kubernetes Deployment replica counts..."
if ! k8s_require_cluster "S3: Cluster Deployment Status"; then
    print_summary "Tier 4: Scenario S3 Results (Cluster Offline)"
    exit 0
fi

# Check backend deployment
BACKEND_SPEC_REPLICAS=$(kubectl get deployment backend -n "${TARGET_NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
BACKEND_READY_REPLICAS=$(kubectl get deployment backend -n "${TARGET_NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)

if [ "$BACKEND_SPEC_REPLICAS" -eq 2 ]; then
    log_pass "S3.5: Backend deployment specifies 2 replicas"
else
    log_fail "S3.5: Backend spec.replicas expected 2, got $BACKEND_SPEC_REPLICAS"
fi

if [ "$BACKEND_READY_REPLICAS" -eq 2 ]; then
    log_pass "S3.6: Backend deployment has 2/2 ready replicas"
else
    log_fail "S3.6: Backend readyReplicas expected 2, got $BACKEND_READY_REPLICAS"
fi

# Check frontend deployment
FRONTEND_SPEC_REPLICAS=$(kubectl get deployment frontend -n "${TARGET_NAMESPACE}" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 0)
FRONTEND_READY_REPLICAS=$(kubectl get deployment frontend -n "${TARGET_NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)

if [ "$FRONTEND_SPEC_REPLICAS" -eq 2 ]; then
    log_pass "S3.7: Frontend deployment specifies 2 replicas"
else
    log_fail "S3.7: Frontend spec.replicas expected 2, got $FRONTEND_SPEC_REPLICAS"
fi

if [ "$FRONTEND_READY_REPLICAS" -eq 2 ]; then
    log_pass "S3.8: Frontend deployment has 2/2 ready replicas"
else
    log_fail "S3.8: Frontend readyReplicas expected 2, got $FRONTEND_READY_REPLICAS"
fi

# Check postgres statefulset
POSTGRES_READY_REPLICAS=$(kubectl get statefulset postgres -n "${TARGET_NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
if [ "$POSTGRES_READY_REPLICAS" -eq 1 ]; then
    log_pass "S3.9: PostgreSQL StatefulSet has 1/1 ready replica"
else
    log_fail "S3.9: PostgreSQL StatefulSet readyReplicas expected 1, got $POSTGRES_READY_REPLICAS"
fi

# Phase 3: Single Replica Fault Tolerance
log_info "Phase 3: Testing single backend replica termination resilience..."
FIRST_BACKEND_POD=$(kubectl get pods -n "${TARGET_NAMESPACE}" -l app=backend -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -n "$FIRST_BACKEND_POD" ]; then
    log_info "Terminating backend pod '${FIRST_BACKEND_POD}' to test continuous traffic availability..."
    kubectl delete pod "$FIRST_BACKEND_POD" -n "${TARGET_NAMESPACE}" --now >/dev/null 2>&1 || true

    # Immediately query backend to verify zero-downtime serving via second replica
    http_get "/api/tasks"
    assert_status_code "200" "S3.10: Traffic continuously served during pod termination"

    # Wait up to 60s for deployment to return to 2/2 ready replicas
    log_info "Waiting for backend deployment to self-heal back to 2/2 ready replicas..."
    if kubectl rollout status deployment/backend -n "${TARGET_NAMESPACE}" --timeout=60s >/dev/null 2>&1; then
        RECOVERED_REPLICAS=$(kubectl get deployment backend -n "${TARGET_NAMESPACE}" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
        if [ "$RECOVERED_REPLICAS" -eq 2 ]; then
            log_pass "S3.11: Backend deployment successfully restored 2/2 ready replicas"
        else
            log_fail "S3.11: Backend recovered replicas count mismatch" "Expected 2, got $RECOVERED_REPLICAS"
        fi
    else
        log_fail "S3.11: Timeout waiting for backend deployment recovery"
    fi
else
    log_skip "S3.10: Backend pod termination resilience" "No backend pod found"
fi

print_summary "Tier 4: Scenario S3 Replica Resilience Results"
