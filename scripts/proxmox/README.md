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

## Marine Park relay

`deploy-marine-park-relay.sh` deploys `mattlol85/marine-park-relay` (the game's join-code relay at `relay.fitznet.org`, built by Marine-Park's `Relay` workflow). Same convention as above, plus two extras: it prints how many rooms are open before the restart (a restart ends every game), and it waits for the container's healthcheck and exits non-zero if it never goes healthy. Image tags are `latest` and `sha-<7-char commit>`. First-time setup and verification: [`docs/marine-park-relay-vm-handoff.md`](../../docs/marine-park-relay-vm-handoff.md).

```bash
scp scripts/proxmox/deploy-marine-park-relay.sh proxmoxvm:/tmp/
ssh -t proxmoxvm "sudo install -m 755 /tmp/deploy-marine-park-relay.sh /opt/fitznet/scripts/ && rm /tmp/deploy-marine-park-relay.sh"
```

## AI-node VPN route

Remote AI-node chat also requires the Docker host to route the OpenVPN subnet
through the LAN address of the OpenVPN server. Copy the helper to the host and
run it once with the actual addresses from that network:

```bash
scp scripts/proxmox/configure-ai-node-vpn-route.sh proxmoxvm:/opt/fitznet/scripts/
ssh proxmoxvm "chmod +x /opt/fitznet/scripts/configure-ai-node-vpn-route.sh"
ssh -t proxmoxvm "sudo /opt/fitznet/scripts/configure-ai-node-vpn-route.sh 10.180.53.0/24 <openvpn-server-lan-ip> 10.180.53.6"
```

The command applies the route immediately, persists it as a systemd oneshot
service, and uses the optional node address to verify `/api/tags` from the same
host that runs `fitz-net-api`. It is idempotent and can be re-run if the VPN
subnet or OpenVPN server address changes.
