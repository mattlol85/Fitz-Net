# Handoff: Marine Park relay (`relay.fitznet.org`) on the Proxmox Docker VM

This is the runbook for the Proxmox Docker VM (`192.168.1.59`, alias
`proxmoxvm`, hostname `docker-host`). The main stack is in
`/opt/fitznet/compose.yml`, which is root-owned and not a git checkout. Put a
copy of this file on that machine.

## Why

Marine Park (the Unity game, [mattlol85/Marine-Park](https://github.com/mattlol85/Marine-Park))
lets friends join over the internet with a 6-character code. Cloudflare can't
carry the game's UDP on our plan, so the game talks WebSocket to a small relay
that we host here, reached through the existing `fitznet-proxmox` tunnel:

```
Game ──wss──▶ Cloudflare ──tunnel──▶ cloudflared ──http──▶ caddy:80 ──▶ marine-park-relay:8080
```

The relay source, tests and image build live in Marine-Park's `Server/Relay/`
(issue #2, PR #11). This doc covers only running it here.

**Already done on the Cloudflare side (2026-11-27), don't change it:**
- tunnel route `relay.fitznet.org` → `http://caddy:80`, before the 404 catch-all;
- proxied `CNAME relay` → the tunnel;
- a Configuration Rule for that host: Browser Integrity Check off, Security
  Level essentially off (game clients aren't browsers).

Until this runbook is done, `https://relay.fitznet.org/healthz` returns `308`
(Caddy has no `http://relay.fitznet.org` site yet). That's expected.

**Not affected:** nothing else in the stack. The relay needs no Mongo, no
`.env` values and no other service. cloudflared and Caddy need no changes.

## Hard rules

- **Never replace `/opt/fitznet/compose.yml`** with the repo's
  `docker-compose.yml`. They have drifted, and the live file is right. Make a
  targeted edit only, with a backup.
- **Never print anything from `.env`.**
- **Don't change Cloudflare.** The dev side does DNS and tunnel routes.
- Writes in `/opt/fitznet` need `sudo`. Docker doesn't.
- Recreating `marine-park-relay` ends every game in progress. Other services'
  deploys don't (see `stream_close_delay` below).

## Prerequisite: the image must exist

The image is `mattlol85/marine-park-relay`, pushed by Marine-Park's `Relay`
workflow on every merge to `main`. Check it before starting:

```bash
docker pull mattlol85/marine-park-relay:latest
```

If that fails with *not found*, the dev side hasn't published it yet (the
workflow needs `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN` in Marine-Park). Stop
and report it.

## One-time setup

### 1. Install the deploy script

From a Fitz-Net checkout on the dev machine:

```bash
scp scripts/proxmox/deploy-marine-park-relay.sh proxmoxvm:/tmp/
ssh -t proxmoxvm "sudo install -m 755 /tmp/deploy-marine-park-relay.sh /opt/fitznet/scripts/ && rm /tmp/deploy-marine-park-relay.sh"
```

It follows the other deploy scripts (pull the tag, retag as `:latest`,
`docker compose up -d --no-deps`), and also waits for the container's
healthcheck and fails loudly if it never goes healthy.

### 2. Add the service to `compose.yml`

```bash
cd /opt/fitznet
sudo cp compose.yml compose.yml.bak-$(date +%F-%H%M)
sudoedit compose.yml
```

Add this under `services:` (next to `fitz-net-website` is fine). Copy it from
the repo's `docker-compose.yml`, where it's the `marine-park-relay` service:

```yaml
  marine-park-relay:
    image: mattlol85/marine-park-relay:latest
    container_name: marine-park-relay
    mem_limit: 128m
    restart: unless-stopped
    environment:
      Relay__MaxRooms: "32"
      Relay__MaxPeersPerRoom: "8"
    networks:
      - fitznet
    expose:
      - "8080"
      - "9464"
    labels:
      caddy: http://relay.fitznet.org
      caddy.reverse_proxy: "{{upstreams 8080}}"
      caddy.reverse_proxy.stream_close_delay: 6h
      caddy_network: fitznet
```

Two things matter here:
- **Don't add `ASPNETCORE_URLS`.** The image listens on 8080 (relay) and 9464
  (metrics). Setting it to only 8080 silently drops the metrics port.
- **Keep `stream_close_delay`.** caddy-docker-proxy reloads Caddy whenever any
  container changes, so every Fitz-Net deploy reloads it. Without the delay,
  each reload closes every open WebSocket and every game drops.

Then:

```bash
docker compose config -q && docker compose up -d marine-park-relay
```

`up -d marine-park-relay` only creates this one container; nothing else
restarts. Caddy picks the new labels up by itself within a few seconds.

### 3. Add the Prometheus scrape job

The observability stack is at `/home/deploy/observability/`. Back up and edit
its `prometheus/prometheus.yml`, adding at the end of `scrape_configs`:

```yaml
  - job_name: marine-park-relay
    metrics_path: /metrics
    static_configs:
      - targets: ['marine-park-relay:9464']
```

Then reload Prometheus (works whether or not the live file enables
`--web.enable-lifecycle`):

```bash
docker kill -s HUP prometheus
```

### 4. (Optional) Self-hosted runner for automatic deploys

Marine-Park's `Relay` workflow has a deploy job that runs
`/opt/fitznet/scripts/deploy-marine-park-relay.sh sha-<short>` on a
`[self-hosted, proxmox]` runner after each image push. Runners on a personal
account are per repo, so it needs its own instance. Follow
[`proxmox-self-hosted-runner-handoff.md`](proxmox-self-hosted-runner-handoff.md)
step 1 with directory `/opt/actions-runner-marine-park`, URL
`https://github.com/mattlol85/Marine-Park` and `--name proxmoxvm-marine-park
--labels proxmox`, then step 2 (docker group). The dev side then sets the
`RELAY_DEPLOY_ENABLED` repository variable to `true`:

```bash
gh variable set RELAY_DEPLOY_ENABLED -R mattlol85/Marine-Park --body true
```

Until then, deploy by hand (see below).

## Verify

On the VM:

```bash
docker inspect marine-park-relay --format '{{.State.Health.Status}} {{.HostConfig.Memory}}'
# expect: healthy 134217728

curl -si -H 'Host: relay.fitznet.org' http://127.0.0.1/healthz | head -1
# expect: HTTP/1.1 200 OK   (a 308 means Caddy has no http://relay.fitznet.org site yet)

curl -s https://relay.fitznet.org/healthz; echo
# expect: ok

docker exec marine-park-relay wget -q -O - http://127.0.0.1:9464/metrics | grep '^marinepark_relay_rooms '
# expect: marinepark_relay_rooms 0

curl -si -H 'Host: relay.fitznet.org' http://127.0.0.1/metrics | head -1
# expect: 404 — metrics must NOT be reachable through Caddy

docker logs --tail 5 marine-park-relay
# expect: JSON lines, no exceptions
```

Prometheus target (from the VM, Prometheus is loopback-only):

```bash
curl -s 'http://127.0.0.1:9090/api/v1/targets?state=active' | grep -o '"job":"marine-park-relay"[^}]*"health":"[a-z]*"'
# expect: ..."health":"up"
```

End to end, from any machine with Node 22+ and a Marine-Park checkout:

```bash
node Server/Relay/scripts/smoke.mjs wss://relay.fitznet.org
```

It hosts a room, joins it, sends a frame each way, then closes the host and
checks the client gets close `4000` (host ended).

Once the game client supports join codes, also check `stream_close_delay`:
start a game, redeploy some *other* service
(`/opt/fitznet/scripts/deploy-fitz-net-website.sh latest`), and confirm the
game stays connected.

## Redeploy (normal path)

```bash
/opt/fitznet/scripts/deploy-marine-park-relay.sh            # latest
/opt/fitznet/scripts/deploy-marine-park-relay.sh sha-1a2b3c4  # a specific build
```

Image tags are `latest` and `sha-<7-char commit>` (see the Marine-Park
`Relay` workflow run or Docker Hub). The script prints how many rooms are open
before it restarts the container, because a restart ends them all.

## Rollback

Previous image:

```bash
/opt/fitznet/scripts/deploy-marine-park-relay.sh sha-<previous>
```

Remove the relay entirely:

```bash
cd /opt/fitznet
docker compose stop marine-park-relay && docker compose rm -f marine-park-relay
sudo cp compose.yml.bak-<stamp> compose.yml
docker compose config -q
```

Caddy drops the `relay.fitznet.org` site on its own once the container is
gone. Remove the scrape job from `prometheus.yml` and `docker kill -s HUP
prometheus`. Games then fall back to LAN / direct IP; the Cloudflare route can
stay (it returns 308 with nothing behind it).

## Report back (no secrets)

```
image pull: ___   container health: ___   local /healthz: ___   public /healthz: ___
/metrics via Caddy (expect 404): ___   prometheus target: ___   smoke.mjs: ___
deploy-script installed: ___   runner registered (optional): ___
```
