# AI node installer (Windows)

This is what you package up and send to someone contributing a GPU (e.g. your brother's PC) so it registers itself as a Fitz-Net AI worker node. It installs Ollama, configures the OpenVPN client for manual use, and registers with `fitz-net-api`. Not auto-synced anywhere — this directory is the source of truth; you assemble a zip from it each time you enroll a new node.

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

2. **Get a client `.ovpn` profile.** *Skip this whole step for a node on your own local network* — those install LAN-only and need no profile; the owner just runs `.\install-ai-node.ps1 -Lan`. Otherwise, two ways:
   - **Automated (recommended):** run the `generate-ai-node-package.yml` GitHub Actions workflow (`gh workflow run generate-ai-node-package.yml -f node-name=brother-pc`) — it generates the profile on your OpenVPN server via a restricted SSH key and hands you back a ready-to-send zip as a workflow artifact. Skip straight to step 4 if you use this path. See [`docs/openvpn-ai-node-handoff.md`](../../docs/openvpn-ai-node-handoff.md) for one-time setup.
   - **Manual:** generate it by hand on your existing OpenVPN server (see the handoff doc's fallback section) and save the resulting single-file profile as `node.ovpn` in this folder (same directory as `install-ai-node.ps1`).

3. **Zip it up** (only needed for the manual path — the workflow does this for you). Select `install-ai-node.ps1`, `uninstall-ai-node.ps1`, `heartbeat.ps1`, `node-network.ps1`, `manage-ai-node-vpn.ps1`, `manage-ai-node-ollama.ps1`, `start-ollama.ps1`, `node-console.ps1`, `node-console-icon.ico`, and `node.ovpn`, and compress them into one `.zip` (e.g. `fitz-net-ai-node.zip`) — including the uninstaller, controls, and desktop icon gives the node owner everything needed without another download.

4. **Send the zip to the node owner**, along with the enrollment token from step 1 (send the token through a separate channel, not inside the zip — it's a one-time credential).

## What the node owner does

1. Unzip the package anywhere.
2. Right-click `install-ai-node.ps1` → **Run with PowerShell** (as Administrator — the script requires it). If prompted, paste in the enrollment token you sent them.
3. **LAN node (same local network as `fitz-net-api`):** there's nothing to answer — run `.\install-ai-node.ps1 -Lan` (or just double-click when no `node.ovpn` is bundled) and it installs LAN-only. **Remote node** (e.g. a family member's PC elsewhere): the package includes a `node.ovpn`; the installer asks whether to install/connect OpenVPN — say **yes**, since the VPN is the only way `fitz-net-api` can reach it to route chat prompts. Pass `-InstallVpn yes` / `-InstallVpn no` to answer without the prompt (the value is required — `-InstallVpn` on its own is an error).
4. Wait for "This machine is now registered as a Fitz-Net AI node."

That's it — Ollama is installed for the signed-in model owner if missing and configured with `OLLAMA_HOST=0.0.0.0`. The installer briefly starts it under that owner to verify the API and models, then stops it before completing. `FitzNetOllamaServe` is a demand-only task with no logon or boot trigger. OpenVPN is also left disconnected with its service set to Manual. Vendor-created Ollama and OpenVPN GUI sign-in entries are backed up and disabled, so they cannot bypass this manual policy. The node owner starts and stops both from the desktop console. A lightweight scheduled heartbeat still runs every 2 minutes so the website promptly reflects `ONLINE` or `OFFLINE`; it does not load Ollama, the model, GPU, or VPN. Port 11434 is opened either on Private networks for LAN mode or only on the OpenVPN adapter for VPN mode. The script is safe to re-run if anything needs retrying; an existing node keeps its registration and does not need another enrollment token.

If VPN installation is selected, `node.ovpn` is required. The installer rewrites it as a narrow split tunnel: only traffic to the API host (`192.168.1.59`) uses OpenVPN, never the node owner's general internet traffic. A manually controlled node remains `OFFLINE` until its owner connects the VPN.

## Turning the VPN on and off

The installer copies `manage-ai-node-vpn.ps1` to `C:\ProgramData\FitzNetNode\`. Right-click it and choose **Run with PowerShell** for an interactive Connect/Disconnect/Status menu, or use an Administrator PowerShell:

```powershell
powershell.exe -ExecutionPolicy Bypass -File C:\ProgramData\FitzNetNode\manage-ai-node-vpn.ps1 -Action Connect
powershell.exe -ExecutionPolicy Bypass -File C:\ProgramData\FitzNetNode\manage-ai-node-vpn.ps1 -Action Disconnect
powershell.exe -ExecutionPolicy Bypass -File C:\ProgramData\FitzNetNode\manage-ai-node-vpn.ps1 -Action Status
```

Connect starts the VPN for the current Windows session but leaves the OpenVPN service set to Manual. Disconnect stops it and moves the profile out of OpenVPN's auto-start directory. The node heartbeat automatically changes the website status between `ONLINE` and `OFFLINE`.

## Live node console

The installer opens a colored PowerShell console and creates a **Fitz-Net AI Node Console** desktop shortcut with the Fitz-Net robot icon. Nothing is added to Windows logon: after a reboot, the owner opens this shortcut when they want to use the node. Windows shows one UAC approval when the console opens; that elevated session handles every later control without prompting again. The console shows the authoritative VPN adapter address, OpenVPN service/startup state, Ollama health, installed models, active website calls, and recent chat activity. This avoids confusion with OpenVPN GUI, whose tray menu may still say **Connect** because the Fitz-Net profile is controlled by the Windows service instead of that GUI session.

Use **O** to start Ollama, **X** to stop Ollama, **C** to connect the VPN, **D** to disconnect it, **R** to refresh, and **Q** to close only the console. These controls reuse the console's administrator session, so they do not show additional UAC prompts. Closing the console does not stop Ollama or change the VPN state.

The console records request metadata only: arrival time, completion status, and duration. Prompt and response content are never shown or written to its activity display. Ollama's access log is rotated at 10 MB and retained as one previous file under the model owner's local application-data directory.

## Removing a node

Run `uninstall-ai-node.ps1` (as Administrator) on the node itself. It deregisters the node from `fitz-net-api` (so it stops showing up on the Status page), removes the heartbeat scheduled task and `C:\ProgramData\FitzNetNode\`, restores the vendor sign-in entries it backed up, reverts `OLLAMA_HOST` and removes the firewall rule opened for it, and removes any Fitz-Net OpenVPN profile files. It does **not** uninstall Ollama or the OpenVPN client themselves — only the Fitz-Net-specific configuration this installer added. Safe to re-run.

## Files

- `install-ai-node.ps1` — the main installer, run once by the node owner.
- `uninstall-ai-node.ps1` — cleanly removes everything the installer set up (see "Removing a node" above).
- `heartbeat.ps1` — copied to `C:\ProgramData\FitzNetNode\` and run every 2 minutes by a scheduled task (`FitzNetNodeHeartbeat`) that the installer creates.
- `node-network.ps1` — shared route detection used by the installer and heartbeat; it is copied beside the installed heartbeat.
- `manage-ai-node-vpn.ps1` — explicit Connect/Disconnect/Status control for a manually managed VPN.
- `manage-ai-node-ollama.ps1` — explicit Start/Stop/Status control for Ollama and its demand-only scheduled task.
- `start-ollama.ps1` — runs Ollama with remote access under the signed-in model owner's Windows account when manually requested.
- `node-console.ps1` — colored live status, manual VPN controls, and privacy-safe website request activity.
- `node-console-icon.ico` — multi-resolution Windows shortcut icon for the node console.
- `node-console-icon.png` — transparent high-resolution source art for the robot icon (not required in the installer zip).
- `node.ovpn` — **not committed** (gitignored, per-node secret) — generated per step 2 above before zipping. It must use this exact name and sit beside `install-ai-node.ps1`.

## Manual step: generating the `.ovpn` profile by hand

Covered in full in [`docs/openvpn-ai-node-handoff.md`](../../docs/openvpn-ai-node-handoff.md) — use this only if you're not using the GitHub Actions workflow from step 2.

Note: node registration and heartbeats talk to `fitz-net-api` over its existing public HTTPS endpoint, not over this VPN. The VPN is what makes a **remote** node's chat requests routable — see [`docs/openvpn-ai-node-handoff.md`](../../docs/openvpn-ai-node-handoff.md)'s §5 for the (one-time, per OpenVPN server) routing setup this requires on the OpenVPN server and the Docker host.
