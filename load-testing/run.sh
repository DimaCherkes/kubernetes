#!/usr/bin/env bash
# ==============================================================================
# Full-Stack Application k6 Stress Test Launcher
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_URL="${TARGET_URL:-http://localhost}"

echo "========================================================================"
echo "           K6 LOAD & STRESS TEST (MELT OBSERVABILITY)                   "
echo "========================================================================"
echo "  Target URL:        ${TARGET_URL}"
echo "  Profile:           15s (15 VUs) -> 45s (30 VUs) -> 15s (45 VUs) -> 15s (0)"
echo "  Total Duration:    ~1m 30s"
echo "  Expected Rate:     ~100 - 150 RPS"
echo "========================================================================"
echo ""
echo "📊 Во время теста откройте в браузере дашборды Grafana:"
echo "   1. JVM & RPS:    http://localhost/grafana/d/spring-boot-jvm/spring-boot-jvm-and-application-metrics"
echo "   2. Node & Pods:  http://localhost/grafana/d/k8s-nodes-pods/kubernetes-nodes-and-pods-health"
echo "   3. Live Logs:    http://localhost/grafana/d/live-logs-events/live-logs-and-cluster-events-explorer"
echo "   4. Traces:       http://localhost/grafana/d/traces-explorer/distributed-traces-explorer"
echo ""
echo "Запуск теста через 3 секунды..."
sleep 3

k6 run "${SCRIPT_DIR}/load-test.js" --env TARGET_URL="${TARGET_URL}"
