# Full-Stack Kubernetes & MELT Observability Architecture

This document describes the complete architecture of the deployed system, the physical/virtual node topology, network routing, and architectural diagrams across all layers.

---

## 1. Cluster Node Topology (Node Infrastructure)

The cluster is deployed on a local multi-node architecture consisting of **3 nodes**:

```
                        ┌─────────────────────────────────────┐
                        │   desktop-control-plane (Control)   │
                        │    Control Plane / API Server       │
                        │   (Taint: NoSchedule for app)       │
                        └──────────────────┬──────────────────┘
                                           │
                 ┌─────────────────────────┴─────────────────────────┐
                 ▼                                                   ▼
┌─────────────────────────────────┐                 ┌─────────────────────────────────┐
│         desktop-worker          │                 │        desktop-worker2          │
│      (Worker Node 1)            │                 │      (Worker Node 2)            │
│  - backend-pod-1 (Spring Boot)  │                 │  - backend-pod-2 (Spring Boot)  │
│  - frontend-pod-1 (Nginx)       │                 │  - frontend-pod-2 (Nginx)       │
│  - postgres-0 (StatefulSet+PVC) │                 │  - prometheus-pod               │
│  - loki-pod                     │                 │  - grafana-pod                  │
│  - tempo-pod                    │                 │  - kube-state-metrics           │
│  - event-exporter-pod           │                 │  - node-exporter (DaemonSet)    │
│  - node-exporter (DaemonSet)    │                 │  - promtail (DaemonSet)         │
│  - promtail (DaemonSet)         │                 │                                 │
└─────────────────────────────────┘                 └─────────────────────────────────┘
```

* **`desktop-control-plane`**: Master/Control Plane node (runs `etcd`, `kube-apiserver`, `kube-scheduler`, `kube-controller-manager`). Tainted with `NoSchedule` so application workloads are not scheduled on it.
* **`desktop-worker`** & **`desktop-worker2`**: Worker nodes. Application replicas (`backend` and `frontend`) are evenly distributed by the Kubernetes scheduler across both workers to ensure high availability and resilience.
* **`node-exporter` & `promtail` Agents**: Deployed as a `DaemonSet`, automatically running exactly one pod on **every node** in the cluster.

---

## 2. Component Diagram

The component model illustrates the logical separation between the core business application and the observability subsystem.

```mermaid
flowchart TD
    subgraph Client["Client Tier"]
        Browser["User Web Browser"]
        AdminBrowser["DevOps / Engineer Browser"]
    end

    subgraph Edge["Cluster Edge Gateway"]
        IngressController["Ingress Controller (NGINX)"]
    end

    Browser -->|"HTTP /"| IngressController
    Browser -->|"REST API /api/tasks"| IngressController
    AdminBrowser -->|"UI /grafana"| IngressController

    subgraph AppNamespace["Namespace: full-stack-app"]
        direction TB

        subgraph CoreWorkloads["Core Business Workloads"]
            SvcFE["frontend-service:80"]
            SvcBE["backend-service:8080"]
            SvcDB["postgres-service:5432"]

            PodFE["Frontend (Nginx + SPA)"]
            PodBE["Backend (Spring Boot 3 + OTel)"]
            PodDB[("PostgreSQL 16")]

            SvcFE --> PodFE
            SvcBE --> PodBE
            SvcDB --> PodDB
            PodBE -->|"JDBC / SQL"| SvcDB
        end

        subgraph ObservabilityStack["MELT Observability Stack"]
            Prometheus["Prometheus (Metrics Server)"]
            Loki[("Grafana Loki (Log Aggregator)")]
            Tempo[("Grafana Tempo (OTLP Trace Store)")]
            Grafana["Grafana 11.0 (Visualization)"]

            NodeExp["node-exporter (DaemonSet)"]
            KSM["kube-state-metrics"]
            Promtail["promtail (DaemonSet)"]
            EventExp["kubernetes-event-exporter"]
        end
    end

    IngressController -->|"Route /"| SvcFE
    IngressController -->|"Route /api"| SvcBE
    IngressController -->|"Route /grafana"| Grafana

    %% Telemetry Flows
    PodBE -.->|"/actuator/prometheus"| Prometheus
    NodeExp -.->|"Node Metrics (CPU, RAM, Disk)"| Prometheus
    KSM -.->|"K8s Resource State Metrics"| Prometheus

    Promtail -.->|"Log Stream from /var/log/pods"| Loki
    EventExp -.->|"K8s Cluster Events Stream"| Loki

    PodBE -.->|"OTLP Spans via HTTP :4318"| Tempo

    Grafana -->|"PromQL Queries"| Prometheus
    Grafana -->|"LogQL Queries"| Loki
    Grafana -->|"TraceQL Queries"| Tempo
```

---

## 3. Deployment Diagram

Demonstrates how declarative Kubernetes manifests map to physical pods, services, and persistent disk storage.

```mermaid
flowchart TB
    subgraph Host["Host Machine (macOS)"]
        HostPort80["localhost:80 / 443"]
        HostDisk[("Host Filesystem (Persistent Volumes)")]
    end

    subgraph K8s["Kubernetes Cluster"]
        direction TB

        Ingress["Ingress: app-ingress"]
        HostPort80 --> Ingress

        subgraph SvcLayer["Network Tier (ClusterIP Services)"]
            SvcFE["Service: frontend-service (port 80)"]
            SvcBE["Service: backend-service (port 8080)"]
            SvcDB["Service: postgres-service (port 5432)"]
            SvcProm["Service: prometheus-service (port 9090)"]
            SvcLoki["Service: loki-service (port 3100)"]
            SvcTempo["Service: tempo-service (ports 4317, 4318, 3200)"]
            SvcGraf["Service: grafana-service (port 3000)"]
        end

        Ingress -->|"Path: /"| SvcFE
        Ingress -->|"Path: /api"| SvcBE
        Ingress -->|"Path: /grafana"| SvcGraf

        subgraph PodsLayer["Pod Tier (Workloads)"]
            PodFE1["Pod: frontend-replica-1"]
            PodFE2["Pod: frontend-replica-2"]
            SvcFE --> PodFE1 & PodFE2

            PodBE1["Pod: backend-replica-1"]
            PodBE2["Pod: backend-replica-2"]
            SvcBE --> PodBE1 & PodBE2

            PodDB["Pod: postgres-0 (StatefulSet)"]
            SvcDB --> PodDB

            PodProm["Pod: prometheus"]
            SvcProm --> PodProm

            PodLoki["Pod: loki"]
            SvcLoki --> PodLoki

            PodTempo["Pod: tempo"]
            SvcTempo --> PodTempo

            PodGraf["Pod: grafana"]
            SvcGraf --> PodGraf
        end

        subgraph StorageLayer["Persistent Storage Tier (PVCs)"]
            PVC_DB[("PVC: postgres-data-postgres-0 (1Gi)")]
            PVC_Loki[("PVC: loki-data (2Gi)")]
            PVC_Tempo[("PVC: tempo-data (2Gi)")]
            PVC_Prom[("PVC: prometheus-data (2Gi)")]
            PVC_Graf[("PVC: grafana-storage (1Gi)")]
        end

        PodDB --- PVC_DB
        PodLoki --- PVC_Loki
        PodTempo --- PVC_Tempo
        PodProm --- PVC_Prom
        PodGraf --- PVC_Graf

        PVC_DB & PVC_Loki & PVC_Tempo & PVC_Prom & PVC_Graf --- HostDisk
    end
```

---

## 4. Request & Telemetry Sequence Diagram

Illustrates the end-to-end flow of a single user action (e.g. clicking "Add Task" in the web UI) and how all 4 telemetry signals (**MELT**) are generated simultaneously.

```mermaid
sequenceDiagram
    autonumber
    actor User as User (Web Browser)
    participant Ingress as Ingress NGINX
    participant FE as Frontend Pod (Nginx)
    participant BE as Backend Pod (Spring Boot)
    participant DB as PostgreSQL
    participant Tempo as Grafana Tempo
    participant Promtail as Promtail DaemonSet
    participant Loki as Grafana Loki
    participant Prom as Prometheus
    participant Grafana as Grafana Dashboard

    %% 1. Initial Page Load
    User->>Ingress: GET http://localhost/
    Ingress->>FE: Proxy request to frontend-service:80
    FE-->>User: 200 OK (HTML/JS/CSS + X-Frontend-Pod header)

    %% 2. Task Creation via REST API with Tracing
    User->>Ingress: POST /api/tasks (JSON Payload)
    Ingress->>BE: Proxy request to backend-service:8080
    
    activate BE
    Note over BE: Generate TraceID & SpanID (OpenTelemetry)<br/>Inject TraceID into logging context (MDC)
    
    BE->>DB: INSERT INTO tasks (...)
    DB-->>BE: Commit OK (id=1)
    
    Note over BE: Output structured log to stdout:<br/>[traceId=3a9b...] Task created
    
    BE-->>Ingress: 201 Created (JSON + headers X-Backend-Pod, traceId)
    deactivate BE
    
    Ingress-->>User: 201 Created (UI updates live badges and paginated task list)

    %% 3. Async Telemetry: Traces
    critical Tracing (Traces - T)
        BE-)Tempo: Async export span via OTLP (HTTP :4318)
    end

    %% 4. Async Telemetry: Logs & Events
    critical Log & Event Ingestion (Logs - L, Events - E)
        Promtail-)Loki: Read container stdout from /var/log/pods -> Push to Loki
        Note over Loki: Automatic Trace-to-Log linking using TraceID regex
    end

    %% 5. Periodic Metric Scraping (Metrics - M)
    critical Metric Collection (Metrics - M)
        Prom->>BE: Periodic scrape GET /actuator/prometheus (every 5s)
        BE-->>Prom: Metrics: http_server_requests_seconds, jvm_memory_used, ...
    end

    %% 6. Visualization in Grafana
    User->>Grafana: Open http://localhost/grafana
    Grafana->>Prom: PromQL: Total RPS & Per-Pod load balancing
    Grafana->>Loki: LogQL: Backend container logs with trace links
    Grafana->>Tempo: TraceQL: Waterfall breakdown by TraceID
```

---

## 5. Network Communication & Port Matrix

| Source | Destination | Target Port | Protocol | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **External Client** | Ingress NGINX | `80` (HTTP) | TCP / HTTP | Ingress gateway entrypoint |
| **Ingress NGINX** | `frontend-service` | `80` | TCP / HTTP | Static HTML/CSS/JS SPA routing |
| **Ingress NGINX** | `backend-service` | `8080` | TCP / HTTP | REST API (`/api/tasks`) |
| **Ingress NGINX** | `grafana-service` | `3000` | TCP / HTTP | Observability dashboard (`/grafana`) |
| **Backend Pod** | `postgres-service` | `5432` | TCP / PostgreSQL | HikariCP database connection pool |
| **Backend Pod** | `tempo-service` | `4318` | TCP / HTTP (OTLP) | OpenTelemetry distributed trace spans |
| **Prometheus** | `backend-service` | `8080` | TCP / HTTP | Actuator metrics (`/actuator/prometheus`) |
| **Prometheus** | `node-exporter` | `9100` | TCP / HTTP | Node hardware metrics (CPU, RAM, Disk) |
| **Prometheus** | `kube-state-metrics`| `8080` | TCP / HTTP | Kubernetes resource state metrics |
| **Promtail** | `loki-service` | `3100` | TCP / HTTP | Pushing `/var/log/pods` container logs |
| **Event Exporter** | `loki-service` | `3100` | TCP / HTTP | Pushing Kubernetes cluster events |
| **Grafana** | `prometheus-service`| `9090` | TCP / HTTP | Prometheus data source queries |
| **Grafana** | `loki-service` | `3100` | TCP / HTTP | Loki data source queries |
| **Grafana** | `tempo-service` | `3200` | TCP / HTTP | Tempo data source queries |
