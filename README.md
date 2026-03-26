# reverse-engineer

A toolkit for reverse engineering and personalising iOS apps on a jailbroken iPhone via a remote SSH session over an ngrok tunnel.

## Target environment

| Item | Value |
|------|-------|
| Device | iPhone 7 |
| iOS version | 15.8.5 |
| Jailbreak | Dopamine |
| Remote access | SSH → ngrok TCP tunnel |

## Requirements

### On your workstation

* macOS or Linux
* Python ≥ 3.9
* [ngrok](https://ngrok.com/) CLI (authenticated)
* `sshpass` (optional – avoids repeated password prompts)
* `ldid` – for re-signing binaries (`brew install ldid`)
* `class-dump` – for ObjC header extraction
* Install Python dependencies:

```bash
pip install -r requirements.txt
```

### On the jailbroken device (via Sileo / Cydia)

* OpenSSH
* Frida (add the official Frida repo: `https://build.frida.re`)
* `ldid` tweak or `appinst`
* `ipainstaller` or `AppSync Unified`

---

## Workflow overview

```
Workstation  ──SSH──▶  ngrok TCP endpoint  ──▶  iPhone (sshd :22)
                                                      │
                                          frida-server (port 27042)
```

1. **[Start ngrok tunnel on device](docs/workflow.md#1-start-ngrok-on-device)** – expose the device's SSH port through an ngrok TCP tunnel.
2. **[Connect via SSH](scripts/connect_device.sh)** – establish an interactive SSH session or run remote commands.
3. **[Extract the target app](scripts/extract_app.sh)** – decrypt and download the `.ipa` to your workstation.
4. **[Static analysis](scripts/analyze_app.py)** – inspect headers, entitlements, strings and linked libraries.
5. **[Dynamic analysis](frida_scripts/)** – hook methods and read/write runtime state with Frida.
6. **[Patch & re-sign](scripts/patch_app.sh)** – apply your personalisation, re-sign the binary and sideload.

See **[docs/workflow.md](docs/workflow.md)** for the full step-by-step guide.

---

## Quick start

```bash
# 1. Set environment variables (or export them in ~/.bashrc)
export NGROK_TCP_ADDR="0.tcp.ngrok.io"   # hostname printed by ngrok
export NGROK_TCP_PORT="12345"            # port  printed by ngrok
export DEVICE_USER="root"                # default Dopamine SSH user
export DEVICE_PASS="alpine"              # change this immediately!

# 2. Open SSH session
./scripts/connect_device.sh

# 3. Extract an app (bundle ID required)
./scripts/extract_app.sh com.example.targetapp

# 4. Run static analysis on the extracted IPA
python scripts/analyze_app.py output/com.example.targetapp.ipa

# 5. Attach Frida and trace Objective-C methods
frida -H "$NGROK_TCP_ADDR:$NGROK_TCP_PORT" \
      -n TargetApp \
      -l frida_scripts/trace_methods.js

# 6. Patch and re-sign
./scripts/patch_app.sh output/com.example.targetapp.ipa
```

---

## Security notes

* Change the default SSH password (`passwd`) **immediately** after jailbreaking.
* Use an ngrok auth token so the tunnel is tied to your account.
* These tools are intended for **personal use on your own device only**.
* Distributing modified apps may violate App Store guidelines and applicable law.
