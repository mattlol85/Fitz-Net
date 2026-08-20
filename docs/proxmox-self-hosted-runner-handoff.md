# Handoff: self-hosted GitHub Actions runners on the Proxmox Docker VM

This is a one-time setup checklist for the Proxmox-hosted Docker VM (`192.168.1.59`, alias `proxmoxvm`) to enable the "Deploy to Proxmox" workflows in `fitz-net-api`, `fitz-net-website`, and `GamerBell`.

## Why

Those repos' `deploy-to-proxmox.yml` workflows now run on a **self-hosted runner** rather than SSHing in from a GitHub-hosted runner. The VM's ports aren't exposed to the internet, so instead of GitHub reaching in over SSH, an agent on the VM polls GitHub outbound (HTTPS/443) for queued jobs and executes them locally. No inbound port needs to open.

## 1. Register one runner per repo

GitHub self-hosted runners (on a personal account, no GitHub Org) are registered per-repository. Install **three separate runner instances** on the VM, each in its own directory, each pointed at a different repo, all sharing the label `proxmox`:

```
/opt/actions-runner-fitz-net-api/
/opt/actions-runner-fitz-net-website/
/opt/actions-runner-gamerbell/
```

For each repo, in its GitHub Settings → Actions → Runners → "New self-hosted runner" (Linux x64), you'll get a registration token and a `config.sh` command. Example for `fitz-net-api`:

```bash
sudo mkdir -p /opt/actions-runner-fitz-net-api && cd /opt/actions-runner-fitz-net-api
curl -o actions-runner-linux-x64.tar.gz -L https://github.com/actions/runner/releases/latest/download/actions-runner-linux-x64-<version>.tar.gz
tar xzf actions-runner-linux-x64.tar.gz

./config.sh --url https://github.com/mattlol85/fitz-net-api --token <REGISTRATION_TOKEN> --name proxmoxvm-fitz-net-api --labels proxmox --unattended

sudo ./svc.sh install
sudo ./svc.sh start
```

Repeat for `fitz-net-website` (dir `/opt/actions-runner-fitz-net-website`) and `GamerBell` (dir `/opt/actions-runner-gamerbell`), each with its own registration token from that repo's Settings page and its own `--name`.

**Registration tokens expire in ~1 hour and are single-use** — generate each one right before running `config.sh`.

## 2. Give the runner service user docker access

Whatever OS user the runner services run as needs to run `docker` / `docker compose` without `sudo`:

```bash
sudo usermod -aG docker <runner-service-user>
```

Restart the runner services after this so the new group membership takes effect:

```bash
sudo /opt/actions-runner-fitz-net-api/svc.sh stop && sudo /opt/actions-runner-fitz-net-api/svc.sh start
# repeat for the website and gamerbell runner dirs
```

## 3. Install the deploy scripts

Copy the two new scripts from this repo (`Fitz-Net/scripts/proxmox/`) to `/opt/fitznet/scripts/` and make them executable:

```bash
scp scripts/proxmox/deploy-fitz-net-api.sh proxmoxvm:/opt/fitznet/scripts/
scp scripts/proxmox/deploy-fitz-net-website.sh proxmoxvm:/opt/fitznet/scripts/
ssh proxmoxvm "chmod +x /opt/fitznet/scripts/deploy-fitz-net-api.sh /opt/fitznet/scripts/deploy-fitz-net-website.sh"
```

`deploy-gamerbell.sh` should already exist at `/opt/fitznet/scripts/deploy-gamerbell.sh` from the prior SSH-based setup — confirm it's present and executable; no changes to it are required (the GamerBell workflow still invokes it with a single tag argument, same contract as before).

## 4. Test each workflow

In each repo's Actions tab, run "Deploy to Proxmox" manually (`workflow_dispatch`) with `tag=latest` first — the image already exists so this is the lowest-risk way to confirm the runner picks up the job and the script executes. Watch the job logs; if the runner doesn't pick up the job within ~30s, check `sudo ./svc.sh status` in the relevant runner directory.

## 5. Clean up the old SSH-based secrets (optional, after all three are confirmed working)

These are no longer used once the self-hosted runner is live:

- `PROXMOX_SSH_PRIVATE_KEY`
- `DEPLOY_HOST` / `DEPLOY_USER`
- `PROXMOX_HOST` / `PROXMOX_USER`

Remove them from each repo's Settings → Secrets and consider rotating/revoking that SSH key pair if it isn't used anywhere else.
