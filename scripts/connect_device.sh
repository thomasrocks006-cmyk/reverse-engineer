#!/usr/bin/env bash
# connect_device.sh
# Open an interactive SSH session to the jailbroken iPhone via an ngrok TCP tunnel.
#
# Required environment variables:
#   NGROK_TCP_ADDR  – ngrok TCP hostname (e.g. 0.tcp.ngrok.io)
#   NGROK_TCP_PORT  – ngrok TCP port    (e.g. 12345)
#
# Optional environment variables:
#   DEVICE_USER     – SSH username (default: root)
#   DEVICE_PASS     – SSH password (default: alpine)
#                     If sshpass is not installed the password prompt is shown.

set -euo pipefail

NGROK_TCP_ADDR="${NGROK_TCP_ADDR:?Set NGROK_TCP_ADDR to the ngrok hostname}"
NGROK_TCP_PORT="${NGROK_TCP_PORT:?Set NGROK_TCP_PORT to the ngrok port}"
DEVICE_USER="${DEVICE_USER:-root}"
DEVICE_PASS="${DEVICE_PASS:-alpine}"

SSH_OPTS=(
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o LogLevel=ERROR
  -p "$NGROK_TCP_PORT"
)

echo "[*] Connecting to ${DEVICE_USER}@${NGROK_TCP_ADDR}:${NGROK_TCP_PORT} ..."

if command -v sshpass &>/dev/null; then
  sshpass -p "$DEVICE_PASS" ssh "${SSH_OPTS[@]}" "${DEVICE_USER}@${NGROK_TCP_ADDR}" "$@"
else
  ssh "${SSH_OPTS[@]}" "${DEVICE_USER}@${NGROK_TCP_ADDR}" "$@"
fi
