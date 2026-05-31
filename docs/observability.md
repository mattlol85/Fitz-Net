# Grafana Dashboard Operations

Grafana in this repo is fully file-provisioned. Treat dashboard JSON and provisioning YAML as the source of truth; do not rely on UI-only edits.

---

## Where the files live

| Purpose | Repo path |
|---|---|
| Grafana container wiring | `observability\docker-compose.yml` |
| Datasource provisioning | `observability\grafana\provisioning\datasources\datasources.yml` |
| Dashboard provisioning | `observability\grafana\provisioning\dashboards\dashboards.yml` |
| Website dashboard | `observability\grafana\dashboards\fitz-net-website\overview.json` |
| API dashboard | `observability\grafana\dashboards\fitz-net-api\overview.json` |
| GamerBell dashboard | `observability\grafana\dashboards\gamerbell\overview.json` |

`observability\docker-compose.yml` mounts:

- `observability\grafana\provisioning` → `/etc/grafana/provisioning`
- `observability\grafana\dashboards` → `/var/lib/grafana/dashboards`

The dashboard provider scans `/var/lib/grafana/dashboards` every 30 seconds and uses `foldersFromFilesStructure: true`, so the subfolders become Grafana folders automatically.

---

## How provisioning works

- `datasources.yml` provisions the Prometheus and Loki datasources as non-editable.
- `dashboards.yml` provisions every JSON file under `observability\grafana\dashboards`.
- `allowUiUpdates: false` means dashboard changes must be made in JSON, committed here, and deployed to the Docker host.
- `disableDeletion: false` means deleting a JSON file removes the provisioned dashboard from Grafana.

Operationally: edit the JSON file in this repo, sync the change to the Docker host, and let Grafana reload it. A Grafana restart is usually unnecessary if the mounted file changed in place.

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

---

## Maintenance checklist

1. Edit the provisioned JSON file under `observability\grafana\dashboards\...`.
2. Keep the dashboard in the correct service subfolder so Grafana folder placement stays consistent.
3. If a panel stops working, verify the backing signal first:
   - Prometheus scrape target for API/GamerBell
   - cAdvisor metric presence for container panels
   - Loki log ingestion and JSON parsing for website/log panels
4. Commit the JSON/YAML change in this repo so Grafana can be rebuilt or re-synced reproducibly.
