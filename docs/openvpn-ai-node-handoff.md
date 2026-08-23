# Handoff: enrolling AI worker nodes on the OpenVPN server

This is the runbook for the Raspberry Pi (or whatever box) running your OpenVPN server — the one your home network's clients already connect through — for what to do there each time you enroll a new Fitz-Net AI worker node (e.g. a family member's GPU rig). Put a copy of this file directly on that machine.

## Why

Fitz-Net's AI-node installer (`Fitz-Net/scripts/ai-node-installer/`) bundles a per-node OpenVPN client profile so the node connects to your network automatically as a background service — no manual VPN setup on the node owner's end. Node **registration and heartbeats** go over `fitz-net-api`'s existing public HTTPS endpoint, not this VPN. The VPN is what makes a **remote** node's chat requests actually routable — see §5 for the server-side routing setup that requires.

## Primary path: the GitHub Actions workflow

`Fitz-Net`'s `.github/workflows/generate-ai-node-package.yml` automates everything below (§1–2) end to end: trigger it with a node name, it SSHes to this Pi using a dedicated, restricted key, runs `onboard-ai-node.sh` here, and hands you back a ready-to-send zip (installer, uninstaller, heartbeat, shared network helper, and the generated `.ovpn`) as a workflow artifact — no manual SSH/scp on your end at all.

Getting that automation working requires a **one-time setup on this Pi**, since GitHub can't SSH in without a key you've explicitly authorized, and that key is deliberately restricted to doing only this one thing (see "Why a restricted key" below):

### One-time setup

1. **Deploy the scripts here**, from your `Fitz-Net` checkout:
   ```bash
   scp scripts/openvpn-server/onboard-ai-node.sh scripts/openvpn-server/ssh-onboard-wrapper.sh matt@fitznet.doomdns.org:~/
   ssh matt@fitznet.doomdns.org "chmod +x ~/onboard-ai-node.sh ~/ssh-onboard-wrapper.sh"
   ```

2. **Generate a dedicated keypair** (not your personal SSH key — a new one, used for nothing else), on your own machine:
   ```bash
   ssh-keygen -t ed25519 -f fitznet-onboarder -C "github-actions-fitznet-onboarder" -N ""
   ```

3. **Authorize the public key on the Pi, restricted to the wrapper script.** Append to `~/.ssh/authorized_keys` for the `matt` user (paste the contents of `fitznet-onboarder.pub` after the `command=` prefix below, all on one line):
   ```
   command="~/ssh-onboard-wrapper.sh",no-port-forwarding,no-X11-forwarding,no-agent-forwarding,no-pty ssh-ed25519 AAAA...your-generated-public-key... github-actions-fitznet-onboarder
   ```
   The `command=` prefix means sshd ignores whatever command a client using this key actually requests and always runs `ssh-onboard-wrapper.sh` instead — that script is the only thing this key can ever trigger (see below).

4. **Add the private key to GitHub Secrets** (never commit it, never paste it into chat):
   ```bash
   gh secret set OPENVPN_SSH_PRIVATE_KEY -R mattlol85/Fitz-Net < fitznet-onboarder
   ```
   Then delete your local copy of `fitznet-onboarder` (the private key) once it's confirmed in GitHub Secrets.

5. **Trigger it**: `gh workflow run generate-ai-node-package.yml -R mattlol85/Fitz-Net -f node-name=brother-pc`, or from the Actions tab in GitHub. Download the resulting artifact zip once the run finishes.

### Why a restricted key, not just "an SSH key"

A general-purpose SSH key with full shell access to this box would mean anything that can read the GitHub secret (or anything that compromises the workflow) gets a shell on the machine hosting your VPN server, its PKI/CA material, and everything else here. The `command=` restriction means the absolute worst case if this specific key leaks is: someone can generate one more OpenVPN client profile for a name matching `[a-zA-Z0-9-]+` — nothing else. `ssh-onboard-wrapper.sh` (§ below) enforces this even if `authorized_keys` were ever misconfigured, by double-checking `$SSH_ORIGINAL_COMMAND` itself before doing anything.

If you ever need to revoke this automation entirely: delete the `authorized_keys` line and remove the `OPENVPN_SSH_PRIVATE_KEY` secret from the repo. Nothing else needs to change.

## Fallback / manual path

Everything below is what the workflow does for you automatically — useful if you want to do it by hand, are testing directly on the Pi, or your setup doesn't match PiVPN or plain easy-rsa (in which case `onboard-ai-node.sh` will tell you so and let you fall back to doing this manually).

### 1. Generate a client certificate for the new node

From your `easy-rsa` directory:

```bash
cd $EASYRSA_DIR
./easyrsa build-client-full ai-node-<name> nopass
```

Use a descriptive `<name>` per node (e.g. `ai-node-brother-pc`) so you can tell nodes apart later, especially when revoking one (see §3).

### 2. Assemble a single-file `.ovpn` profile

The installer expects **one file** to drop into the package — inline the CA cert, client cert, and client key into your base client template rather than shipping them as separate files:

```bash
BASE_CONFIG="$OPENVPN_DIR/client-common.txt"   # your existing base client template
NAME="ai-node-<name>"
OUT="$NAME.ovpn"

{
  cat "$BASE_CONFIG"
  echo "<ca>"
  cat "$EASYRSA_DIR/pki/ca.crt"
  echo "</ca>"
  echo "<cert>"
  sed -ne '/BEGIN CERTIFICATE/,$ p' "$EASYRSA_DIR/pki/issued/$NAME.crt"
  echo "</cert>"
  echo "<key>"
  cat "$EASYRSA_DIR/pki/private/$NAME.key"
  echo "</key>"
} > "$OUT"
```

Copy the resulting `$OUT` off the server (e.g. `scp`) and rename it to `node.ovpn` inside your local checkout of `Fitz-Net/scripts/ai-node-installer/` before zipping the installer package — see that folder's `README.md` for the rest of the packaging steps. Treat this file as a credential: send it to the node owner over a private channel, never publicly, and don't commit it (the repo's `.gitignore` already excludes `scripts/ai-node-installer/*.ovpn`).

### 3. Revoking a node's access later

If a node is decommissioned or a machine is compromised:

```bash
cd $EASYRSA_DIR
./easyrsa revoke ai-node-<name>
./easyrsa gen-crl
```

Then reload/restart the OpenVPN server so it picks up the updated CRL (`systemctl restart openvpn@server` or equivalent), and separately delete the node from `fitz-net-api`'s registry (there's no admin UI for this yet in phase 1 — a direct Mongo delete on the `ai_nodes` collection, or ask for a `/node/{id}` delete endpoint to be added if this becomes routine).

## Split-tunnel vs. full-tunnel — check before handing off

This is a property of your base client template (`CLIENT_TEMPLATE` / PiVPN's `client-common.txt`), not something either the script or the installer decides:

- **Full tunnel**: if the template has `redirect-gateway def1 bypass-dhcp` (or similar), the node's *entire* internet connection routes through your home network once connected — all its normal browsing/streaming/etc, not just traffic meant for you. Almost certainly not what you want for an AI node.
- **Split tunnel** (what you want): the template instead pushes a route just for what the node actually needs to reach — see §5 below for the specific narrow route, rather than your whole LAN — with no `redirect-gateway`. Only that traffic goes through the tunnel; the node's own internet traffic is unaffected.

Check for `redirect-gateway` in the template before generating a node's profile, and remove it (or keep a separate, narrower template just for AI nodes) if present. Also check the template isn't pushing DNS servers (`dhcp-option DNS ...`) unless you actually want the node's DNS lookups going through your network too.

## 5. Private node-to-orchestrator traffic (routing a remote node's chat requests)

Registration/heartbeat traffic doesn't need this VPN — it goes over `fitz-net-api`'s public HTTPS endpoint regardless. This section is specifically for the orchestrator (the Proxmox Docker host, `192.168.1.59`, running `fitz-net-api`) being able to reach a **remote** node's Ollama port (`11434`) over the VPN to route a chat request — needed for any node that isn't on your home LAN (e.g. a family member's PC elsewhere).

This is three separate pieces, all needed together — missing any one of them looks like the same generic connection failure, so do all three:

**On this Pi:**

1. **Enable IP forwarding** so the Pi actually forwards packets between the VPN tunnel and your LAN:
   ```bash
   sudo sysctl -w net.ipv4.ip_forward=1
   echo "net.ipv4.ip_forward=1" | sudo tee -a /etc/sysctl.conf
   ```

2. **Push a narrow route to VPN clients** — just to the Docker host, not your whole LAN (least-privilege: a remote node only needs to reach the one machine it's actually talking to). Add to your server config (`server.conf`, or PiVPN's equivalent):
   ```
   push "route 192.168.1.59 255.255.255.255"
   ```
   Restart the OpenVPN server after (`sudo systemctl restart openvpn@server` or equivalent). This is what makes the *return* path work — without it, the node has no idea how to reply to the Docker host.

3. **Note the VPN subnet** this server hands out — look for a line like `server 10.8.0.0 255.255.255.0` in the same config. You'll need this exact subnet for the next step.

**On the Docker host** (`192.168.1.59`, the Ubuntu VM running `fitz-net-api`):

4. **Add a static route into the VPN subnet**, via this Pi as next-hop, so the *outbound* direction (Docker host → remote node) works:
   ```bash
   sudo ip route add <vpn-subnet-from-step-3> via <this-pi's-LAN-IP>
   ```
   Persist it (e.g. via netplan on Ubuntu) so it survives a reboot — an `ip route add` alone is lost on restart. `fitz-net-api` runs in Docker on this host; outbound container connections go through the host's routing table via the normal Docker NAT path, so this host-level route is sufficient on its own — no container-specific networking change needed.

**Verify before testing through the app** — from the Docker host itself:
```bash
curl http://<remote-node's-VPN-IP>:11434/api/tags
```
If that works, the network layer is solid and any remaining issue is elsewhere. The installer scopes its port-11434 firewall rule directly to the OpenVPN adapter, so it remains effective without changing the adapter's Windows Public/Private category.
