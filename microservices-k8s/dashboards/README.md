# Learning SLI, SLO, and SLA with a Real Microservices Cluster

*A hands-on guide using this ecommerce Kubernetes lab — Prometheus metrics, Grafana dashboards, and six services that all actually show up on the charts.*

---

Most teams talk about “99.9% uptime” without agreeing on what is being measured, who it is measured for, or what happens when the number slips. **SLIs**, **SLOs**, and **SLAs** are the vocabulary that fixes that. This README walks through the ideas like a short blog post, then shows how to practice them on the cluster you already have running from `helm-cnpg-vault-deploy.sh`.

---

## The problem reliability engineering tries to solve

You ship features on a distributed system. Something breaks at 2 a.m. Someone asks: *“Are we still within our uptime commitment?”* If the room goes quiet, you do not have a reliability practice — you have hope.

Reliability work answers three questions in order:

1. **What do we measure?** → SLI  
2. **What do we aim for internally?** → SLO  
3. **What did we promise customers?** → SLA  

The stack in this repo makes that concrete: requests hit an API gateway, fan out to Go/Node/Python services, and land as Prometheus time series you can chart in Grafana.

```
                         YOUR CUSTOMER / USER
                                    |
                                    v
    +------------------------------------------------------------------+
    |  Kind cluster: ecommerce-vault                                   |
    |                                                                  |
    |   +-------------+     +----------------------------------+     |
    |   |  Frontend   |     |  API Gateway (:9080 on host)     |     |
    |   |  :4000      |---->|  routes to microservices          |     |
    |   +-------------+     +------------------+----------------+     |
    |                                          |                       |
    |          +-------------------------------+------------------+    |
    |          |           |           |           |              |    |
    |          v           v           v           v              v    |
    |    +----------+ +----------+ +----------+ +----------+ +------+ |
    |    | product  | |  order   | |   cart   | |   user   | | pay  | |
    |    |  (Go)    | |  (Go)    | | (Node)   | | (Node)   | |(Py) | |
    |    +----+-----+ +----+-----+ +----+-----+ +----+-----+ +--+---+ |
    |         |            |            |            |          |      |
    |         +------------+------------+------------+----------+      |
    |                              |                                     |
    |                              v                                     |
    |                    +-------------------+                           |
    |                    |    Prometheus     |  scrapes /metrics       |
    |                    |    (monitoring)   |                           |
    |                    +---------+---------+                           |
    |                              |                                     |
    |                              v                                     |
    |                    +-------------------+                           |
    |                    |     Grafana       |  folder: SLI / SLO / SLA  |
    |                    |     :3030         |                           |
    |                    +-------------------+                           |
    +------------------------------------------------------------------+
```

---

## SLI — Service Level Indicator

An **SLI** is a quantified measure of some aspect of service behavior that matters to users.

It is not a target. It is the **raw signal** — the thermometer reading, not “keep the room below 25°C.”

Common SLI types:

| SLI type        | Question it answers              | Example in this lab                          |
|-----------------|----------------------------------|----------------------------------------------|
| **Availability** | What fraction of requests succeed? | `2xx / total` per service                    |
| **Latency**      | How fast are responses?          | p95 of `http_request_duration_seconds`       |
| **Error rate**   | How often do requests fail?      | `5xx / total`                                |
| **Throughput**   | How much load are we serving?    | `rate(requests_total[5m])`                   |

### Why “availability” is harder than it sounds

In production you must define **good events**. Is a `404` bad? Usually no — the system worked; the resource was missing. Is a `429` bad? Depends on whether you promised capacity. For teaching, this lab treats **HTTP 2xx as good** and **5xx as bad**, which is a clean starting point.

```
  REQUEST LIFECYCLE (availability SLI mental model)

      Client                Service                 SLI bucket
        |                      |                         |
        |---- GET /api/... --->|                         |
        |                      |---- process ----------->|
        |                      |                         |
        |<--- 200 OK ----------|                         +---> GOOD  (counts toward SLI)
        |                      |                         |
        |<--- 500 error -------|                         +---> BAD   (burns error budget)
        |                      |                         |
        |<--- 404 not found ---|                         +---> GOOD* (*policy choice)
```

Each microservice here exposes metrics differently — that is realistic, not a bug:

```
  METRIC SOURCES (all 6 services, normalized to label: service)

  product-service  ──► http_requests_total          (label: status)
  order-service    ──► http_requests_total          (label: status)
  cart-service     ──► http_requests_total          (label: status_code)
  user-service     ──► http_request_duration_seconds_count  (no counter; use histogram _count)
  payment-service  ──► flask_http_request_total     (label: status)
  notification-svc ──► flask_http_request_total     (label: status)

        \___________________________________________/
                          |
                          v
              Prometheus (kubernetes-pods job)
                          |
                          v
              Grafana dashboards unify with PromQL `or` + label_replace
```

The dashboards in `slo/` do that unification so you always see **six lines** in the “by service” panels — not just the two Go apps.

---

## SLO — Service Level Objective

An **SLO** is an internal target for an SLI over a time window.

Example: *“99.9% of requests to the ecommerce API will succeed over any rolling 30-day window.”*

```
  SLI  ─────────────────────────────────────────────►  measured reality
                                                          (Prometheus)

  SLO  ─ - - - - - - - - - - - - - - - - - - - - - ►  internal goal
                                                          (99.9% line on chart)

  SLA  ═══════════════════════════════════════════►  contractual floor
                                                          (often looser, e.g. 99.5%)
```

**SLOs are for engineering decisions.** They tell you when to stop shipping features and fix reliability. They should be **stricter than your SLA** so you have buffer before a customer-visible breach.

Default targets baked into the dashboards (changeable via Grafana variables):

| SLO            | Default in dashboards | Meaning                                      |
|----------------|----------------------|----------------------------------------------|
| Availability   | **99.9%**            | At most ~0.1% failed requests in the window  |
| Latency        | **500 ms** (p95)     | Teaching reference for tail latency          |

### Error budget — where SLOs become actionable

If your availability SLO is **99.9%**, you are allowed **0.1%** failure. That allowance is the **error budget**.

```
  ERROR BUDGET (availability)

  100%  |████████████████████████████████████████|  all requests
        |
  99.9% |██████████████████████████████████████░░|  SLO line
        |                              ▲▲▲▲▲▲▲▲░░|
        |                              budget = 0.1% failures allowed
        |
   ?%   |████████████████████░░░░░░░░░░░░░░░░░░░░|  SLI drops here
        |                    ▲
        |              budget consumed
        |
        +-- When budget hits zero: freeze risky launches, fix reliability --+
```

Dashboard **07 — Error Budget** plots consumed vs remaining budget from live SLI data.

### Burn rate — how fast you are spending budget

**Burn rate** compares your current error rate to the sustainable rate implied by the SLO.

```
  burn_rate = (current error rate) / (allowed error rate)

  burn_rate = 1   sustainable pace
  burn_rate > 1   burning budget too fast  → page someone
  burn_rate < 1   healthier than required
```

Dashboard **08 — SLO Burn Rate** visualizes this. Run `./generate-traffic.sh` and optionally load tests to watch the curve move.

---

## SLA — Service Level Agreement

An **SLA** is a **contract** with users or customers. Miss it and there may be financial or legal consequences — credits, penalties, escalations.

```
  WHO SEES WHAT

  +------------------+     tighter      +------------------+
  |       SLO        |  <────────────  |  Engineering     |
  |  (99.9% internal)|                  |  on-call, PM     |
  +------------------+                  +------------------+
          |
          | margin (buffer)
          v
  +------------------+     looser       +------------------+
  |       SLA        |  <────────────  |  Customer / legal |
  |  (99.5% contract)|                  |  invoices, trust  |
  +------------------+
          ^
          |
  +------------------+                  +------------------+
  |       SLI        |  measured by     |  Prometheus +    |
  |  (actual metric) |  ──────────────► |  Grafana         |
  +------------------+                  +------------------+
```

Dashboard **09 — SLA vs SLO** uses **99.5%** as a illustrative customer SLA vs **99.9%** internal SLO. In a real company those numbers come from legal and product — not from a YAML file.

---

## Golden signals map cleanly to SLIs

Google’s **four golden signals** are a practical menu of SLIs:

```
  GOLDEN SIGNALS  ──►  SLI IN THIS LAB

  Latency     ──►  histogram_quantile(0.95, http_request_duration_seconds_bucket)
       |
  Traffic     ──►  sum(rate(http_requests_total[5m]))  (+ flask + user variants)
       |
  Errors      ──►  5xx rate / total rate
       |
  Saturation  ──►  http_requests_in_flight, process_resident_memory_bytes
```

Dashboard **10 — Golden Signals & SLI Mapping** ties theory to those four panels with all six services.

---

## The ten dashboards (Grafana folder: `SLI / SLO / SLA`)

Each dashboard opens with a **Service coverage** row: a stat that should read **6** and a chart with six request-rate lines. That is your sanity check.

| # | Dashboard | What you learn |
|---|-----------|----------------|
| 1 | SLI, SLO & SLA — Fundamentals | Definitions + live platform SLI |
| 2 | Availability SLI | Success ratio per service |
| 3 | Latency SLI (Percentiles) | p50 / p95 across stacks |
| 4 | Error Rate SLI | 5xx ratio |
| 5 | Throughput SLI (Traffic) | RPS and saturation |
| 6 | SLO Targets & Compliance | SLI vs target, meeting SLO? |
| 7 | Error Budget | Consumed vs remaining |
| 8 | SLO Burn Rate | How fast budget drains |
| 9 | SLA vs SLO | Contract vs internal buffer |
| 10 | Golden Signals & SLI Mapping | Latency, traffic, errors, saturation |

Repository layout:

```
dashboards/
├── README.md                 ← you are here
├── deploy.sh                 ← push dashboards to Grafana
├── generate_dashboards.py    ← regenerate slo/*.json
├── generate-traffic.sh       ← exercise all services via gateway
└── slo/
    ├── 01-sli-slo-sla-fundamentals.json
    ├── 02-availability-sli.json
    └── ... (10 files total)
```

---

## Setup walkthrough (this project)

### 1. Start the cluster and apps

If you have not already:

```bash
./helm-cnpg-vault-deploy.sh
```

That gives you a Kind cluster `ecommerce-vault`, ecommerce microservices, Vault, CNPG Postgres, and (from the `monitor/` manifests) Prometheus and Grafana in the `monitoring` namespace.

### 2. Confirm monitoring is up

```bash
kubectl get pods -n monitoring
kubectl get svc -n monitoring | grep -E 'grafana|prometheus'
```

You should see `grafana` and `prometheus` Running.

### 3. Deploy the teaching dashboards

```bash
chmod +x dashboards/deploy.sh dashboards/generate-traffic.sh
./dashboards/deploy.sh
```

What happens under the hood:

```
  deploy.sh
     |
     |-- python3 generate_dashboards.py  -->  writes dashboards/slo/*.json
     |
     |-- kubectl apply ConfigMap grafana-dashboards-slo
     |
     |-- kubectl apply monitor/grafana-deployment.yaml
     |      (mounts slo/ at /var/lib/grafana/dashboards/slo)
     |
     +-- rollout restart grafana
```

### 4. Open Grafana

| UI | URL | Login |
|----|-----|-------|
| Grafana | http://localhost:3030 | `admin` / `admin123` |
| Prometheus | http://localhost:9090 | — |
| API Gateway | http://localhost:9080 | — |

In Grafana: sidebar → **Dashboards** → folder **SLI / SLO / SLA**.

Older ops dashboards live under **Operations**.

### 5. Generate traffic so every service has data

Health probes alone produce thin metrics. Hit the gateway:

```bash
./dashboards/generate-traffic.sh
```

Wait ~30 seconds for Prometheus to scrape, then refresh. The coverage panel should show **6 services reporting traffic**.

### 6. Optional — verify in Prometheus

```bash
kubectl port-forward -n monitoring svc/prometheus 9090:9090
```

Example query (same logic as the dashboards):

```promql
(
  sum(rate(http_requests_total{kubernetes_namespace="ecommerce", app=~"product-service|order-service"}[5m]))
  + sum(rate(http_requests_total{kubernetes_namespace="ecommerce", app="cart-service"}[5m]))
  + sum(rate(http_request_duration_seconds_count{kubernetes_namespace="ecommerce", service="user-service"}[5m]))
  + sum(rate(flask_http_request_total{kubernetes_namespace="ecommerce"}[5m]))
)
```

You should see non-zero rates after `generate-traffic.sh`.

---

## End-to-end data flow (one request)

```
  curl http://localhost:9080/api/v1/products
           |
           v
      api-gateway (nginx)
           |
           v
      product-service :8001
           |
           |  middleware increments http_requests_total{status="200"}
           v
      /metrics endpoint
           |
           v
      Prometheus scrape (annotation: prometheus.io/scrape=true)
           |
           v
      Grafana panel: "Request rate by service"
           |
           v
      You compare line to SLO variable (99.9%)
```

That path — **user action → metric → SLI → compare to SLO** — is the whole practice loop.

---

## Customizing SLO targets

In any dashboard, use the top variables:

- **Availability SLO (%)** — default `99.9`
- **Latency SLO (ms)** — default `500`

To change defaults permanently, edit `DEFAULT_AVAIL_SLO` and `DEFAULT_LATENCY_SLO_MS` in `generate_dashboards.py`, then:

```bash
./dashboards/deploy.sh
```

---

## A minimal study path (about 90 minutes)

1. Read sections above (concepts + diagrams).  
2. Deploy dashboards; open **01 — Fundamentals**.  
3. Run `generate-traffic.sh`; confirm six lines in coverage chart.  
4. Walk dashboards **02 → 05** (the four SLI types).  
5. **06 — Compliance**: when does SLI drop below SLO?  
6. **07 + 08**: error budget and burn rate.  
7. **09**: why SLA must be looser than SLO.  
8. **10**: map golden signals to your metrics.  

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| Only 2 services on charts | Old dashboard JSON or no traffic | Re-run `./deploy.sh`; run `generate-traffic.sh` |
| “Services reporting” &lt; 6 | Scrape missing or pod down | `kubectl get pods -n ecommerce`; check `/metrics` |
| Flat lines at zero | Prometheus not scraping | `kubectl logs -n monitoring deploy/prometheus` |
| No Grafana folder | ConfigMap not mounted | Check `kubectl describe deploy grafana -n monitoring` volumes |

---

## Further reading

- [Google SRE Book — SLI/SLO chapter](https://sre.google/sre-book/service-level-objectives/)
- [Google SRE Workbook — Alerting on SLOs](https://sre.google/workbook/alerting-on-slos/) (multi-window burn rates)
- Prometheus docs: [histogram_quantile](https://prometheus.io/docs/prometheus/latest/querying/functions/#histogram_quantile)

---

## Quick reference

```bash
# Deploy / refresh dashboards
./dashboards/deploy.sh

# Regenerate JSON only
python3 dashboards/generate_dashboards.py

# Traffic for all six services
./dashboards/generate-traffic.sh

# Grafana
open http://localhost:3030
```

**Takeaway:** SLIs tell the truth, SLOs guide engineering, SLAs bind you to customers. This lab wires all three to real metrics on a cluster you control — so the definitions are not abstract; they are lines on a chart you can explain to a teammate in five minutes.
