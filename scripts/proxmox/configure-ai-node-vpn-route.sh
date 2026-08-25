#!/usr/bin/env bash
set -euo pipefail

SERVICE_NAME="fitznet-ai-node-vpn-route.service"
VPN_SUBNET="${1:-${FITZNET_VPN_SUBNET:-}}"
VPN_GATEWAY="${2:-${FITZNET_VPN_GATEWAY:-}}"
NODE_ADDRESS="${3:-}"

usage() {
  cat <<'EOF'
Usage: sudo ./configure-ai-node-vpn-route.sh <vpn-subnet> <openvpn-server-lan-ip> [node-vpn-ip]

Example:
  sudo ./configure-ai-node-vpn-route.sh 10.180.53.0/24 192.168.1.150 10.180.53.6

The route is applied immediately and persisted with a small systemd oneshot
service. If a node address is supplied, its Ollama /api/tags endpoint is also
checked from this Docker host.
EOF
}

if [[ ${EUID} -ne 0 ]]; then
  echo "Run this script with sudo so it can update routes and systemd." >&2
  exit 1
fi

if [[ ! "${VPN_SUBNET}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] ||
   [[ ! "${VPN_GATEWAY}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  usage >&2
  exit 2
fi

if [[ -n "${NODE_ADDRESS}" ]] &&
   [[ ! "${NODE_ADDRESS}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
  usage >&2
  exit 2
fi

IP_COMMAND="$(command -v ip)"
SYSTEMCTL_COMMAND="$(command -v systemctl)"
CURL_COMMAND="$(command -v curl || true)"
UNIT_PATH="/etc/systemd/system/${SERVICE_NAME}"

# Let iproute2 perform full address/gateway validation before writing a unit.
"${IP_COMMAND}" route replace "${VPN_SUBNET}" via "${VPN_GATEWAY}"

cat > "${UNIT_PATH}" <<EOF
[Unit]
Description=Route Fitz-Net AI node traffic through the OpenVPN server
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=${IP_COMMAND} route replace ${VPN_SUBNET} via ${VPN_GATEWAY}
ExecStop=${IP_COMMAND} route del ${VPN_SUBNET} via ${VPN_GATEWAY}

[Install]
WantedBy=multi-user.target
EOF

"${SYSTEMCTL_COMMAND}" daemon-reload
"${SYSTEMCTL_COMMAND}" enable --now "${SERVICE_NAME}"

echo "Installed persistent route:"
"${IP_COMMAND}" route show "${VPN_SUBNET}"

if [[ -n "${NODE_ADDRESS}" ]]; then
  if [[ -z "${CURL_COMMAND}" ]]; then
    echo "Route installed, but curl is unavailable; skipping the node reachability check." >&2
    exit 0
  fi

  echo "Checking Ollama at ${NODE_ADDRESS}:11434..."
  "${CURL_COMMAND}" --fail --show-error --silent --connect-timeout 5 \
    "http://${NODE_ADDRESS}:11434/api/tags"
  echo
  echo "The Docker host can reach the AI node."
fi
