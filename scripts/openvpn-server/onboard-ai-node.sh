#!/usr/bin/env bash
#
# Onboards (or revokes) a Fitz-Net AI worker node's OpenVPN client profile.
# Run this ON the Raspberry Pi (or whatever box) running your OpenVPN server.
#
# Auto-detects whether the server is managed by PiVPN or a plain
# OpenVPN + easy-rsa install and does the right thing either way.
#
# Usage:
#   ./onboard-ai-node.sh add <node-name>       # e.g. ./onboard-ai-node.sh add brother-pc
#   ./onboard-ai-node.sh revoke <node-name>
#
# Env overrides (only used in the plain easy-rsa path; ignored under PiVPN):
#   EASYRSA_DIR       - path to your easy-rsa directory (auto-detected if unset)
#   CLIENT_TEMPLATE   - path to your base client .ovpn template (auto-detected if unset)
#   OUTPUT_DIR        - where to write the finished .ovpn (default: ./ai-node-ovpns)
#
# The output .ovpn is a SPLIT-TUNNEL profile expectation: this script does not
# add or strip `redirect-gateway` for you. Check your CLIENT_TEMPLATE (or
# PiVPN's client-common.txt) doesn't push a full-tunnel/redirect-gateway route
# before handing this off — see docs/openvpn-ai-node-handoff.md for why.

set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-./ai-node-ovpns}"

usage() {
  echo "Usage: $0 add <node-name>" >&2
  echo "       $0 revoke <node-name>" >&2
  exit 1
}

[[ $# -eq 2 ]] || usage
ACTION="$1"
RAW_NAME="$2"

# Sanitize: lowercase alnum + hyphen only, so cert/file names stay predictable
if [[ ! "$RAW_NAME" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]*$ ]]; then
  echo "Error: node name must be alphanumeric/hyphen only (got: $RAW_NAME)" >&2
  exit 1
fi
NAME="ai-node-${RAW_NAME}"

log() { echo ">> $*"; }

detect_mode() {
  if command -v pivpn >/dev/null 2>&1; then
    echo "pivpn"
    return
  fi

  local candidates=(
    "/etc/openvpn/easy-rsa"
    "/etc/openvpn/server/easy-rsa"
    "$HOME/easy-rsa"
    "$HOME/openvpn-ca"
  )
  if [[ -n "${EASYRSA_DIR:-}" ]]; then
    echo "easyrsa"
    return
  fi
  for dir in "${candidates[@]}"; do
    if [[ -d "$dir" ]]; then
      echo "easyrsa"
      return
    fi
  done

  echo "unknown"
}

find_easyrsa_dir() {
  if [[ -n "${EASYRSA_DIR:-}" ]]; then
    echo "$EASYRSA_DIR"
    return
  fi
  local candidates=(
    "/etc/openvpn/easy-rsa"
    "/etc/openvpn/server/easy-rsa"
    "$HOME/easy-rsa"
    "$HOME/openvpn-ca"
  )
  for dir in "${candidates[@]}"; do
    if [[ -d "$dir" ]]; then
      echo "$dir"
      return
    fi
  done
  echo "Error: couldn't auto-detect your easy-rsa directory. Set EASYRSA_DIR=/path/to/easy-rsa and retry." >&2
  exit 1
}

find_client_template() {
  if [[ -n "${CLIENT_TEMPLATE:-}" ]]; then
    echo "$CLIENT_TEMPLATE"
    return
  fi
  local candidates=(
    "/etc/openvpn/client-common.txt"
    "/etc/openvpn/base.conf"
    "/etc/openvpn/client-template.txt"
    "$HOME/client-common.txt"
  )
  for f in "${candidates[@]}"; do
    if [[ -f "$f" ]]; then
      echo "$f"
      return
    fi
  done
  echo "Error: couldn't auto-detect your base client template. Set CLIENT_TEMPLATE=/path/to/template and retry." >&2
  exit 1
}

# ── PiVPN path ───────────────────────────────────────────────────────────────
pivpn_add() {
  log "Detected PiVPN. Adding client '$NAME' (no passphrase, unattended)..."
  pivpn add nopass -n "$NAME" -d "${CERT_DAYS:-3650}"

  log "Looking for the generated .ovpn..."
  local found
  found=$(find /home/*/ovpns "$HOME/ovpns" -maxdepth 1 -name "${NAME}.ovpn" 2>/dev/null | head -n1 || true)
  if [[ -z "$found" ]]; then
    echo "Error: PiVPN reported success but I couldn't find ${NAME}.ovpn under */ovpns/. Check PiVPN's output above and copy it manually." >&2
    exit 1
  fi

  mkdir -p "$OUTPUT_DIR"
  cp "$found" "$OUTPUT_DIR/${NAME}.ovpn"
  log "Done. Profile written to: $OUTPUT_DIR/${NAME}.ovpn"
}

pivpn_revoke() {
  log "Detected PiVPN. Revoking client '$NAME'..."
  pivpn revoke --yes "$NAME"
  log "Revoked. PiVPN restarts the OpenVPN service automatically."
}

# ── Plain easy-rsa path ──────────────────────────────────────────────────────
easyrsa_add() {
  local easyrsa_dir template
  easyrsa_dir=$(find_easyrsa_dir)
  template=$(find_client_template)

  log "Using easy-rsa dir: $easyrsa_dir"
  log "Using client template: $template"
  log "Building client certificate for '$NAME'..."

  (cd "$easyrsa_dir" && ./easyrsa build-client-full "$NAME" nopass)

  mkdir -p "$OUTPUT_DIR"
  local out="$OUTPUT_DIR/${NAME}.ovpn"

  log "Assembling single-file profile: $out"
  {
    cat "$template"
    echo "<ca>"
    cat "$easyrsa_dir/pki/ca.crt"
    echo "</ca>"
    echo "<cert>"
    sed -ne '/BEGIN CERTIFICATE/,$ p' "$easyrsa_dir/pki/issued/${NAME}.crt"
    echo "</cert>"
    echo "<key>"
    cat "$easyrsa_dir/pki/private/${NAME}.key"
    echo "</key>"
  } > "$out"

  log "Done. Profile written to: $out"
}

easyrsa_revoke() {
  local easyrsa_dir
  easyrsa_dir=$(find_easyrsa_dir)

  log "Using easy-rsa dir: $easyrsa_dir"
  log "Revoking client certificate for '$NAME'..."
  (cd "$easyrsa_dir" && ./easyrsa revoke "$NAME" && ./easyrsa gen-crl)

  log "Revoked and regenerated the CRL."
  log "Reload/restart your OpenVPN server so it picks up the new CRL, e.g.:"
  echo "     sudo systemctl restart openvpn@server   # adjust unit name to match your setup"
}

# ── Dispatch ─────────────────────────────────────────────────────────────────
MODE=$(detect_mode)

case "$MODE" in
  pivpn)
    case "$ACTION" in
      add)    pivpn_add ;;
      revoke) pivpn_revoke ;;
      *)      usage ;;
    esac
    ;;
  easyrsa)
    case "$ACTION" in
      add)    easyrsa_add ;;
      revoke) easyrsa_revoke ;;
      *)      usage ;;
    esac
    ;;
  *)
    echo "Error: couldn't detect PiVPN or a plain easy-rsa setup." >&2
    echo "  - If this IS PiVPN, make sure the 'pivpn' command is on PATH for this user (try: sudo -E env PATH=\"\$PATH\" $0 $ACTION $RAW_NAME)." >&2
    echo "  - If this is a plain OpenVPN + easy-rsa setup, set EASYRSA_DIR and CLIENT_TEMPLATE explicitly, e.g.:" >&2
    echo "      EASYRSA_DIR=/etc/openvpn/easy-rsa CLIENT_TEMPLATE=/etc/openvpn/client-common.txt $0 $ACTION $RAW_NAME" >&2
    exit 1
    ;;
esac

if [[ "$ACTION" == "add" ]]; then
  echo ""
  echo "Next: copy $OUTPUT_DIR/${NAME}.ovpn off this Pi (e.g. scp) and rename it into"
  echo "your Fitz-Net checkout as scripts/ai-node-installer/<something>.ovpn before"
  echo "zipping the installer package. See that folder's README.md."
fi
