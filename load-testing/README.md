# Load & Stress Testing (k6)

This directory contains the **k6** load and stress testing suite, designed to evaluate Kubernetes pod resource thresholds and generate a rich stream of telemetry in the **MELT** stack.

---

## Load Profile

* **Duration:** ~1 minute 30 seconds.
* **Stages:**
  1. `0s - 15s`: Ramp-up to **15 VUs** (~40–60 RPS) — baseline traffic warmup.
  2. `15s - 60s`: Steady stress at **30 VUs** (~100–150 RPS) — stresses pod CPU and PostgreSQL HikariCP connection pool.
  3. `60s - 75s`: Peak spike to **45 VUs** — tests throughput limits and latency spikes (p95 / p99).
  4. `75s - 90s`: Cooldown to 0 VUs — monitors queue drain and cluster recovery.

## Simulated User Operations (per VU):
* `GET /` — Fetches static assets (exercises Ingress and Nginx replicas).
* `GET /api/tasks` — Queries database tasks (SELECT via Spring Data JPA with pagination).
* `POST /api/tasks` — Creates new task (INSERT transaction + OpenTelemetry TraceID generation).
* `PUT /api/tasks/:id` — Toggles task completion (UPDATE transaction).
* `DELETE /api/tasks/:id` — Cleans up every 3rd created task (DELETE transaction).

---

## How to Run

```bash
# Using the convenience runner script:
./full-stack-app/load-testing/run.sh

# Or directly with the k6 CLI:
k6 run full-stack-app/load-testing/load-test.js
```

---

## What to Observe in Grafana During the Test

Open [http://localhost/grafana](http://localhost/grafana) before starting:

1. **`Spring Boot JVM & Application Metrics`**:
   * **Total System RPS** and **Per-Pod RPS Breakdown**: Observe real-time traffic balancing across both backend pods.
   * **HTTP Latency (p95 & p99)**: Millisecond-level response times under heavy load.
   * **HikariCP Connection Pool**: Active vs. idle connections to PostgreSQL.
2. **`Kubernetes Nodes & Pods Health`**:
   * **Per-Pod CPU & Memory**: Watch pods approach configured resource limits on worker nodes.
3. **`Distributed Traces Explorer`**:
   * Fresh traces ingested in Tempo with waterfall timing breakdowns across Spring MVC and Postgres.
4. **`Live Logs & Cluster Events Explorer`**:
   * Real-time logs streamed from both backend replicas via Promtail to Loki.
