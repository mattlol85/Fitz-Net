# AI node installer (Windows)

This is what you package up and send to someone contributing a GPU (e.g. your brother's PC) so it registers itself as a Fitz-Net AI worker node. It installs Ollama, installs/connects the OpenVPN client, and registers with `fitz-net-api`. Not auto-synced anywhere — this directory is the source of truth; you assemble a zip from it each time you enroll a new node.

## What you do (once per new node)

1. **Generate an enrollment token.** While logged in on the website (so you have a valid JWT), call:

   ```bash
   curl -X POST https://api.fitznet.doomdns.org/node/enrollment-token \
     -H "Authorization: Bearer <your JWT>" \
     -H "Content-Type: application/json" \
     -d '{"label": "brother-pc"}'
   ```

   This returns `{"token": "...", "expiresAt": "..."}`. The token is valid for 30 minutes and can only be used once.

2. **Get a client `.ovpn` profile from your existing OpenVPN server.** See the note at the bottom of this file — this is a manual step on the Linux VPN box, not scripted here. Save the resulting single-file profile as `brother-pc.ovpn` in this folder (same directory as `install-ai-node.ps1`).

3. **Zip it up.** Select `install-ai-node.ps1`, `heartbeat.ps1`, and `brother-pc.ovpn`, and compress them into one `.zip` (e.g. `fitz-net-ai-node.zip`). Send that zip to the node owner, along with the enrollment token from step 1 (send the token through a separate channel, not inside the zip — it's a one-time credential).

## What the node owner does

1. Unzip the package anywhere.
2. Right-click `install-ai-node.ps1` → **Run with PowerShell** (as Administrator — the script requires it). If prompted, paste in the enrollment token you sent them.
3. Wait for "This machine is now registered as a Fitz-Net AI node."

That's it — Ollama and the OpenVPN client are installed if missing, the VPN profile auto-connects as a background service, and a scheduled task heartbeats the node every 2 minutes. The script is safe to re-run if anything needs retrying.

## Files

- `install-ai-node.ps1` — the main installer, run once by the node owner.
- `heartbeat.ps1` — copied to `C:\ProgramData\FitzNetNode\` and run every 2 minutes by a scheduled task (`FitzNetNodeHeartbeat`) that the installer creates.
- `brother-pc.ovpn` — **not committed** (gitignored, per-node secret) — you generate and drop this in before zipping. Naming is just a placeholder; use whatever you like as long as `install-ai-node.ps1`'s `-OvpnSourcePath` default (`brother-pc.ovpn`, same folder) matches, or edit the script.

## Manual step: generating the `.ovpn` profile on your existing OpenVPN server

This part is not scripted or tracked in this repo — do it by hand on the Linux box running your OpenVPN server:

```bash
# From your easy-rsa directory on the OpenVPN server
./easyrsa build-client-full ai-node-brother-pc nopass
```

Then assemble a **single-file** `.ovpn` profile (inline `<ca>`, `<cert>`, `<key>` blocks) so there's just one file to hand off — most OpenVPN server setups have a base client template you can append the cert/key into. Copy the result here as `brother-pc.ovpn` before zipping.

Note: node registration and heartbeats talk to `fitz-net-api` over its existing public HTTPS endpoint, not over this VPN — the tunnel isn't required for phase 1 to work. It's laying the groundwork for later phases, when the orchestrator needs to reach the node's Ollama port privately. When that's needed, revisit whether the VPN server allows client-to-client traffic or needs a route to the Docker host's subnet.
