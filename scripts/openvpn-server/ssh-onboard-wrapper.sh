#!/usr/bin/env bash
#
# Forced-command wrapper for the dedicated GitHub Actions SSH key that
# automates OpenVPN profile generation. This is the ONLY thing that key is
# allowed to run — enforced via a `command="..."` restriction in this user's
# ~/.ssh/authorized_keys (see docs/openvpn-ai-node-handoff.md), which makes
# sshd ignore whatever command the client actually asked for and always run
# this script instead, with the client's request available in
# $SSH_ORIGINAL_COMMAND.
#
# Even if this specific key ever leaked, it can only trigger
# `onboard-ai-node.sh add <name>` for a name matching a safe pattern — never
# an arbitrary shell command, and never `revoke` (revocation stays a manual,
# by-hand operation on this box).
#
# Progress/log output goes to stderr; only the finished .ovpn content goes to
# stdout, so a single `ssh matt@host "add <name>"` call both generates and
# returns the profile in one shot — no separate scp/sftp session needed (and
# therefore nothing else to permit in authorized_keys).
#
# Install: place in ~/ alongside onboard-ai-node.sh, chmod +x, then add the
# corresponding authorized_keys entry documented in the handoff doc.

set -euo pipefail

read -r -a ARGS <<< "${SSH_ORIGINAL_COMMAND:-}"

if [[ "${ARGS[0]:-}" != "add" || -z "${ARGS[1]:-}" || ! "${ARGS[1]}" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
  echo "Rejected: only 'add <alphanumeric-hyphen-name>' is permitted via this key." >&2
  exit 1
fi

NAME="${ARGS[1]}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/onboard-ai-node.sh" add "$NAME" 1>&2

OVPN_FILE="$SCRIPT_DIR/ai-node-ovpns/ai-node-${NAME}.ovpn"
if [[ ! -f "$OVPN_FILE" ]]; then
  echo "Error: onboard-ai-node.sh reported success but $OVPN_FILE is missing." >&2
  exit 1
fi

cat "$OVPN_FILE"
