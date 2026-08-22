# OpenVPN server scripts

Runs **on the box hosting your OpenVPN server** (a Raspberry Pi in this setup) — not on the Proxmox Docker host, not on a node. Not auto-synced; copy manually when you add or change something here:

```bash
scp scripts/openvpn-server/onboard-ai-node.sh scripts/openvpn-server/ssh-onboard-wrapper.sh matt@fitznet.doomdns.org:~/
ssh matt@fitznet.doomdns.org "chmod +x ~/onboard-ai-node.sh ~/ssh-onboard-wrapper.sh"
```

## `onboard-ai-node.sh`

Generates (or revokes) a per-node OpenVPN client profile for a new Fitz-Net AI worker node. Auto-detects whether the server is PiVPN or a plain OpenVPN + easy-rsa install and does the right thing either way — see the script's header comment for the full option list (`EASYRSA_DIR`, `CLIENT_TEMPLATE`, `OUTPUT_DIR` overrides for the plain easy-rsa path).

```bash
./onboard-ai-node.sh add brother-pc      # writes ./ai-node-ovpns/ai-node-brother-pc.ovpn
./onboard-ai-node.sh revoke brother-pc   # revokes it later if the node is decommissioned
```

After `add`, copy the resulting `.ovpn` off the Pi and into your local `Fitz-Net/scripts/ai-node-installer/` checkout before zipping the installer package for the node's owner — see that folder's `README.md`. Or, once the automation below is set up, skip this manual copy entirely.

**Before handing off any profile it produces**, check your base client template (`CLIENT_TEMPLATE`, or PiVPN's own `client-common.txt`) doesn't push `redirect-gateway` — that would route the *entire* node PC's internet traffic through your home connection instead of just reaching your private network. See [`docs/openvpn-ai-node-handoff.md`](../../docs/openvpn-ai-node-handoff.md) for the full split-tunnel-vs-full-tunnel explanation.

## `ssh-onboard-wrapper.sh`

Not run directly — this is a **forced command** installed via `authorized_keys` for a dedicated, restricted SSH key that `Fitz-Net`'s `generate-ai-node-package.yml` GitHub Actions workflow uses to automate the manual steps above. It only ever allows `onboard-ai-node.sh add <name>` for a sanitized `<name>`, regardless of what the SSH client actually asks to run — so even if that specific automation key ever leaked, it can't be used for anything beyond generating one more node profile. Full one-time setup steps (keypair generation, the exact `authorized_keys` line, adding the private key as a GitHub secret) are in [`docs/openvpn-ai-node-handoff.md`](../../docs/openvpn-ai-node-handoff.md).
