# Handoff: close router 80/443, everything on the Cloudflare Tunnel

**For:** the agent on the Proxmox Docker VM (`docker-host`). The main stack is
in `/opt/fitznet/compose.yml`, which is root-owned and not a git checkout.
**From:** the dev-side session that runs Cloudflare.
**Decision (Matt, 2026-11-18):** go all-in on the tunnel now, without waiting
for the ESP32 bells. Bells on firmware ≤ v0.16.0 only know
`gamerbell.fitznet.doomdns.org`. They go offline when 443 closes, and that is
accepted.

## State when this was written

**Through the tunnel** (`fitznet-proxmox`, cloudflared → `http://caddy:80`),
all verified from outside:

| Hostname | Result |
|---|---|
| `fitznet.org` | site 200; `/api/*` 200; LiveBoard STOMP `/api/ws-board` 101 |
| `api.fitznet.org` | 200 |
| `gamerbell.fitznet.org` | firmware check 304; `/ws` 101 |

**Still on the router path:**
- `logs.fitznet.org` (Grafana): a DNS-only `A` record to the home IP.
- `*.doomdns.org`.

## Hard rules

- **Never replace `compose.yml`** with the repo's `docker-compose.yml`. They have
  drifted, and the live file is right. Make targeted edits only, with a backup.
- **Only close 80 and 443.**
  - **Keep** the OpenVPN UDP forward to the Pi (AI worker nodes) and SSH :22
    (the `generate-ai-node-package` workflow).
  - **Keep the DDNS updater running.** Both of those use `fitznet.doomdns.org`.
- **Don't change Cloudflare.** The dev side does DNS.
- **Never print anything from `.env`.**
- Writes in `/opt/fitznet` need `sudo`. Docker doesn't.

## Step 1: put Grafana on the tunnel (VM side)

1. Find the observability stack:
   ```bash
   docker inspect grafana --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}  {{index .Config.Labels "com.docker.compose.project.config_files"}}'
   ```
2. In that compose file, change Grafana's labels to the same dual-site pattern
   as the rest of the stack. Back the file up first
   (`sudo cp <file> <file>.bak-$(date +%F-%H%M)`). From:
   ```yaml
   caddy: logs.fitznet.org
   caddy.reverse_proxy: "{{upstreams 3000}}"
   ```
   to:
   ```yaml
   caddy_0: logs.fitznet.org
   caddy_0.reverse_proxy: "{{upstreams 3000}}"
   caddy_1: http://logs.fitznet.org
   caddy_1.reverse_proxy: "{{upstreams 3000}}"
   ```
   Keep `caddy_network: fitznet` and everything else as it is.
3. Apply and check:
   ```bash
   cd <that dir> && docker compose config -q && docker compose up -d grafana
   curl -si -H 'Host: logs.fitznet.org' http://127.0.0.1/ | grep -iE '^HTTP|^location'
   ```
   Expect `HTTP/1.1 302` with `Location: /login`, or a 200. A `308` to
   `https://logs.fitznet.org/` means the `caddy_1` site isn't live; report it.
4. Grafana should know its public URL. If `GF_SERVER_ROOT_URL` is set, it
   should be `https://logs.fitznet.org/`. Report its current value rather than
   changing it.

**Report step 1 and stop.** The dev side then adds the tunnel route and
switches the `logs` record to the tunnel. Grafana briefly has no TLS on the
old path during the swap.

## Step 2: wait for the dev side's go-ahead

The dev side will confirm these before you continue:
- `logs.fitznet.org` is on the tunnel;
- the website release with fitz-net-website#79 is deployed (the status page and
  bell button stop calling doomdns hosts);
- existing AI nodes have `apiBaseUrl` switched to `https://api.fitznet.org`.

## Step 3: close the router ports (Matt does this on the router)

- On the router, delete the **TCP 80** and **TCP 443** port-forwards to the
  Docker VM (`192.168.1.59`).
- **Leave** the OpenVPN UDP forward to the Pi and the TCP 22 forward.
- Also turn off UPnP if it's on. Containers or other devices can reopen ports
  through it.

## Step 4: verify after the ports close

On the VM:
```bash
curl -si https://fitznet.org/ | head -1                              # 200
curl -si https://fitznet.org/api/actuator/health | head -1           # 200
curl -si https://api.fitznet.org/actuator/health | head -1           # 200
curl -si https://logs.fitznet.org/ | grep -iE '^HTTP|^location'      # 302 /login
curl -si -H 'x-ESP32-version: v0.16.0' https://gamerbell.fitznet.org/api/firmware/latest | head -1   # 304
docker logs cloudflared 2>&1 | grep -c "Registered tunnel connection"   # >= 4
```
The dev side separately confirms that the home IP no longer answers on
80/443 from outside.

## Step 5 (optional, 24 h later): stop publishing 80/443 on the VM

Once nothing has needed the direct path for a day, remove Caddy's
`ports: ["80:80", "443:443"]` from `compose.yml` (backup first) and run
`docker compose up -d caddy`. Then only cloudflared can reach Caddy, LAN
clients included. Before doing this, check whether anything on the LAN relies
on `https://<vm-ip>`, and report it if so.

**Rollback** for any step: restore the `.bak-*` file and `docker compose up -d`
the service. For the router, re-add the 80/443 forwards.

## Report back (no secrets)

```
Step 1: grafana compose file: ___  local check: ___  GF_SERVER_ROOT_URL: ___
Step 4: fitznet.org ___  /api health ___  api.fitznet.org ___  logs ___  gamerbell ___  cloudflared conns ___
Step 5 (if done): LAN dependents found: ___  result: ___
Anything unexpected: ___
```
