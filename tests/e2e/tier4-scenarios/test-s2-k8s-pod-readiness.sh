#!/usr/bin/env bash
# ==============================================================================
# Tier 4: Scenario S2 — Kubernetes Pod Status & Readiness Verification
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/tier4-scenarios/test-s2-k8s-pod-readiness.sh
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

print_tier_header "Tier 4: Scenario S2" "Kubernetes Cluster Pod Running & Ready Acceptance"
log_info "Target Namespace: ${TARGET_NAMESPACE}"

# Verify cluster connectivity
if ! k8s_require_cluster "S2: Cluster Accessibility"; then
    print_summary "Tier 4: Scenario S2 Results (Cluster Offline)"
    exit 0
fi

# 1. Verify Namespace Exists
log_info "Checking if namespace '${TARGET_NAMESPACE}' exists..."
if kubectl get namespace "${TARGET_NAMESPACE}" >/dev/null 2>&1; then
    log_pass "S2.1: Namespace '${TARGET_NAMESPACE}' exists"
else
    log_fail "S2.1: Namespace '${TARGET_NAMESPACE}' not found in cluster"
fi

# 2. Query all pods in namespace
log_info "Querying pods in namespace '${TARGET_NAMESPACE}'..."
POD_JSON=$(kubectl get pods -n "${TARGET_NAMESPACE}" -o json 2>/dev/null || echo '{"items":[]}')
POD_COUNT=$(printf "%s" "$POD_JSON" | jq '.items | length' 2>/dev/null || echo 0)

if [ "$POD_COUNT" -gt 0 ]; then
    log_pass "S2.2: Namespace contains running pods" "Found: $POD_COUNT pods"
else
    log_fail "S2.2: No pods found in namespace '${TARGET_NAMESPACE}'"
fi

# 3. Check every pod phase is 'Running'
ALL_RUNNING=true
while IFS= read -r line; do
    [ -z "$line" ] && continue
    pod_name=$(echo "$line" | awk '{print $1}')
    pod_phase=$(echo "$line" | awk '{print $2}')
    if [ "$pod_phase" = "Running" ]; then
        log_pass "S2.3.pod_${pod_name}: Pod phase is Running"
    else
        log_fail "S2.3.pod_${pod_name}: Pod phase is '$pod_phase'" "Expected Running"
        ALL_RUNNING=false
    fi
done < <(printf "%s" "$POD_JSON" | jq -r '.items[] | "\(.metadata.name) \(.status.phase)"' 2>/dev/null)

# 4. Check readiness condition (Ready: True) for every pod
ALL_READY=true
while IFS= read -r line; do
    [ -z "$line" ] && continue
    pod_name=$(echo "$line" | awk '{print $1}')
    ready_status=$(echo "$line" | awk '{print $2}')
    if [ "$ready_status" = "True" ]; then
        log_pass "S2.4.ready_${pod_name}: Pod Ready condition is True"
    else
        log_fail "S2.4.ready_${pod_name}: Pod Ready condition is '$ready_status'"
        ALL_READY=false
    fi
done < <(printf "%s" "$POD_JSON" | jq -r '.items[] | "\(.metadata.name) \((.status.conditions[]? | select(.type=="Ready") | .status) // "False")"' 2>/dev/null)

# 5. Check no containers are restarting or in CrashLoopBackOff
NO_CRASH_LOOPS=true
while IFS= read -r line; do
    [ -z "$line" ] && continue
    pod_name=$(echo "$line" | awk '{print $1}')
    restart_count=$(echo "$line" | awk '{print $2}')
    waiting_reason=$(echo "$line" | awk '{print $3}')
    if [ "$waiting_reason" != "CrashLoopBackOff" ] && [ "$waiting_reason" != "Error" ]; then
        log_pass "S2.5.healthy_${pod_name}: Pod container healthy (restarts: $restart_count)"
    else
        log_fail "S2.5.healthy_${pod_name}: Pod container failed" "Reason: $waiting_reason, Restarts: $restart_count"
        NO_CRASH_LOOPS=false
    fi
done < <(printf "%s" "$POD_JSON" | jq -r '.items[] | "\(.metadata.name) \([.status.containerStatuses[]?.restartCount // 0] | add // 0) \((.status.containerStatuses[]?.state.waiting.reason) // "None")"' 2>/dev/null)

print_summary "Tier 4: Scenario S2 Pod Readiness Results"
