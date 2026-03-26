#!/usr/bin/env bash
# extract_app.sh
# Decrypt a running App Store binary on the jailbroken device and pull the
# resulting IPA to the workstation via SCP over the ngrok tunnel.
#
# Usage:
#   ./scripts/extract_app.sh <bundle-id>
#
# Example:
#   ./scripts/extract_app.sh com.example.targetapp
#
# Prerequisites on device (install via Sileo/Cydia):
#   • frida-server  – used to locate the app container
#   • frida-ios-dump (https://github.com/AloneMonkey/frida-ios-dump)
#     OR clutch / bfdecrypt for decryption
#
# Required environment variables (same as connect_device.sh):
#   NGROK_TCP_ADDR, NGROK_TCP_PORT, DEVICE_USER, DEVICE_PASS

set -euo pipefail

BUNDLE_ID="${1:?Usage: $0 <bundle-id>}"

NGROK_TCP_ADDR="${NGROK_TCP_ADDR:?Set NGROK_TCP_ADDR}"
NGROK_TCP_PORT="${NGROK_TCP_PORT:?Set NGROK_TCP_PORT}"
DEVICE_USER="${DEVICE_USER:-root}"
DEVICE_PASS="${DEVICE_PASS:-alpine}"
OUTPUT_DIR="${OUTPUT_DIR:-output}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -p ${NGROK_TCP_PORT}"
SCP_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -P ${NGROK_TCP_PORT}"

run_ssh() {
  if command -v sshpass &>/dev/null; then
    # shellcheck disable=SC2086
    sshpass -p "$DEVICE_PASS" ssh $SSH_OPTS "${DEVICE_USER}@${NGROK_TCP_ADDR}" "$@"
  else
    # shellcheck disable=SC2086
    ssh $SSH_OPTS "${DEVICE_USER}@${NGROK_TCP_ADDR}" "$@"
  fi
}

run_scp() {
  if command -v sshpass &>/dev/null; then
    # shellcheck disable=SC2086
    sshpass -p "$DEVICE_PASS" scp $SCP_OPTS "$@"
  else
    # shellcheck disable=SC2086
    scp $SCP_OPTS "$@"
  fi
}

mkdir -p "$OUTPUT_DIR"

echo "[*] Locating bundle '${BUNDLE_ID}' on device..."
APP_PATH=$(run_ssh "find /var/containers/Bundle/Application -maxdepth 2 -name '*.app' 2>/dev/null | \
  while read p; do \
    id=\$(defaults read \"\$p/Info.plist\" CFBundleIdentifier 2>/dev/null); \
    [ \"\$id\" = '${BUNDLE_ID}' ] && echo \"\$p\" && break; \
  done")

if [ -z "$APP_PATH" ]; then
  echo "[-] App not found on device. Make sure the app is installed." >&2
  exit 1
fi
echo "[+] Found: ${APP_PATH}"

# Use frida-ios-dump if present, otherwise fall back to a manual tar approach
DUMP_SCRIPT="/usr/local/bin/dump.py"
IPA_NAME="${BUNDLE_ID}.ipa"
REMOTE_IPA="/tmp/${IPA_NAME}"

if run_ssh "[ -f '${DUMP_SCRIPT}' ]"; then
  echo "[*] Dumping with frida-ios-dump..."
  run_ssh "python3 '${DUMP_SCRIPT}' '${BUNDLE_ID}' -o '${REMOTE_IPA}'"
else
  echo "[!] frida-ios-dump not found – creating unencrypted archive (device-jailbroken decryption assumed via bfdecrypt/Clutch)."
  run_ssh "cd / && tar czf '${REMOTE_IPA}' --exclude='__MACOSX' '${APP_PATH}'"
fi

echo "[*] Pulling IPA to ${OUTPUT_DIR}/${IPA_NAME} ..."
run_scp "${DEVICE_USER}@${NGROK_TCP_ADDR}:${REMOTE_IPA}" "${OUTPUT_DIR}/${IPA_NAME}"

echo "[+] Done – saved to ${OUTPUT_DIR}/${IPA_NAME}"
