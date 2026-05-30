#!/usr/bin/env python3
"""Generate 10 Grafana dashboards for SLI / SLO / SLA teaching (all 6 microservices)."""

from __future__ import annotations

import json
import shutil
from pathlib import Path

OUT_DIR = Path(__file__).parent / "slo"
LEGACY_DIR = Path(__file__).parent
DS = {"type": "prometheus", "uid": "${datasource}"}

NS = 'kubernetes_namespace="ecommerce"'
RI = "[$__rate_interval]"
GO = "product-service|order-service"
FLASK = "payment-service|notification-service"
ALL = f"{GO}|cart-service|{FLASK}|user-service"
SVC_FILTER = 'service=~"$service"'

DEFAULT_AVAIL_SLO = "99.9"
DEFAULT_LATENCY_SLO_MS = "500"


def lr_app(expr: str) -> str:
    return f'label_replace({expr}, "service", "$1", "app", "(.*)")'


# --- Unified metrics: Go (status), Cart (status_code), User (histogram _count), Flask (status) ---

def _good_rate_inner() -> str:
    return f"""(
  {lr_app(f'sum(rate(http_requests_total{{{NS}, app=~"{GO}", status=~"2.."}} {RI})) by (app)')}
  or {lr_app(f'sum(rate(http_requests_total{{{NS}, app="cart-service", status_code=~"2.."}} {RI})) by (app)')}
  or sum(rate(http_request_duration_seconds_count{{{NS}, service="user-service", status_code=~"2.."}} {RI})) by (service)
  or {lr_app(f'sum(rate(flask_http_request_total{{{NS}, app=~"{FLASK}", status=~"2.."}} {RI})) by (app)')}
)"""


def _total_rate_inner() -> str:
    return f"""(
  {lr_app(f'sum(rate(http_requests_total{{{NS}, app=~"{GO}"}} {RI})) by (app)')}
  or {lr_app(f'sum(rate(http_requests_total{{{NS}, app="cart-service"}} {RI})) by (app)')}
  or sum(rate(http_request_duration_seconds_count{{{NS}, service="user-service"}} {RI})) by (service)
  or {lr_app(f'sum(rate(flask_http_request_total{{{NS}, app=~"{FLASK}"}} {RI})) by (app)')}
)"""


def _bad_rate_inner() -> str:
    return f"""(
  {lr_app(f'sum(rate(http_requests_total{{{NS}, app=~"{GO}", status=~"5.."}} {RI})) by (app)')}
  or {lr_app(f'sum(rate(http_requests_total{{{NS}, app="cart-service", status_code=~"5.."}} {RI})) by (app)')}
  or sum(rate(http_request_duration_seconds_count{{{NS}, service="user-service", status_code=~"5.."}} {RI})) by (service)
  or {lr_app(f'sum(rate(flask_http_request_total{{{NS}, app=~"{FLASK}", status=~"5.."}} {RI})) by (app)')}
)"""


def _p95_inner(q: str = "0.95") -> str:
    return f"""(
  {lr_app(f'histogram_quantile({q}, sum(rate(http_request_duration_seconds_bucket{{{NS}, app=~"{GO}|cart-service"}} {RI})) by (le, app))')}
  or histogram_quantile({q}, sum(rate(http_request_duration_seconds_bucket{{{NS}, service="user-service"}} {RI})) by (le, service))
  or {lr_app(f'histogram_quantile({q}, sum(rate(flask_http_request_duration_seconds_bucket{{{NS}, app=~"{FLASK}"}} {RI})) by (le, app))')}
)"""


GOOD_BY_SVC = _good_rate_inner()
TOTAL_BY_SVC = _total_rate_inner()
BAD_BY_SVC = _bad_rate_inner()
P95_BY_SVC = _p95_inner("0.95")
P50_BY_SVC = _p95_inner("0.50")

AVAIL_BY_SVC = f"{GOOD_BY_SVC} / {TOTAL_BY_SVC}"
ERR_BY_SVC = f"{BAD_BY_SVC} / {TOTAL_BY_SVC}"
RPS_BY_SVC = TOTAL_BY_SVC

AVAIL_PLATFORM = f"sum({GOOD_BY_SVC}) / sum({TOTAL_BY_SVC})"
ERR_PLATFORM = f"sum({BAD_BY_SVC}) / sum({TOTAL_BY_SVC})"
RPS_PLATFORM = f"sum({TOTAL_BY_SVC})"

SVC_WITH_DATA = f"count(({TOTAL_BY_SVC}) > 0)"
SLO_TARGET = "${slo_availability:raw} / 100"
ERROR_BUDGET = f"1 - ({SLO_TARGET})"
BURN_RATE = f"({ERR_PLATFORM}) / ({ERROR_BUDGET})"

SATURATION_BY_SVC = f"""(
  {lr_app(f'sum(http_requests_in_flight{{{NS}, app=~"{GO}|cart-service"}}) by (app)')}
  or label_replace(
      sum(nodejs_active_requests_total{{{NS}, app="user-service"}}) by (app),
      "service", "user-service", "", ""
    )
)"""


def panel_text(title: str, content: str, grid: dict, panel_id: int) -> dict:
    return {
        "id": panel_id,
        "title": title,
        "type": "text",
        "gridPos": grid,
        "options": {"mode": "markdown", "content": content},
    }


def panel_row(title: str, grid: dict, panel_id: int) -> dict:
    return {"id": panel_id, "title": title, "type": "row", "gridPos": grid, "collapsed": False}


def panel_timeseries(
    title: str,
    expr: str,
    grid: dict,
    panel_id: int,
    *,
    unit: str = "short",
    legend: str = "{{service}}",
    description: str = "",
) -> dict:
    return {
        "id": panel_id,
        "title": title,
        "type": "timeseries",
        "gridPos": grid,
        "datasource": DS,
        "description": description,
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "palette-classic"},
                "custom": {"drawStyle": "line", "lineWidth": 1, "fillOpacity": 12, "showPoints": "never"},
                "unit": unit,
            },
            "overrides": [],
        },
        "options": {
            "legend": {"displayMode": "table", "placement": "bottom", "calcs": ["mean", "lastNotNull", "max"]},
            "tooltip": {"mode": "multi"},
        },
        "targets": [{"expr": expr, "legendFormat": legend, "refId": "A"}],
    }


def panel_stat(
    title: str,
    expr: str,
    grid: dict,
    panel_id: int,
    *,
    unit: str = "percentunit",
    description: str = "",
) -> dict:
    return {
        "id": panel_id,
        "title": title,
        "type": "stat",
        "gridPos": grid,
        "datasource": DS,
        "description": description,
        "fieldConfig": {
            "defaults": {"color": {"mode": "thresholds"}, "unit": unit, "decimals": 3},
            "overrides": [],
        },
        "options": {
            "colorMode": "value",
            "graphMode": "area",
            "reduceOptions": {"calcs": ["lastNotNull"], "fields": "", "values": False},
        },
        "targets": [{"expr": expr, "refId": "A"}],
    }


def panel_gauge(title: str, expr: str, grid: dict, panel_id: int, *, unit: str = "percentunit") -> dict:
    return {
        "id": panel_id,
        "title": title,
        "type": "gauge",
        "gridPos": grid,
        "datasource": DS,
        "fieldConfig": {
            "defaults": {
                "color": {"mode": "thresholds"},
                "unit": unit,
                "min": 0,
                "max": 1 if unit == "percentunit" else None,
                "thresholds": {
                    "mode": "absolute",
                    "steps": [
                        {"color": "red", "value": None},
                        {"color": "yellow", "value": 0.995},
                        {"color": "green", "value": 0.999},
                    ],
                },
            },
            "overrides": [],
        },
        "options": {"reduceOptions": {"calcs": ["lastNotNull"]}},
        "targets": [{"expr": expr, "refId": "A"}],
    }


def coverage_panels(start_id: int, y: int) -> list:
    """Row + stats showing all 6 services emit request metrics."""
    panels = [
        panel_row("Service coverage (6 microservices)", {"h": 1, "w": 24, "x": 0, "y": y}, start_id),
        panel_stat(
            "Services reporting traffic",
            SVC_WITH_DATA,
            {"h": 4, "w": 4, "x": 0, "y": y + 1},
            start_id + 1,
            unit="short",
            description="Should be 6: product, order, cart, user, payment, notification.",
        ),
        panel_timeseries(
            "Request rate by service (verify 6 lines)",
            RPS_BY_SVC,
            {"h": 8, "w": 20, "x": 4, "y": y + 1},
            start_id + 2,
            unit="reqps",
            description="Each line = one microservice. If fewer than 6, check Prometheus scrape targets.",
        ),
    ]
    return panels


def base_dashboard(uid: str, title: str, tags: list[str], panels: list) -> dict:
    return {
        "annotations": {"list": []},
        "editable": True,
        "fiscalYearStartMonth": 0,
        "graphTooltip": 1,
        "id": None,
        "links": [],
        "liveNow": False,
        "panels": panels,
        "refresh": "30s",
        "schemaVersion": 39,
        "tags": tags + ["slo-folder"],
        "templating": {
            "list": [
                {
                    "name": "datasource",
                    "type": "datasource",
                    "query": "prometheus",
                    "current": {},
                    "label": "Datasource",
                },
                {
                    "name": "service",
                    "type": "query",
                    "datasource": DS,
                    "query": f'label_values(up{{{NS}, app=~"{ALL}"}}, app)',
                    "refresh": 2,
                    "includeAll": True,
                    "multi": True,
                    "allValue": ".*",
                    "current": {"text": "All", "value": "$__all"},
                    "label": "Service",
                },
                {
                    "name": "slo_availability",
                    "type": "constant",
                    "label": "Availability SLO (%)",
                    "query": DEFAULT_AVAIL_SLO,
                },
                {
                    "name": "slo_latency_ms",
                    "type": "constant",
                    "label": "Latency SLO (ms)",
                    "query": DEFAULT_LATENCY_SLO_MS,
                },
            ]
        },
        "time": {"from": "now-6h", "to": "now"},
        "timezone": "browser",
        "title": title,
        "uid": uid,
        "version": 2,
    }


def dashboard_01() -> dict:
    intro = """# SLI, SLO & SLA — Fundamentals

| Term | Definition |
|------|------------|
| **SLI** | Measured signal (availability, latency, errors) |
| **SLO** | Internal target for an SLI |
| **SLA** | Customer-facing commitment |

**Metrics in this cluster** (all 6 services):

| Service | Stack | Request metrics |
|---------|-------|-----------------|
| product-service, order-service | Go | `http_requests_total` (`status`) |
| cart-service | Node (custom) | `http_requests_total` (`status_code`) |
| user-service | Node (prom-bundle) | `http_request_duration_seconds_count` (`status_code`) |
| payment-service, notification-service | Flask | `flask_http_request_total` (`status`) |
"""
    return base_dashboard(
        "slo-01-fundamentals",
        "SLI, SLO & SLA — Fundamentals",
        ["education", "sli", "slo", "sla"],
        [
            *coverage_panels(1, 0),
            panel_text("Concepts", intro, {"h": 9, "w": 24, "x": 0, "y": 9}, 10),
            panel_stat("Platform availability SLI", AVAIL_PLATFORM, {"h": 5, "w": 8, "x": 0, "y": 18}, 20),
            panel_stat("Platform error rate SLI", ERR_PLATFORM, {"h": 5, "w": 8, "x": 8, "y": 18}, 21, unit="percentunit"),
            panel_stat("Availability SLO target", SLO_TARGET, {"h": 5, "w": 8, "x": 16, "y": 18}, 22, unit="percentunit"),
        ],
    )


def dashboard_02() -> dict:
    return base_dashboard(
        "slo-02-availability-sli",
        "Availability SLI",
        ["education", "sli", "availability"],
        [
            *coverage_panels(1, 0),
            panel_text(
                "Availability SLI",
                "**Formula:** `2xx_requests / total_requests` per service, then aggregated.\n\nEvery line below should map to one microservice.",
                {"h": 3, "w": 24, "x": 0, "y": 9},
                10,
            ),
            panel_timeseries("Availability SLI — by service", AVAIL_BY_SVC, {"h": 9, "w": 24, "x": 0, "y": 12}, 11, unit="percentunit"),
            panel_timeseries("Availability SLI — platform", AVAIL_PLATFORM, {"h": 7, "w": 12, "x": 0, "y": 21}, 12, unit="percentunit", legend="platform"),
            panel_gauge("Current platform availability", AVAIL_PLATFORM, {"h": 7, "w": 6, "x": 12, "y": 21}, 13),
            panel_stat("SLO target", SLO_TARGET, {"h": 7, "w": 6, "x": 18, "y": 21}, 14, unit="percentunit"),
        ],
    )


def dashboard_03() -> dict:
    return base_dashboard(
        "slo-03-latency-sli",
        "Latency SLI (Percentiles)",
        ["education", "sli", "latency"],
        [
            *coverage_panels(1, 0),
            panel_text(
                "Latency SLI",
                "Histograms from Go, cart, user (express-prom-bundle), and Flask. **Six services** should appear in p95 panel.",
                {"h": 3, "w": 24, "x": 0, "y": 9},
                10,
            ),
            panel_timeseries("p50 latency by service", P50_BY_SVC, {"h": 8, "w": 12, "x": 0, "y": 12}, 11, unit="s"),
            panel_timeseries("p95 latency by service", P95_BY_SVC, {"h": 8, "w": 12, "x": 12, "y": 12}, 12, unit="s"),
            panel_stat("Worst p95 (any service)", f"max({P95_BY_SVC})", {"h": 6, "w": 12, "x": 0, "y": 20}, 13, unit="s"),
            panel_stat("Latency SLO (seconds)", "${slo_latency_ms:raw} / 1000", {"h": 6, "w": 12, "x": 12, "y": 20}, 14, unit="s"),
        ],
    )


def dashboard_04() -> dict:
    return base_dashboard(
        "slo-04-error-rate-sli",
        "Error Rate SLI",
        ["education", "sli", "errors"],
        [
            *coverage_panels(1, 0),
            panel_timeseries("Error rate by service", ERR_BY_SVC, {"h": 9, "w": 24, "x": 0, "y": 9}, 10, unit="percentunit"),
            panel_timeseries("Platform error rate", ERR_PLATFORM, {"h": 7, "w": 24, "x": 0, "y": 18}, 11, unit="percentunit", legend="platform"),
        ],
    )


def dashboard_05() -> dict:
    return base_dashboard(
        "slo-05-throughput-sli",
        "Throughput SLI (Traffic)",
        ["education", "sli", "throughput"],
        [
            *coverage_panels(1, 0),
            panel_timeseries("Request rate by service", RPS_BY_SVC, {"h": 9, "w": 24, "x": 0, "y": 9}, 10, unit="reqps"),
            panel_timeseries("Platform RPS", RPS_PLATFORM, {"h": 7, "w": 12, "x": 0, "y": 18}, 11, unit="reqps", legend="platform"),
            panel_timeseries(
                "Saturation — in-flight / active requests",
                SATURATION_BY_SVC,
                {"h": 7, "w": 12, "x": 12, "y": 18},
                12,
            ),
        ],
    )


def dashboard_06() -> dict:
    return base_dashboard(
        "slo-06-slo-compliance",
        "SLO Targets & Compliance",
        ["education", "slo", "compliance"],
        [
            *coverage_panels(1, 0),
            panel_stat("Platform availability SLI", AVAIL_PLATFORM, {"h": 5, "w": 6, "x": 0, "y": 9}, 10, unit="percentunit"),
            panel_stat("SLO target", SLO_TARGET, {"h": 5, "w": 6, "x": 6, "y": 9}, 11, unit="percentunit"),
            panel_stat("Meeting SLO (1=yes)", f"({AVAIL_PLATFORM}) >= bool {SLO_TARGET}", {"h": 5, "w": 6, "x": 12, "y": 9}, 12, unit="short"),
            panel_stat("Services reporting", SVC_WITH_DATA, {"h": 5, "w": 6, "x": 18, "y": 9}, 13, unit="short"),
            panel_timeseries("Availability SLI by service", AVAIL_BY_SVC, {"h": 9, "w": 24, "x": 0, "y": 14}, 14, unit="percentunit"),
        ],
    )


def dashboard_07() -> dict:
    consumed = f"clamp_min(({SLO_TARGET}) - ({AVAIL_PLATFORM}), 0) / ({ERROR_BUDGET})"
    remaining = f"clamp_max(1 - ({consumed}), 0)"
    return base_dashboard(
        "slo-07-error-budget",
        "Error Budget",
        ["education", "slo", "error-budget"],
        [
            *coverage_panels(1, 0),
            panel_gauge("Budget remaining", remaining, {"h": 7, "w": 8, "x": 0, "y": 9}, 10),
            panel_gauge("Budget consumed", consumed, {"h": 7, "w": 8, "x": 8, "y": 9}, 11),
            panel_stat("Allowed error rate", ERROR_BUDGET, {"h": 7, "w": 8, "x": 16, "y": 9}, 12, unit="percentunit"),
            panel_timeseries("Error budget consumed", consumed, {"h": 8, "w": 24, "x": 0, "y": 16}, 13, unit="percentunit"),
        ],
    )


def dashboard_08() -> dict:
    return base_dashboard(
        "slo-08-burn-rate",
        "SLO Burn Rate",
        ["education", "slo", "burn-rate"],
        [
            *coverage_panels(1, 0),
            panel_timeseries("Platform burn rate", BURN_RATE, {"h": 8, "w": 24, "x": 0, "y": 9}, 10),
            panel_timeseries("Error rate by service", ERR_BY_SVC, {"h": 8, "w": 24, "x": 0, "y": 17}, 11, unit="percentunit"),
        ],
    )


def dashboard_09() -> dict:
    sla = "99.5 / 100"
    return base_dashboard(
        "slo-09-sla-vs-slo",
        "SLA vs SLO — Customer Commitments",
        ["education", "sla", "slo"],
        [
            *coverage_panels(1, 0),
            panel_stat("SLI (platform)", AVAIL_PLATFORM, {"h": 5, "w": 6, "x": 0, "y": 9}, 10, unit="percentunit"),
            panel_stat("SLO (internal)", SLO_TARGET, {"h": 5, "w": 6, "x": 6, "y": 9}, 11, unit="percentunit"),
            panel_stat("SLA (customer)", sla, {"h": 5, "w": 6, "x": 12, "y": 9}, 12, unit="percentunit"),
            panel_stat("SLA at risk (1=yes)", f"({AVAIL_PLATFORM}) < bool {sla}", {"h": 5, "w": 6, "x": 18, "y": 9}, 13, unit="short"),
            panel_timeseries("Availability by service", AVAIL_BY_SVC, {"h": 9, "w": 24, "x": 0, "y": 14}, 14, unit="percentunit"),
        ],
    )


def dashboard_10() -> dict:
    return base_dashboard(
        "slo-10-golden-signals",
        "Golden Signals & SLI Mapping",
        ["education", "sre", "golden-signals"],
        [
            *coverage_panels(1, 0),
            panel_timeseries("Latency (p95)", P95_BY_SVC, {"h": 7, "w": 12, "x": 0, "y": 9}, 10, unit="s"),
            panel_timeseries("Traffic (RPS)", RPS_BY_SVC, {"h": 7, "w": 12, "x": 12, "y": 9}, 11, unit="reqps"),
            panel_timeseries("Errors (rate)", ERR_BY_SVC, {"h": 7, "w": 12, "x": 0, "y": 16}, 12, unit="percentunit"),
            panel_timeseries(
                "Saturation (memory)",
                f'process_resident_memory_bytes{{{NS}, app=~"{ALL}"}}',
                {"h": 7, "w": 12, "x": 12, "y": 16},
                13,
                unit="bytes",
                legend="{{app}}",
            ),
        ],
    )


DASHBOARDS = [
    ("01-sli-slo-sla-fundamentals.json", dashboard_01),
    ("02-availability-sli.json", dashboard_02),
    ("03-latency-sli.json", dashboard_03),
    ("04-error-rate-sli.json", dashboard_04),
    ("05-throughput-sli.json", dashboard_05),
    ("06-slo-targets-compliance.json", dashboard_06),
    ("07-error-budget.json", dashboard_07),
    ("08-slo-burn-rate.json", dashboard_08),
    ("09-sla-vs-slo.json", dashboard_09),
    ("10-golden-signals-sli.json", dashboard_10),
]


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for filename, builder in DASHBOARDS:
        path = OUT_DIR / filename
        path.write_text(json.dumps(builder(), indent=2) + "\n", encoding="utf-8")
        print(f"Wrote slo/{path.name}")

    # Remove legacy flat JSON (moved under slo/)
    for old in LEGACY_DIR.glob("*.json"):
        old.unlink()
        print(f"Removed legacy {old.name}")


if __name__ == "__main__":
    main()
