#!/usr/bin/env bash
# patch_app.sh
# Apply binary patches to an extracted IPA, re-sign with ldid,
# and sideload the modified app back onto the jailbroken device.
#
# Usage:
#   ./scripts/patch_app.sh <path-to.ipa> [patch-script.py]
#
# The optional patch script receives the path to the unpacked .app folder as
# its first argument and may modify any files inside it before re-packaging.
#
# Required environment variables (same as connect_device.sh):
#   NGROK_TCP_ADDR, NGROK_TCP_PORT, DEVICE_USER, DEVICE_PASS
#
# Required tools (workstation):
#   ldid, zip/unzip

set -euo pipefail

IPA_PATH="${1:?Usage: $0 <path-to.ipa> [patch-script.py]}"
PATCH_SCRIPT="${2:-}"
OUTPUT_DIR="${OUTPUT_DIR:-output}"

NGROK_TCP_ADDR="${NGROK_TCP_ADDR:?Set NGROK_TCP_ADDR}"
NGROK_TCP_PORT="${NGROK_TCP_PORT:?Set NGROK_TCP_PORT}"
DEVICE_USER="${DEVICE_USER:-root}"
DEVICE_PASS="${DEVICE_PASS:-alpine}"

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

# ── Unpack ────────────────────────────────────────────────────────────────────
WORK_DIR=$(mktemp -d /tmp/re_patch_XXXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

echo "[*] Unpacking ${IPA_PATH} …"
unzip -q "$IPA_PATH" -d "$WORK_DIR"
APP_BUNDLE=$(find "$WORK_DIR/Payload" -maxdepth 1 -name "*.app" | head -1)
if [ -z "$APP_BUNDLE" ]; then
  echo "[-] No .app bundle found in Payload/" >&2
  exit 1
fi
echo "[+] App bundle: $(basename "$APP_BUNDLE")"

# ── Apply user patch script ───────────────────────────────────────────────────
if [ -n "$PATCH_SCRIPT" ] && [ -f "$PATCH_SCRIPT" ]; then
  echo "[*] Running patch script: ${PATCH_SCRIPT} ..."
  python3 "$PATCH_SCRIPT" "$APP_BUNDLE"
  echo "[+] Patch script finished."
else
  echo "[!] No patch script provided – continuing with unmodified app."
fi

# ── Re-sign all Mach-O binaries with ldid ─────────────────────────────────────
echo "[*] Re-signing binaries with ldid …"
if ! command -v ldid &>/dev/null; then
  echo "[-] ldid not found. Install it with: brew install ldid" >&2
  exit 1
fi

# Gather entitlements from the main binary before wiping signatures
MAIN_BIN="${APP_BUNDLE}/$(python3 -c "import plistlib,sys; d=plistlib.load(open(sys.argv[1],'rb')); print(d.get('CFBundleExecutable',''))" "${APP_BUNDLE}/Info.plist" 2>/dev/null || basename "$APP_BUNDLE" .app)"
ENTITLEMENTS_FILE="${WORK_DIR}/entitlements.plist"
ldid -e "$MAIN_BIN" > "$ENTITLEMENTS_FILE" 2>/dev/null || echo "<dict/>" > "$ENTITLEMENTS_FILE"

find "$APP_BUNDLE" -type f | while read -r bin; do
  file_type=$(file -b "$bin" 2>/dev/null || true)
  if echo "$file_type" | grep -q "Mach-O"; then
    ldid -S"${ENTITLEMENTS_FILE}" "$bin"
    echo "  Signed: $(basename "$bin")"
  fi
done

# ── Repack ────────────────────────────────────────────────────────────────────
IPA_BASENAME=$(basename "$IPA_PATH" .ipa)
PATCHED_IPA="${OUTPUT_DIR}/${IPA_BASENAME}_patched.ipa"
mkdir -p "$OUTPUT_DIR"

echo "[*] Repacking IPA …"
(cd "$WORK_DIR" && zip -qr - Payload) > "$PATCHED_IPA"
echo "[+] Patched IPA: ${PATCHED_IPA}"

# ── Push to device and install ────────────────────────────────────────────────
REMOTE_IPA="/tmp/${IPA_BASENAME}_patched.ipa"
echo "[*] Uploading to device …"
run_scp "$PATCHED_IPA" "${DEVICE_USER}@${NGROK_TCP_ADDR}:${REMOTE_IPA}"

echo "[*] Installing on device …"
if run_ssh "command -v ipainstaller" &>/dev/null; then
  run_ssh "ipainstaller '${REMOTE_IPA}'"
elif run_ssh "command -v appinst" &>/dev/null; then
  run_ssh "appinst '${REMOTE_IPA}'"
else
  echo "[!] No installer found on device (ipainstaller / appinst)."
  echo "    The IPA has been uploaded to ${REMOTE_IPA} – install it manually."
fi

echo "[+] Done."
