# Proxmox deploy scripts

Host-side scripts that live on the Proxmox Docker VM (`192.168.1.59`) at `/opt/fitznet/scripts/`. Each repo's `deploy-to-proxmox.yml` GitHub Actions workflow runs on a **self-hosted runner installed on this same VM** (no SSH, no inbound ports needed — the runner polls GitHub outbound) and invokes these scripts directly as a local shell step.

See [`docs/proxmox-self-hosted-runner-handoff.md`](../../docs/proxmox-self-hosted-runner-handoff.md) for the one-time runner installation steps.

They are tracked here for review/history — this directory is **not** auto-synced to the server. After creating or editing a script, copy it manually:

```bash
scp scripts/proxmox/deploy-fitz-net-api.sh proxmoxvm:/opt/fitznet/scripts/
scp scripts/proxmox/deploy-fitz-net-website.sh proxmoxvm:/opt/fitznet/scripts/
ssh proxmoxvm "chmod +x /opt/fitznet/scripts/deploy-fitz-net-api.sh /opt/fitznet/scripts/deploy-fitz-net-website.sh"
```

Each script takes a Docker Hub tag as its only argument (defaults to `latest`), pulls `mattlol85/<image>:<tag>`, retags it locally as `:latest` (since `docker-compose.yml` hardcodes `:latest`), and recreates just that service with `docker compose up -d --no-deps <service>`.

`deploy-gamerbell.sh` already exists on the server following this same convention but is not tracked in any repo.
