# AI node installer (Windows)

This is what you package up and send to someone contributing a GPU (e.g. your brother's PC) so it registers itself as a Fitz-Net AI worker node. It installs Ollama, installs/connects the OpenVPN client, and registers with `fitz-net-api`. Not auto-synced anywhere — this directory is the source of truth; you assemble a zip from it each time you enroll a new node.

## What you do (once per new node)

1. **Generate an enrollment token.** Log into the website, go to the Status tab, and use the "Enroll a new AI node" panel next to the AI Worker Nodes graph — enter an optional label and click Generate. It shows the token and its expiry with a one-click copy button.

   Fallback (if the website's unavailable): call the endpoint directly with a JWT copied out of browser dev tools:
   ```bash
   curl -X POST https://api.fitznet.doomdns.org/node/enrollment-token \
     -H "Authorization: Bearer <your JWT>" \
     -H "Content-Type: application/json" \
     -d '{"label": "brother-pc"}'
   ```

   Either way you get back `{"token": "...", "expiresAt": "..."}`. The token is valid for 30 minutes and can only be used once.

2. **Get a client `.ovpn` profile.** Two ways:
   - **Automated (recommended):** run the `generate-ai-node-package.yml` GitHub Actions workflow (`gh workflow run generate-ai-node-package.yml -f node-name=brother-pc`) — it generates the profile on your OpenVPN server via a restricted SSH key and hands you back a ready-to-send zip as a workflow artifact. Skip straight to step 4 if you use this path. See [`docs/openvpn-ai-node-handoff.md`](../../docs/openvpn-ai-node-handoff.md) for one-time setup.
   - **Manual:** generate it by hand on your existing OpenVPN server (see the handoff doc's fallback section) and save the resulting single-file profile as `node.ovpn` in this folder (same directory as `install-ai-node.ps1`).

3. **Zip it up** (only needed for the manual path — the workflow does this for you). Select `install-ai-node.ps1`, `heartbeat.ps1`, and `node.ovpn`, and compress them into one `.zip` (e.g. `fitz-net-ai-node.zip`).

4. **Send the zip to the node owner**, along with the enrollment token from step 1 (send the token through a separate channel, not inside the zip — it's a one-time credential).

## What the node owner does

1. Unzip the package anywhere.
2. Right-click `install-ai-node.ps1` → **Run with PowerShell** (as Administrator — the script requires it). If prompted, paste in the enrollment token you sent them.
3. It'll ask whether to install/connect OpenVPN on this PC at all — "no" skips OpenVPN entirely (nothing gets installed or configured), and the node still registers and works for local/LAN chat routing either way. The VPN is groundwork for a later phase (reaching a node that's off the LAN), so it's fine to decline if they'd rather not have a VPN on their PC.
4. If they said yes, it'll also ask whether the VPN should connect automatically on every boot — "yes" if they're fine with it always being on in the background, "no" if they'd rather start it manually from the OpenVPN GUI when they want it active.
5. Wait for "This machine is now registered as a Fitz-Net AI node."

That's it — Ollama is installed if missing, and a scheduled task heartbeats the node every 2 minutes. The script also opens Ollama up to the local network (sets `OLLAMA_HOST=0.0.0.0`, adds a Windows Firewall rule scoped to the Private network profile only) so `fitz-net-api` can actually route chat prompts to it — this part always happens regardless of the VPN choice. The script is safe to re-run if anything needs retrying.

## Files

- `install-ai-node.ps1` — the main installer, run once by the node owner.
- `heartbeat.ps1` — copied to `C:\ProgramData\FitzNetNode\` and run every 2 minutes by a scheduled task (`FitzNetNodeHeartbeat`) that the installer creates.
- `node.ovpn` — **not committed** (gitignored, per-node secret) — generated per step 2 above before zipping. Naming matches `install-ai-node.ps1`'s `-OvpnSourcePath` default (`node.ovpn`, same folder); pass `-OvpnSourcePath` explicitly if you use a different name.

## Manual step: generating the `.ovpn` profile by hand

Covered in full in [`docs/openvpn-ai-node-handoff.md`](../../docs/openvpn-ai-node-handoff.md) — use this only if you're not using the GitHub Actions workflow from step 2.

Note: node registration and heartbeats talk to `fitz-net-api` over its existing public HTTPS endpoint, not over this VPN — the tunnel isn't required for phase 1 to work. It's laying the groundwork for later phases, when the orchestrator needs to reach the node's Ollama port privately. When that's needed, revisit whether the VPN server allows client-to-client traffic or needs a route to the Docker host's subnet.
