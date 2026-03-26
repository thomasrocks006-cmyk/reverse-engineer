# Reverse Engineering Workflow

Complete step-by-step guide for personalising iOS apps on a jailbroken iPhone 7
(iOS 15.8.5, Dopamine jailbreak) over an SSH session tunnelled through ngrok.

---

## 0 – Prerequisites

### Workstation
| Tool | Install |
|------|---------|
| ngrok | `brew install ngrok/ngrok/ngrok` |
| Python ≥ 3.9 | `brew install python` |
| frida-tools | `pip install frida-tools` |
| class-dump | `brew install class-dump` |
| ldid | `brew install ldid` |
| sshpass (optional) | `brew install sshpass` |
| otool / strings | Included in Xcode Command Line Tools |

```bash
pip install -r requirements.txt
chmod +x scripts/*.sh
```

### On the iPhone (via Sileo)
1. **OpenSSH** – enables SSH server
2. **Frida** – add repo `https://build.frida.re`, install *Frida*
3. **AppSync Unified** – allows installing unsigned IPAs
4. **ipainstaller** or **appinst** – CLI IPA installer
5. *(Optional)* **bfdecrypt** – passive IPA decryption tweak

> **Security** – change the root password immediately after jailbreaking:
> ```
> ssh root@<device-ip>
> passwd
> ```

---

## 1 – Start ngrok on device

ngrok must run on the **iPhone** so it can expose the device's SSH port (22).

### Option A – ngrok installed on the device

```bash
# On the device (via SSH on local Wi-Fi first)
ngrok config add-authtoken <YOUR_TOKEN>
ngrok tcp 22
```

ngrok will print something like:
```
Forwarding  tcp://0.tcp.ngrok.io:12345 -> localhost:22
```

### Option B – ngrok reverse tunnel from workstation

If ngrok cannot run on the device itself, use a local-forward trick:

```bash
# On workstation – forward device SSH through a local port, then tunnel
ssh -L 2222:localhost:22 root@<device-local-ip>  &
ngrok tcp 2222
```

---

## 2 – Connect via SSH

Export the tunnel details and open a session:

```bash
export NGROK_TCP_ADDR="0.tcp.ngrok.io"
export NGROK_TCP_PORT="12345"
export DEVICE_USER="root"
export DEVICE_PASS="alpine"   # change this!

./scripts/connect_device.sh
```

You now have an interactive root shell on the iPhone.

---

## 3 – Extract the target app

Make sure the app is **running** on the device (frida-ios-dump needs it spawned to decrypt):

```bash
./scripts/extract_app.sh com.example.targetapp
# → output/com.example.targetapp.ipa
```

If bfdecrypt is installed the decrypted IPA will appear automatically in
`/var/mobile/Documents/` after you open the app once; download it with:

```bash
scp -P $NGROK_TCP_PORT root@$NGROK_TCP_ADDR:/var/mobile/Documents/*.ipa output/
```

---

## 4 – Static analysis

```bash
python scripts/analyze_app.py output/com.example.targetapp.ipa --output-dir analysis/
```

This will print:
* App metadata from `Info.plist`
* Entitlements embedded in the binary
* Linked dylibs and frameworks
* Objective-C class/method headers (`analysis/headers/*.h`)
* Readable strings from the binary

Study the headers to understand the class structure before writing Frida scripts.

---

## 5 – Dynamic analysis with Frida

### 5a – Trace all Objective-C method calls

```bash
frida -H "$NGROK_TCP_ADDR:$NGROK_TCP_PORT" \
      -n TargetApp \
      -l frida_scripts/trace_methods.js
```

Edit `CLASS_FILTER` and `METHOD_FILTER` at the top of the script to narrow
the output to the class/method you care about.

### 5b – Intercept and override preferences

```bash
frida -H "$NGROK_TCP_ADDR:$NGROK_TCP_PORT" \
      -n TargetApp \
      -l frida_scripts/hook_prefs.js
```

Add your overrides to the `OVERRIDES` array in `hook_prefs.js`:

```js
const OVERRIDES = [
    { key: "isPremiumUser", value: "1" },
    { key: "theme",         value: "dark" },
];
```

### 5c – Interactive REPL

```bash
frida -H "$NGROK_TCP_ADDR:$NGROK_TCP_PORT" -n TargetApp
```

Useful REPL snippets:

```js
// List all classes whose name contains "Login"
Object.keys(ObjC.classes).filter(c => c.includes("Login"))

// Call a class method
ObjC.classes.NSUserDefaults.standardUserDefaults().objectForKey_("theme")

// Read a file on device
var NSString = ObjC.classes.NSString;
NSString.stringWithContentsOfFile_encoding_error_(
    "/var/mobile/Library/Preferences/com.example.targetapp.plist", 4, NULL)
```

---

## 6 – Patch and personalise

Write a Python patch script that receives the `.app` folder path:

```python
# patches/my_patch.py
import sys, pathlib, struct

app = pathlib.Path(sys.argv[1])

# Example: replace a string in the binary
binary = app / "TargetApp"
data = binary.read_bytes()
data = data.replace(b"isPremiumUser\x00", b"alwaysPremium\x00")
binary.write_bytes(data)
print("[patch] Applied premium override")
```

Then run:

```bash
./scripts/patch_app.sh output/com.example.targetapp.ipa patches/my_patch.py
```

This will:
1. Unpack the IPA
2. Run your patch script
3. Re-sign all Mach-O binaries with `ldid`
4. Repack the IPA
5. Upload it to the device and install via `ipainstaller`

---

## 7 – Persistence (optional)

To make Frida overrides persistent without re-running the script every launch,
package them as a **Theos tweak**:

```bash
# On the device
apt-get install theos   # or install via Sileo
nic.pl                  # scaffold a new tweak
```

See the [Theos wiki](https://theos.dev/docs/) for details.

---

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `ssh: connect to host … port 22: Connection refused` | Check ngrok is running on device; verify `NGROK_TCP_PORT` |
| `frida.InvalidArgumentError: process not found` | App must be in the foreground; check the exact process name with `frida-ps -H …` |
| `class-dump: error: can't get Objective-C…` | Binary is still encrypted – use bfdecrypt or frida-ios-dump to decrypt first |
| `ldid: …: No such file or directory` | Install ldid: `brew install ldid` |
| App crashes after patching | Check you haven't corrupted alignment; use `install_name_tool -id` to verify |
