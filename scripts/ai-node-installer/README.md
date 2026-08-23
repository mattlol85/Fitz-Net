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

3. **Zip it up** (only needed for the manual path — the workflow does this for you). Select `install-ai-node.ps1`, `uninstall-ai-node.ps1`, `heartbeat.ps1`, and `node.ovpn`, and compress them into one `.zip` (e.g. `fitz-net-ai-node.zip`) — including the uninstaller means the node owner has a clean way to remove everything later without re-downloading anything.

4. **Send the zip to the node owner**, along with the enrollment token from step 1 (send the token through a separate channel, not inside the zip — it's a one-time credential).

## What the node owner does

1. Unzip the package anywhere.
2. Right-click `install-ai-node.ps1` → **Run with PowerShell** (as Administrator — the script requires it). If prompted, paste in the enrollment token you sent them.
3. It'll ask whether to install/connect OpenVPN on this PC at all — say **yes** if this node isn't on your own home LAN (e.g. a family member's PC elsewhere), since the VPN is the only way `fitz-net-api` can reach it to route chat prompts. If the node *is* on your LAN, "no" is fine — it still registers and works for local chat routing without it.
4. If they said yes, it'll also ask whether the VPN should connect automatically on every boot — "yes" if they're fine with it always being on in the background, "no" if they'd rather start it manually from the OpenVPN GUI when they want it active.
5. Wait for "This machine is now registered as a Fitz-Net AI node."

That's it — Ollama is installed if missing, and a scheduled task heartbeats the node every 2 minutes. The script also opens Ollama up to the local network (sets `OLLAMA_HOST=0.0.0.0`, adds a Windows Firewall rule scoped to the Private network profile only) so `fitz-net-api` can actually route chat prompts to it — this part always happens regardless of the VPN choice. The script is safe to re-run if anything needs retrying.

## Removing a node

Run `uninstall-ai-node.ps1` (as Administrator) on the node itself. It deregisters the node from `fitz-net-api` (so it stops showing up on the Status page), removes the heartbeat scheduled task and `C:\ProgramData\FitzNetNode\`, reverts `OLLAMA_HOST` and removes the firewall rule opened for it, and removes any Fitz-Net OpenVPN profile files. It does **not** uninstall Ollama or the OpenVPN client themselves — only the Fitz-Net-specific configuration this installer added. Safe to re-run.

## Files

- `install-ai-node.ps1` — the main installer, run once by the node owner.
- `uninstall-ai-node.ps1` — cleanly removes everything the installer set up (see "Removing a node" above).
- `heartbeat.ps1` — copied to `C:\ProgramData\FitzNetNode\` and run every 2 minutes by a scheduled task (`FitzNetNodeHeartbeat`) that the installer creates.
- `node.ovpn` — **not committed** (gitignored, per-node secret) — generated per step 2 above before zipping. Naming matches `install-ai-node.ps1`'s `-OvpnSourcePath` default (`node.ovpn`, same folder); pass `-OvpnSourcePath` explicitly if you use a different name.

## Manual step: generating the `.ovpn` profile by hand

Covered in full in [`docs/openvpn-ai-node-handoff.md`](../../docs/openvpn-ai-node-handoff.md) — use this only if you're not using the GitHub Actions workflow from step 2.

Note: node registration and heartbeats talk to `fitz-net-api` over its existing public HTTPS endpoint, not over this VPN. The VPN is what makes a **remote** node's chat requests routable — see [`docs/openvpn-ai-node-handoff.md`](../../docs/openvpn-ai-node-handoff.md)'s §5 for the (one-time, per OpenVPN server) routing setup this requires on the OpenVPN server and the Docker host.
