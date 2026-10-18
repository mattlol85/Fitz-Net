# Container Resource Limits

Every service in the three compose stacks (`docker-compose.yml`, `observability/`, `mail/`) sets a `mem_limit`. Before this, no container had a cap, so one leaking process could fill the 8 GB Proxmox VM. The kernel OOM killer would then pick a victim, possibly Mongo or the mailserver.

With a cap, a runaway container is OOM-killed inside its own cgroup and brought back by `restart: unless-stopped`. Everything else keeps running.

## Sizing

Limits are about 1.5–2× the steady-state usage measured with `docker stats` on 2026-10-18, after 13 days of uptime. They're ceilings, not reservations, so their sum (~6 GB) is allowed to exceed what's actually in use.

| Stack | Service | Observed | `mem_limit` | Notes |
|---|---|---|---|---|
| main | gamerbell | 431 MiB | 768m | JVM — see below |
| main | fitz-net-api | 268 MiB | 640m | JVM — see below |
| main | fitz-net-website | 10 MiB | 128m | nginx static |
| main | mongo | 124 MiB | 768m | WiredTiger cache sizes itself from the cgroup limit |
| main | caddy | 22 MiB | 128m | |
| observability | loki | 210 MiB | 768m | query spikes |
| observability | grafana | 259 MiB | 512m | |
| observability | prometheus | 150 MiB | 512m | head-block compaction spikes |
| observability | promtail | 118 MiB | 256m | |
| observability | cadvisor | 87 MiB | 256m | |
| observability | node-exporter | 11 MiB | 64m | |
| mail | mailserver | 284 MiB | 1g | rspamd (5 workers) + postfix/dovecot; ClamAV is off — raise this if `ENABLE_CLAMAV=1` |
| mail | roundcube | 69 MiB | 256m | |

## JVM services

`gamerbell` and `fitz-net-api` set `JAVA_TOOL_OPTIONS=-XX:MaxRAMPercentage=70`. By default the JVM caps its heap at 25% of the RAM it sees. With no container limit, that was 25% of the whole VM (~2 GB each). With `mem_limit` set, the JVM reads the cgroup limit, and 70% of it goes to heap. The remaining 30% is left for metaspace, thread stacks, the code cache and direct buffers.

If either app gets OOM-killed (`docker inspect <name> --format '{{.State.OOMKilled}}'` returns `true`), raise its `mem_limit` before you touch the percentage.

## Rollout

These files aren't deployed automatically. The running stacks live at `/opt/fitznet/compose.yml`, `/home/deploy/observability/docker-compose.yml` and `/home/deploy/mail/docker-compose.yml`, and **those copies have drifted from this repo** (see below). Copy only the `mem_limit` / `JAVA_TOOL_OPTIONS` lines into each live file rather than overwriting it. Then recreate one service at a time:

```bash
docker compose up -d --no-deps <service>
docker stats --no-stream <container>          # usage well under the limit?
docker inspect <container> --format '{{.HostConfig.Memory}} {{.State.OOMKilled}}'
```

Do the JVM services and mongo last, and check their logs after each restart.

## Known drift between repo and host (as of 2026-10-18)

- **observability:** the live file still publishes Loki 3100, Prometheus 9090, cadvisor 8081 and node-exporter 9100 on all interfaces instead of `127.0.0.1`. It also has `--web.enable-lifecycle` on Prometheus and doesn't set the Grafana admin password, anonymous-access or sign-up settings. The live file *does* add log rotation and 30d Prometheus retention, which the repo lacks.
- **main:** the live `gamerbell` uses `env_file: /opt/fitznet/apps/gamerbell/env/dev.env`, only joins `fitznet`, and adds the `gamerbell.fitznet.org` host. The live `fitz-net-api` adds `SPRING_DATA_MONGODB_USERNAME/PASSWORD`. The live `fitz-net-website` has a healthcheck.
- **teamspeak:** runs outside any compose file (started with `docker run`). As of 2026-10-18 it had restarted 18,980 times: the `6.0.0-beta12.1` image's built-in license expired, so it exits every minute. Pull a newer image or remove the container. If you keep it, add it to a compose file with a `mem_limit` like the services above.
