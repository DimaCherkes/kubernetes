# Observability for Beginners: A Plain-Language Guide

Welcome to the world of Cloud-Native Observability! This guide is designed to explain all key concepts clearly and concisely without unnecessary academic jargon.

---

## 1. What is the Difference Between "Monitoring" and "Observability"?

* **Monitoring:** Answers the question: *"Is the system alive right now?"*.
  Think of a car dashboard with a "Check Engine" light. It glows red when the car breaks down, but it cannot tell you why the timing belt snapped on cylinder 3.
* **Observability:** Answers the question: *"Why is the system behaving this way?"*.
  It is the ability to infer the internal state of a complex, distributed system (dozens of microservices, databases, networks) solely by observing its external outputs and telemetry signals.

---

## 2. The Four Pillars of Observability: What is M.E.L.T.?

In modern cloud-native engineering, all telemetry signals fall into 4 primary categories: **M.E.L.T.**

```
   ┌──────────────────────────────────────────────────────────┐
   │                        M.E.L.T.                          │
   ├─────────────┬─────────────┬──────────────┬───────────────┤
   │  M - Metrics│  E - Events │   L - Logs   │   T - Traces  │
   └─────────────┴─────────────┴──────────────┴───────────────┘
```

Let's understand them using a medical check-up analogy:

### 1. M — Metrics
* **What it is:** Numbers that change over time (*Time Series data*).
* **Analogy:** Pulse (80 bpm), blood pressure (120/80), body temperature (98.6 °F / 36.6 °C).
* **In Kubernetes:** CPU usage (75%), memory working set (512 MiB), request throughput (120 RPS), latency (45 ms).
* **Pros:** Highly compressed, negligible disk footprint. Ideal for dashboards, sparklines, and alert rules (*"alert engineer if CPU > 90% for 5 minutes"*).
* **Components in our cluster:** **Prometheus** (time-series database and scraper), **node-exporter** (host hardware metrics), **Spring Boot Actuator** (application-level metrics).

---

### 2. E — Events
* **What it is:** Discrete, point-in-time facts about significant state changes in the cluster.
* **Analogy:** Doctor's notes: *"Patient took medication at 14:00"*, *"Transferred to Room 12 at 16:30"*.
* **In Kubernetes:**
  - `PodScheduled`: Pod assigned to node `desktop-worker2`.
  - `Pulled`: Container image successfully downloaded.
  - `BackOff`: Container crashed and is waiting before restart.
  - `Unhealthy`: `readinessProbe` or `livenessProbe` failed.
* **Components in our cluster:** **kubernetes-event-exporter** (watches the Kubernetes API event stream and ships events into Loki).

---

### 3. L — Logs
* **What it is:** Detailed, timestamped text records of what the program executed at each millisecond.
* **Analogy:** Transcript of patient conversation: *"At 14:05 felt a sharp pain, at 14:06 drank water, felt better"*.
* **In Kubernetes:** Any `System.out.println` or SLF4J log statement in Java, or Nginx access log:
  ```text
  2026-11-02 00:05:12 INFO [backend] Task created with id=42
  ```
* **Pros:** Provides complete forensic context (stack traces, SQL errors, input parameters).
* **Cons:** High storage volume, slower to search without effective indexing.
* **Components in our cluster:** **Grafana Loki** (log aggregation store) and **Promtail** (DaemonSet agent reading `/var/log/pods`).

---

### 4. T — Traces (Distributed Tracing)
* **What it is:** The complete journey of a single request across all microservices, network hops, and databases, with exact millisecond timings for every step.
* **Analogy:** Postal package tracking: *"Accepted at facility A (2h) ➔ In transit to hub B (5h) ➔ Out for delivery (30m)"*.
* **In Kubernetes:** When a user clicks "Add Task":
  1. Request reaches Ingress (took 2 ms).
  2. Routed to Spring Boot controller (took 3 ms).
  3. Executes `INSERT INTO tasks` in PostgreSQL (took 12 ms).
  4. Response returned to user. Total time: 17 ms.
* **Key Vocabulary:**
  - **Trace:** The full call tree from start to finish.
  - **TraceID:** Unique 32-character hex identifier for this specific request (e.g. `4bf92f3577b34da6a3ce929d0e0e4736`).
  - **Span:** A single unit of work within the trace (e.g. executing an individual SQL query).
* **Components in our cluster:** **Grafana Tempo** (distributed trace storage) and **OpenTelemetry** (instrumentation library in Spring Boot).

---

## 3. The Power of Correlation: How It All Works Together

The core advantage of the **Grafana LGTM stack (Loki, Grafana, Tempo, Mimir/Prometheus)** is bidirectional linking across all data types:

```
[ Metric: Latency spike on dashboard ] 
                 │ (Click in Grafana)
                 ▼
[ Trace: Specific slow request in Tempo ]
                 │ (Click on TraceID)
                 ▼
[ Logs: Exact log lines for that request in Loki ]
```

### How correlation is implemented in this project:
1. **Spring Boot** intercepts an incoming HTTP request and generates a unique `TraceID`.
2. The OpenTelemetry tracing bridge automatically injects this `TraceID` into the Logging Mapped Diagnostic Context (MDC).
3. Every log statement automatically includes the trace identifier: `[traceId=3a9b...] Task created`.
4. In **Grafana**, a data source derived field rule parses `traceId` from Loki logs and turns it into a **clickable link**.
5. Clicking the link takes you directly to Tempo to view the interactive waterfall timeline of that exact call.

---

## 4. Deployed Observability Components Map

| Tool | Role | Internal Port | Access Route |
| :--- | :--- | :--- | :--- |
| **Prometheus** | Scrapes & stores numerical time-series metrics | `9090` | Internal ClusterIP (`prometheus-service:9090`) |
| **node-exporter** | Gathers node OS metrics (CPU, RAM, Disk, Net) | `9100` | Host port on each node (DaemonSet) |
| **kube-state-metrics** | Translates K8s object states into metrics | `8080` | Internal ClusterIP (`kube-state-metrics:8080`) |
| **Grafana Loki** | Cost-effective, label-indexed log store | `3100` | Internal ClusterIP (`loki-service:3100`) |
| **Promtail** | Reads `/var/log/pods` and pushes logs to Loki | `9080` | DaemonSet on all 3 nodes |
| **Event Exporter** | Captures K8s cluster events and ships to Loki | — | Background Deployment |
| **Grafana Tempo** | High-volume OpenTelemetry trace storage | `4317` (gRPC), `4318` (HTTP), `3200` | Internal ClusterIP (`tempo-service`) |
| **Grafana** | Unified visualization portal & dashboards | `3000` | `http://localhost/grafana` via Ingress |

---

## 5. Hands-on Guide: First Steps in Grafana

1. Open your browser: **`http://localhost/grafana`**
2. In the left-hand navigation, click **Dashboards** and open the **Observability** folder:
   * **`Kubernetes Nodes & Pods Health`**: Inspect memory working set across all pods and observe resource distribution between worker nodes.
   * **`Spring Boot JVM & Application Metrics`**: Trigger requests on `http://localhost` and watch live RPS, per-pod load balancing, p95/p99 latency, and HikariCP connection pool stats.
   * **`Live Logs & Cluster Events Explorer`**: Filter by `{app="backend"}` to follow live logs, or view cluster-wide events from `event-exporter`.
   * **`Distributed Traces Explorer`**: Search and analyze end-to-end API execution waterfalls down to the sub-millisecond level.

---

## 6. Essential Query Cheat Sheet

* **Prometheus Query Language — PromQL:**
  ```promql
  # Total business RPS across the entire system (excluding internal Actuator probes):
  sum(rate(http_server_requests_seconds_count{application="fullstack-backend", uri!~"/actuator.*"}[30s]))

  # Per-pod and per-node RPS breakdown (real-time load balancing):
  sum by (pod, node) (rate(http_server_requests_seconds_count{application="fullstack-backend", uri!~"/actuator.*"}[30s]))

  # Container CPU usage percentage across the namespace:
  sum(rate(container_cpu_usage_seconds_total{namespace="full-stack-app"}[5m]))
  ```

* **Loki Query Language — LogQL:**
  ```logql
  # Stream logs from all backend pods:
  {namespace="full-stack-app", app="backend"}

  # Filter logs containing specific error strings:
  {namespace="full-stack-app"} |= "ERROR"
  ```
