---
name: deploy-to-proxmox
description: How to deploy Fitz-Net services to the prod Proxmox Docker VM via the web-triggered Deploy to Proxmox workflow, its version/latest input, and the post-deploy health checks. Use when releasing or redeploying fitz-net-website, GamerBell, or fitz-net-api.
---

# deploy-to-proxmox

## Access pattern

Prod runs on an Ubuntu VM (`192.168.1.59`, alias `proxmoxvm`) on the Proxmox
host. **Its ports are not exposed to the internet** — GitHub cannot reach in.
Instead, self-hosted GitHub Actions runners on that VM poll GitHub outbound over
HTTPS/443 for queued jobs and run the deploy locally. One runner is registered
per repo, all sharing the label `proxmox`. See
`docs/proxmox-self-hosted-runner-handoff.md` for the runner setup.

So a deploy is: **trigger a workflow on github.com -> the VM's runner picks it up
-> it runs `/opt/fitznet/scripts/deploy-<service>.sh <tag>` on the box** (pulls
the image tag, recreates the container via `docker compose`).

## The workflow

`.github/workflows/deploy-to-proxmox.yml` in each service repo
(`fitz-net-website`, `GamerBell`; `fitz-net-api` uses the same pattern once its
workflow exists). Triggers:

- `release: published` — deploys `github.event.release.tag_name` automatically.
- `workflow_dispatch` — manual, with one input:

| Input | Description | Example |
|---|---|---|
| `tag` | Image tag to deploy — a version tag or the literal `latest` | `v0.24.0`, `latest` |

`GamerBell`'s job strips a leading `v` for the image tag; `fitz-net-website`'s
runs on `[self-hosted, proxmox]` and passes the tag through as-is.

## How to invoke

```bash
# Manual deploy of a specific tag
gh workflow run deploy-to-proxmox.yml -R mattlol85/fitz-net-website -f tag=v0.24.0

# Redeploy latest (lowest risk — image already exists; good for a first test)
gh workflow run deploy-to-proxmox.yml -R mattlol85/GamerBell -f tag=latest

# Watch the run
RID=$(gh run list -R mattlol85/fitz-net-website -w deploy-to-proxmox.yml -L1 --json databaseId -q '.[0].databaseId')
gh run watch -R mattlol85/fitz-net-website "$RID"
```

If the run stays queued > ~30s, the runner is probably down — check
`sudo ./svc.sh status` in `/opt/actions-runner-<repo>/` on the VM.

## Post-deploy health checks

```bash
curl -fsS https://api.fitznet.org/actuator/health        # {"status":"UP"}
curl -fsS https://gamerbell.fitznet.org/actuator/health   # {"status":"UP"}
curl -fsS https://gamerbell.fitznet.org/count             # {"count":N}
curl -fsS -o /dev/null -w '%{http_code}\n' https://fitznet.org/   # 200
```

The website Status Dashboard also reads `/actuator/health` for every service —
open https://fitznet.org and confirm all tiles are green.

## Rollback

Re-run the workflow with the previous good tag:

```bash
gh workflow run deploy-to-proxmox.yml -R mattlol85/<repo> -f tag=<previous-tag>
```
