# Grafana Dashboard Operations

Grafana datasource wiring stays in repo, but the service dashboards are now deployed through the Grafana HTTP API instead of being mounted as rigid JSON files.

---

## Where the files live

| Purpose | Repo path |
|---|---|
| Grafana container wiring | `observability\docker-compose.yml` |
| Datasource provisioning | `observability\grafana\provisioning\datasources\datasources.yml` |
| Dashboard deployment script | `observability\grafana\scripts\Publish-GrafanaDashboards.ps1` |

`observability\docker-compose.yml` mounts:

- `observability\grafana\provisioning` → `/etc/grafana/provisioning`

---

## How deployment works

- `datasources.yml` provisions the Prometheus and Loki datasources as non-editable.
- `Publish-GrafanaDashboards.ps1` builds the three service dashboards in PowerShell and upserts them through `POST /api/dashboards/db`.
- The script resolves the Prometheus and Loki datasource UIDs from the live Grafana instance before publishing dashboards.
- Dashboards are created in the hosted Grafana folder `Fitz-Net Services`.

Operationally: update the script, then rerun it against the target Grafana instance. The script is the source of truth for the dashboard layout, not ad-hoc UI changes.

### Running the deployment

PowerShell:

```powershell
$env:FITZNET_GRAFANA_USERNAME = "admin"
$env:FITZNET_GRAFANA_PASSWORD = "<password>"
.\observability\grafana\scripts\Publish-GrafanaDashboards.ps1 -GrafanaUrl "https://logs.fitznet.org"
```

Equivalent `curl` check against the same Grafana API:

```bash
curl -u "$GRAFANA_USER:$GRAFANA_PASS" \
  https://logs.fitznet.org/api/search?query=fitz-net
```

---

## What each dashboard answers

### `fitz-net-website`

Use this when answering:

- Is the website container up?
- Is Nginx serving traffic right now?
- Are 4xx/5xx responses or slow requests increasing?
- Did CPU, memory, or uptime change around the same time?

Primary signals:

- Prometheus/cAdvisor for container up, CPU, memory, uptime
- Loki for Nginx access-log derived request rate, status codes, and latency

### `fitz-net-api`

Use this when answering:

- Is the API reachable and serving requests?
- Are HTTP 5xx or custom API failures increasing?
- Are user/encryption operations behaving normally?
- Is JVM or container pressure contributing to errors?

Primary signals:

- Prometheus scraping `fitz-net-api:8080\actuator\prometheus`
- Loki error logs for recent exceptions/failures

### `gamerbell`

Use this when answering:

- Is the WebSocket relay up?
- How many active sessions are connected?
- Are button events, broadcast outcomes, or firmware checks/downloads failing?
- Is JVM/container pressure or log noise pointing to a service issue?

Primary signals:

- Prometheus scraping `gamerbell:8080\actuator\prometheus`
- Loki error logs for recent failures

---

## Signal caveats

### Website dashboard caveats

The website does **not** currently expose a native Prometheus application endpoint. Its dashboard is a hybrid:

- container health from cAdvisor via Prometheus
- request/latency/status signals from Loki queries over parsed Nginx logs

Implications:

- A healthy container does not prove the SPA itself is rendering correctly in the browser.
- Request and latency panels only work if Promtail keeps ingesting Docker logs and the Nginx access logs remain parseable JSON.
- If the log format changes, fields like `status`, `request_time`, or `upstream_response_time` can go blank and silently break panels.
- The dashboard reflects edge/proxy behavior, not client-side React errors or browser performance.

### General caveats

- API and GamerBell metrics depend on Spring Actuator + Micrometer Prometheus output staying enabled at `/actuator/prometheus`.
- Loki log panels depend on the Docker Compose service label because Promtail maps `com.docker.compose.service` to the `service` label. Renaming compose services requires dashboard query updates.
- The dashboard deployment script assumes Grafana already has working Prometheus and Loki datasources. If those datasource names or types change, the script must be updated before rerunning it.

---

## Maintenance checklist

1. Edit `observability\grafana\scripts\Publish-GrafanaDashboards.ps1`.
2. Rerun the script against the intended Grafana instance.
3. If a panel stops working, verify the backing signal first:
   - Prometheus scrape target for API/GamerBell
   - cAdvisor metric presence for container panels
   - Loki log ingestion and JSON parsing for website/log panels
4. Commit the script or datasource change in this repo so the deployed dashboards stay reproducible.
