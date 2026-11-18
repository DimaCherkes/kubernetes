# Full-Stack Kubernetes Application with MELT Observability

A complete, production-grade cloud-native demonstration application deployed on Kubernetes across a multi-node cluster topology. Features a modern full-stack web application, persistent database, and a full **MELT** (Metrics, Events, Logs, Traces) observability stack with pre-configured Grafana dashboards.

---

## Architecture Overview

* **Frontend**: Vanilla ES6 SPA served via **Nginx 1.27 Alpine** (2 replicas) with server-side pagination controls, live node/pod identification badges, and responsive UI.
* **Backend**: **Spring Boot 3.3.5 (Java 21)** REST API (2 replicas) with Spring Data JPA, Hibernate, Micrometer Prometheus metrics, and OpenTelemetry distributed tracing.
* **Database**: **PostgreSQL 16 Alpine** deployed as a `StatefulSet` with a PersistentVolumeClaim (PVC).
* **Ingress**: **Ingress NGINX** routing:
  * `/` ➔ `frontend-service:80`
  * `/api` ➔ `backend-service:8080`
  * `/grafana` ➔ `grafana-service:3000`
* **Observability (MELT)**:
  * **M (Metrics)**: Prometheus + `node-exporter` (DaemonSet) + `kube-state-metrics`.
  * **E (Events)**: `kubernetes-event-exporter` capturing K8s cluster events into Loki.
  * **L (Logs)**: Grafana Loki + Promtail (DaemonSet reading `/var/log/pods`).
  * **T (Traces)**: Grafana Tempo collecting OpenTelemetry spans over OTLP (`:4318` HTTP).
  * **Visualization**: Grafana with 4 pre-provisioned dashboards and bidirectional Trace-to-Log linking.

---

## 1. Prerequisites

Before starting on a clean machine, ensure you have:

* **Docker** (or compatible container runtime, e.g. containerd/Podman)
* **kubectl** (Kubernetes CLI v1.26+)
* **k6** (optional, for load testing: `brew install k6` or [k6 installation guide](https://k6.io/docs/get-started/installation/))
* A Kubernetes cluster or local cluster tool (**Kind**, **Minikube**, **k3s**, or **Docker Desktop**)

---

## 2. Cluster Setup (Any Platform)

Choose one of the following cluster options:

### Option A: Kind (Recommended for local 3-node testing)

1. Create a cluster configuration file named `kind-cluster.yaml`:
   ```yaml
   kind: Cluster
   apiVersion: kind.x-k8s.io/v1alpha4
   name: local-cluster
   nodes:
     - role: control-plane
       kubeadmConfigPatches:
         - |
           kind: InitConfiguration
           nodeRegistration:
             kubeletExtraArgs:
               node-labels: "ingress-ready=true"
       extraPortMappings:
         - containerPort: 80
           hostPort: 80
           protocol: TCP
         - containerPort: 443
           hostPort: 443
           protocol: TCP
     - role: worker
     - role: worker
   ```
2. Create the 3-node cluster:
   ```bash
   kind create cluster --config kind-cluster.yaml
   ```

### Option B: Minikube (Multi-node)

```bash
minikube start --nodes 3 --driver=docker
minikube addons enable ingress
```
*(When using Minikube, run `minikube tunnel` in a separate terminal window to bind port 80).*

### Option C: Docker Desktop Kubernetes

Enable Kubernetes in Docker Desktop Preferences ➔ Kubernetes ➔ **Enable Kubernetes**.

### Option D: Managed Cloud Cluster (GKE / EKS / AKS / Bare-Metal)

Ensure your `kubectl` context points to your cluster:
```bash
kubectl get nodes
```

---

## 3. Install Ingress NGINX Controller

If your cluster does not already have an Ingress Controller installed:

* **For Kind / Docker Desktop / Bare-Metal:**
  ```bash
  kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
  ```
* **For Minikube:**
  ```bash
  minikube addons enable ingress
  ```
* **Wait until Ingress Controller is Ready:**
  ```bash
  kubectl wait --namespace ingress-nginx \
    --for=condition=ready pod \
    --selector=app.kubernetes.io/component=controller \
    --timeout=120s
  ```

---

## 4. Build and Load Container Images

From the `full-stack-app/` root directory:

### Step 1: Build Docker Images
```bash
docker build -t fullstack-backend:v5 ./backend
docker build -t fullstack-frontend:v5 ./frontend
```

### Step 2: Load Images into Your Cluster

* **If using Kind:**
  ```bash
  kind load docker-image fullstack-backend:v5 --name local-cluster
  kind load docker-image fullstack-frontend:v5 --name local-cluster
  ```
* **If using Minikube:**
  ```bash
  minikube image load fullstack-backend:v5
  minikube image load fullstack-frontend:v5
  ```
* **If using Docker Desktop:**
  *(Images are shared automatically via Docker daemon — no load command required).*
* **If using a Remote / Cloud Cluster (EKS / GKE / AKS):**
  Tag and push the images to your container registry (Docker Hub, GHCR, ECR, GCR) and update the `image:` fields in `k8s/04-backend.yaml` and `k8s/05-frontend.yaml`.

---

## 4b. Install the ECK Operator (Elasticsearch)

Full-text task search is backed by a 3-node Elasticsearch cluster managed by the
[Elastic Cloud on Kubernetes (ECK)](https://www.elastic.co/docs/deploy-manage/deploy/cloud-on-k8s) operator
(an implementation of the [Kubernetes Operator pattern](https://kubernetes.io/docs/concepts/extend-kubernetes/operator/)).
Install the CRDs and the operator **before** applying `k8s/`:

```bash
kubectl create -f https://download.elastic.co/downloads/eck/3.5.0/crds.yaml
kubectl apply  -f https://download.elastic.co/downloads/eck/3.5.0/operator.yaml
kubectl -n elastic-system rollout status sts/elastic-operator
```

Related manifests:
* `k8s/03b-elasticsearch.yaml` – `Elasticsearch` CR `task-search` (8.17.10, 3 nodes, 1Gi RAM each, `podAntiAffinity` → 1 pod per node).
* `k8s/03c-elasticsearch-exporter.yaml` – Prometheus exporter (TLS + `elastic` user), scraped by job `elasticsearch`; Grafana dashboard **Elasticsearch (ECK) Cluster**.
* The backend uses the ECK-generated secrets `task-search-es-elastic-user` (password) and `task-search-es-http-certs-public` (CA) and the `k8s` Spring profile (HTTPS + PEM SSL bundle).

Search API:
* `GET /api/tasks/search?q=<text>&status=all|active|completed&page=0&size=20` – fuzzy search on title/description with `<mark>` highlights; `searchSource` is `elasticsearch` or `postgresql-fallback` (when ES is unavailable).
* `POST /api/tasks/reindex` – rebuild the `tasks` index from PostgreSQL (also done on startup). CRUD operations are written through to ES synchronously.

Check the cluster:
```bash
kubectl get elasticsearch -n full-stack-app        # HEALTH green, NODES 3
kubectl get pods -n full-stack-app -o wide -l elasticsearch.k8s.elastic.co/cluster-name=task-search
```

---

## 5. Deploy to Kubernetes

Deploy all 14 Kubernetes manifests. They are numbered in logical dependency order:

```bash
# Option 1: Apply all manifests at once
kubectl apply -f k8s/

# Option 2: Apply in sequential order
kubectl apply -f k8s/00-namespace.yaml
kubectl apply -f k8s/01-secret.yaml
kubectl apply -f k8s/02-configmap.yaml
kubectl apply -f k8s/03-postgres.yaml
kubectl apply -f k8s/04-backend.yaml
kubectl apply -f k8s/05-frontend.yaml
kubectl apply -f k8s/06-ingress.yaml
kubectl apply -f k8s/07-observability-rbac.yaml
kubectl apply -f k8s/08-loki.yaml
kubectl apply -f k8s/09-promtail.yaml
kubectl apply -f k8s/10-tempo.yaml
kubectl apply -f k8s/11-prometheus.yaml
kubectl apply -f k8s/12-event-exporter.yaml
kubectl apply -f k8s/13-grafana.yaml
```

### Verify Deployment Readiness

Wait for all 17 pods across application and observability workloads to become `Running` (1/1):

```bash
kubectl wait --namespace full-stack-app \
  --for=condition=ready pod \
  --all \
  --timeout=300s
```

Check pod status:
```bash
kubectl get pods -n full-stack-app -o wide
```

Expected output:
```text
NAME                                READY   STATUS    RESTARTS   AGE
backend-67f7cf687f-8x5vf            1/1     Running   0          5m
backend-67f7cf687f-ztbt7            1/1     Running   0          5m
event-exporter-577778b874-v7k72     1/1     Running   0          5m
frontend-696788dbd9-8x798           1/1     Running   0          5m
frontend-696788dbd9-z4bkj           1/1     Running   0          5m
grafana-557867cb7c-c22gs            1/1     Running   0          5m
kube-state-metrics-7598c74577-m888  1/1     Running   0          5m
loki-0                              1/1     Running   0          5m
node-exporter-4mscz                 1/1     Running   0          5m
node-exporter-g5j6p                 1/1     Running   0          5m
node-exporter-vgf9d                 1/1     Running   0          5m
postgres-0                          1/1     Running   0          5m
prometheus-85c88b9c48-2qskz         1/1     Running   0          5m
promtail-7kkwj                      1/1     Running   0          5m
promtail-f6z84                      1/1     Running   0          5m
promtail-p9smb                      1/1     Running   0          5m
tempo-6644fcf776-79q8n              1/1     Running   0          5m
```

---

## 6. Accessing the Application

| Service | URL / Access Command | Description |
| :--- | :--- | :--- |
| **Task Manager Web App** | [http://localhost](http://localhost) | Interactive SPA with live pod badges and pagination |
| **REST API** | [http://localhost/api/tasks](http://localhost/api/tasks) | Paginated endpoints (`?page=0&size=20&filter=all`) |
| **Grafana Dashboards** | [http://localhost/grafana](http://localhost/grafana) | Pre-configured observability dashboards (Anonymous Admin enabled) |
| **PostgreSQL CLI** | `kubectl port-forward -n full-stack-app svc/postgres-service 5432:5432` | Host: `localhost:5432`, DB: `taskdb`, User: `postgres`, Pass: `postgrespassword` |

---

## 7. Pre-Provisioned Grafana Dashboards

Navigate to **Dashboards ➔ Observability**:

1. **`Spring Boot JVM & Application Metrics`**:
   * **Total System RPS (All Pods)**: Aggregate incoming request rate (req/s).
   * **Per-Pod Current RPS**: Real-time load balance comparison side-by-side.
   * **Per-Pod RPS Breakdown Over Time**: Individual curves showing how traffic is distributed across worker nodes.
   * **Latency (p95 & p99)**: Millisecond-level request durations.
   * **HikariCP Connection Pool**: Active, idle, and max database connections.
   * **JVM Heap & Live Threads**: Memory allocation and garbage collection pause rates.
2. **`Kubernetes Nodes & Pods Health`**:
   * Node CPU & RAM utilization (%) across all nodes in the cluster.
   * Pod phase status and restart counters.
   * Per-pod CPU (mCPU) and Memory Working Set (MB).
3. **`Live Logs & Cluster Events Explorer`**:
   * Real-time logs from Loki with interactive **TraceID links** leading straight to Tempo waterfalls.
   * Cluster-wide lifecycle events streamed by `kubernetes-event-exporter`.
4. **`Distributed Traces Explorer`**:
   * Tempo search by service name (`fullstack-backend`) with end-to-end execution breakdown.

---

## 8. Run Load & Stress Tests (k6)

To observe real-time autoscaling metrics, latency spikes, and log/trace generation:

```bash
# Execute the automated k6 stress script:
./load-testing/run.sh

# Or invoke directly with the k6 CLI:
k6 run load-testing/load-test.js
```

### Load Profile:
* **Stage 1 (0–15s)**: Ramp-up to 15 VUs (~40–60 RPS).
* **Stage 2 (15–60s)**: Sustained stress at 30 VUs (~100–150 RPS).
* **Stage 3 (60–75s)**: Peak spike to 45 VUs to test latency thresholds.
* **Stage 4 (75–90s)**: Cooldown to 0 VUs to observe queue recovery.

---

## 9. Teardown / Cleanup

To delete all workloads, services, and release persistent volume claims:

```bash
# Delete all resources in namespace full-stack-app
kubectl delete namespace full-stack-app

# If using Kind and you want to delete the whole cluster:
kind delete cluster --name local-cluster
```

---

## Documentation Links

* [Architecture & Topology Diagrams](docs/ARCHITECTURE.md)
* [Observability for Beginners (M.E.L.T. Guide)](docs/OBSERVABILITY_FOR_BEGINNERS.md)
* [Load Testing Details](load-testing/README.md)
