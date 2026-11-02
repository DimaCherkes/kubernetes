#!/usr/bin/env bash
# ==============================================================================
# Master E2E Test Suite Runner
# /Users/dmitrycherkes/JavaProjects/tutorials/kubernetes/full-stack-app/tests/e2e/run-e2e-tests.sh
#
# Usage:
#   ./run-e2e-tests.sh [--host <url>] [--namespace <ns>] [--tier <1|2|3|4|all>]
#
# Defaults:
#   --host: http://localhost
#   --namespace: full-stack-app
#   --tier: all
# ==============================================================================

set -uo pipefail

# ANSI Color Codes
CLR_RESET=$'\033[0m'
CLR_BOLD=$'\033[1m'
CLR_GREEN=$'\033[32m'
CLR_RED=$'\033[31m'
CLR_YELLOW=$'\033[33m'
CLR_BLUE=$'\033[34m'
CLR_MAGENTA=$'\033[35m'
CLR_CYAN=$'\033[36m'


# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"
TIER1_DIR="${SCRIPT_DIR}/tier1-feature"
TIER2_DIR="${SCRIPT_DIR}/tier2-boundary"
TIER3_DIR="${SCRIPT_DIR}/tier3-pairwise"
TIER4_DIR="${SCRIPT_DIR}/tier4-scenarios"

# Defaults
TARGET_HOST="http://localhost"
TARGET_NAMESPACE="full-stack-app"
SELECTED_TIER="all"

print_usage() {
    cat <<EOF
${CLR_BOLD}Full-Stack Kubernetes Application E2E Test Runner${CLR_RESET}

${CLR_CYAN}Usage:${CLR_RESET}
  $0 [options]

${CLR_CYAN}Options:${CLR_RESET}
  --host <url>         Target host entrypoint (default: http://localhost)
  --namespace <ns>     Target Kubernetes namespace (default: full-stack-app)
  --tier <1|2|3|4|all> Select specific test tier to run (default: all)
  -h, --help           Show this help message and exit

${CLR_CYAN}Tiers:${CLR_RESET}
  1    Feature Tests (Backend CRUD, Frontend SPA, Actuator Probes)
  2    Boundary Tests (Extreme lengths, invalid inputs, malformed JSON, etc.)
  3    Pairwise Combinatorial Tests (CRUD lifecycle, batch operations)
  4    Real-World Scenarios (Multi-task workload, pod readiness, replicas, persistence)
  all  Run all tiers in sequential order (1 -> 2 -> 3 -> 4)

${CLR_CYAN}Examples:${CLR_RESET}
  $0
  $0 --host http://localhost --tier 1
  $0 --tier 4 --namespace full-stack-app
  $0 --host http://127.0.0.1:8080 --tier all
EOF
}

# Parse CLI arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --host)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo -e "${CLR_RED}Error: --host requires a URL argument${CLR_RESET}" >&2
                exit 1
            fi
            TARGET_HOST="$2"
            shift 2
            ;;
        --namespace)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo -e "${CLR_RED}Error: --namespace requires a namespace argument${CLR_RESET}" >&2
                exit 1
            fi
            TARGET_NAMESPACE="$2"
            shift 2
            ;;
        --tier)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo -e "${CLR_RED}Error: --tier requires an argument (1, 2, 3, 4, or all)${CLR_RESET}" >&2
                exit 1
            fi
            SELECTED_TIER="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo -e "${CLR_RED}Error: Unknown argument: $1${CLR_RESET}" >&2
            print_usage
            exit 1
            ;;
    esac
done

# Validate tier selection
case "$SELECTED_TIER" in
    1|2|3|4|all)
        ;;
    *)
        echo -e "${CLR_RED}Error: Invalid tier '$SELECTED_TIER'. Must be 1, 2, 3, 4, or all.${CLR_RESET}" >&2
        exit 1
        ;;
esac

# Suite definitions
TIER1_SUITES=(
    "tier1-feature/test-backend-crud.sh:Tier 1: Backend CRUD"
    "tier1-feature/test-frontend.sh:Tier 1: Frontend SPA & Health"
    "tier1-feature/test-actuator-probes.sh:Tier 1: Actuator Probes"
)

TIER2_SUITES=(
    "tier2-boundary/test-invalid-inputs.sh:Tier 2: Invalid Inputs"
    "tier2-boundary/test-extreme-lengths.sh:Tier 2: Extreme Lengths"
    "tier2-boundary/test-special-chars-unicode.sh:Tier 2: Unicode & Special Chars"
    "tier2-boundary/test-nonexistent-entities.sh:Tier 2: Non-Existent Entities"
    "tier2-boundary/test-malformed-payloads.sh:Tier 2: Malformed Payloads"
)

TIER3_SUITES=(
    "tier3-pairwise/test-crud-lifecycle.sh:Tier 3: Entity Lifecycle"
    "tier3-pairwise/test-batch-alternating.sh:Tier 3: Batch Transitions"
)

TIER4_SUITES=(
    "tier4-scenarios/test-s1-workload.sh:Tier 4: S1 Multi-Task Workload"
    "tier4-scenarios/test-s2-k8s-pod-readiness.sh:Tier 4: S2 Pod Readiness"
    "tier4-scenarios/test-s3-k8s-replica-resilience.sh:Tier 4: S3 Replica Resilience"
    "tier4-scenarios/test-s4-postgres-persistence.sh:Tier 4: S4 Postgres Persistence"
)

# Populate test list based on selected tier
SUITES_TO_RUN=()
case "$SELECTED_TIER" in
    1)
        SUITES_TO_RUN=("${TIER1_SUITES[@]}")
        ;;
    2)
        SUITES_TO_RUN=("${TIER2_SUITES[@]}")
        ;;
    3)
        SUITES_TO_RUN=("${TIER3_SUITES[@]}")
        ;;
    4)
        SUITES_TO_RUN=("${TIER4_SUITES[@]}")
        ;;
    all)
        SUITES_TO_RUN=(
            "${TIER1_SUITES[@]}"
            "${TIER2_SUITES[@]}"
            "${TIER3_SUITES[@]}"
            "${TIER4_SUITES[@]}"
        )
        ;;
esac

# Banner display
echo -e "${CLR_BOLD}${CLR_MAGENTA}======================================================================${CLR_RESET}"
echo -e "${CLR_BOLD}${CLR_MAGENTA}             FULL-STACK KUBERNETES E2E TEST RUNNER                    ${CLR_RESET}"
echo -e "${CLR_BOLD}${CLR_MAGENTA}======================================================================${CLR_RESET}"
echo -e "  ${CLR_CYAN}Target Host:${CLR_RESET}      ${TARGET_HOST}"
echo -e "  ${CLR_CYAN}Target Namespace:${CLR_RESET} ${TARGET_NAMESPACE}"
echo -e "  ${CLR_CYAN}Selected Tier:${CLR_RESET}    ${SELECTED_TIER}"
echo -e "  ${CLR_CYAN}Suites to Run:${CLR_RESET}    ${#SUITES_TO_RUN[@]}"
echo -e "  ${CLR_CYAN}Start Time:${CLR_RESET}       $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo -e "${CLR_BOLD}${CLR_MAGENTA}======================================================================${CLR_RESET}\n"

# Result tracking arrays
RESULTS_TIER=()
RESULTS_SCRIPT=()
RESULTS_STATUS=()
RESULTS_DURATION=()

TOTAL_SUITES_PASSED=0
TOTAL_SUITES_FAILED=0
RUNNER_START_TIME=$(date +%s)

# Execution loop
for item in "${SUITES_TO_RUN[@]}"; do
    script_rel="${item%%:*}"
    suite_desc="${item##*:}"
    script_path="${SCRIPT_DIR}/${script_rel}"

    if [ ! -f "$script_path" ]; then
        echo -e "${CLR_RED}[ERROR] Test script not found: ${script_path}${CLR_RESET}"
        RESULTS_TIER+=("${suite_desc%%:*}")
        RESULTS_SCRIPT+=("${script_rel}")
        RESULTS_STATUS+=("MISSING")
        RESULTS_DURATION+=("0s")
        TOTAL_SUITES_FAILED=$((TOTAL_SUITES_FAILED + 1))
        continue
    fi

    echo -e "${CLR_BOLD}${CLR_BLUE}>>> Launching: ${suite_desc} (${script_rel})${CLR_RESET}"
    suite_start=$(date +%s)

    # Run the suite forwarding arguments
    if bash "$script_path" --host "$TARGET_HOST" --namespace "$TARGET_NAMESPACE"; then
        suite_end=$(date +%s)
        duration=$((suite_end - suite_start))
        RESULTS_TIER+=("${suite_desc}")
        RESULTS_SCRIPT+=("${script_rel}")
        RESULTS_STATUS+=("PASSED")
        RESULTS_DURATION+=("${duration}s")
        TOTAL_SUITES_PASSED=$((TOTAL_SUITES_PASSED + 1))
    else
        suite_end=$(date +%s)
        duration=$((suite_end - suite_start))
        RESULTS_TIER+=("${suite_desc}")
        RESULTS_SCRIPT+=("${script_rel}")
        RESULTS_STATUS+=("FAILED")
        RESULTS_DURATION+=("${duration}s")
        TOTAL_SUITES_FAILED=$((TOTAL_SUITES_FAILED + 1))
    fi
    echo ""
done

RUNNER_END_TIME=$(date +%s)
TOTAL_RUNNER_DURATION=$((RUNNER_END_TIME - RUNNER_START_TIME))

# Formatted Summary Table
echo -e "\n${CLR_BOLD}${CLR_CYAN}====================================================================================================${CLR_RESET}"
echo -e "${CLR_BOLD}${CLR_CYAN}                                 E2E TEST EXECUTION SUMMARY                                         ${CLR_RESET}"
echo -e "${CLR_BOLD}${CLR_CYAN}====================================================================================================${CLR_RESET}"
printf "${CLR_BOLD}%-32s %-42s %-12s %-10s${CLR_RESET}\n" "Suite Description" "Script File" "Result" "Duration"
echo -e "----------------------------------------------------------------------------------------------------"

for i in "${!RESULTS_SCRIPT[@]}"; do
    tier_desc="${RESULTS_TIER[$i]}"
    script_file="${RESULTS_SCRIPT[$i]}"
    status="${RESULTS_STATUS[$i]}"
    duration="${RESULTS_DURATION[$i]}"

    if [ "$status" = "PASSED" ]; then
        status_colored="${CLR_GREEN}PASSED${CLR_RESET}"
    elif [ "$status" = "FAILED" ]; then
        status_colored="${CLR_RED}FAILED${CLR_RESET}"
    else
        status_colored="${CLR_YELLOW}${status}${CLR_RESET}"
    fi

    printf "%-32s %-42s %-21s %-10s\n" "$tier_desc" "$script_file" "$status_colored" "$duration"
done

echo -e "===================================================================================================="
echo -e "  ${CLR_BOLD}Total Suites:${CLR_RESET} ${#SUITES_TO_RUN[@]} | ${CLR_GREEN}Passed: ${TOTAL_SUITES_PASSED}${CLR_RESET} | ${CLR_RED}Failed: ${TOTAL_SUITES_FAILED}${CLR_RESET} | ${CLR_CYAN}Total Time: ${TOTAL_RUNNER_DURATION}s${CLR_RESET}"
echo -e "===================================================================================================="

if [ "$TOTAL_SUITES_FAILED" -gt 0 ]; then
    echo -e "${CLR_BOLD}${CLR_RED}>>> OVERALL RESULT: FAILED (${TOTAL_SUITES_FAILED} suite(s) failed)${CLR_RESET}\n"
    exit 1
else
    echo -e "${CLR_BOLD}${CLR_GREEN}>>> OVERALL RESULT: ALL SELECTED SUITES PASSED${CLR_RESET}\n"
    exit 0
fi
