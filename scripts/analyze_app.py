#!/usr/bin/env python3
"""
analyze_app.py
Static analysis of an extracted iOS IPA:
  - List all binaries and shared libraries
  - Dump Objective-C class/method headers via class-dump
  - Print entitlements embedded in the main binary
  - Extract readable strings longer than 6 characters
  - Show linked frameworks and dylibs

Usage:
    python scripts/analyze_app.py <path-to.ipa> [--output-dir DIR]
"""

import argparse
import os
import plistlib
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def run(cmd: list[str], *, check: bool = False, capture: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=capture, text=True, check=check)


def require_tool(name: str) -> None:
    if shutil.which(name) is None:
        print(f"[!] '{name}' not found in PATH – skipping steps that need it.", file=sys.stderr)


def extract_ipa(ipa_path: Path, dest: Path) -> Path:
    """Unzip the IPA and return the path to the .app bundle."""
    with zipfile.ZipFile(ipa_path) as zf:
        zf.extractall(dest)
    payload = dest / "Payload"
    apps = list(payload.glob("*.app"))
    if not apps:
        raise RuntimeError("No .app bundle found inside Payload/")
    return apps[0]


def find_main_binary(app_bundle: Path) -> Path | None:
    """Return the path to the main Mach-O binary (same name as the .app folder)."""
    candidate = app_bundle / app_bundle.stem
    if candidate.exists():
        return candidate
    # Fallback: first file whose name matches Info.plist CFBundleExecutable
    info = app_bundle / "Info.plist"
    if info.exists():
        with open(info, "rb") as f:
            plist = plistlib.load(f)
        exe = plist.get("CFBundleExecutable")
        if exe:
            return app_bundle / exe
    return None


# ---------------------------------------------------------------------------
# Analysis steps
# ---------------------------------------------------------------------------

def print_info_plist(app_bundle: Path) -> None:
    info = app_bundle / "Info.plist"
    if not info.exists():
        return
    with open(info, "rb") as f:
        plist = plistlib.load(f)
    keys = ["CFBundleIdentifier", "CFBundleDisplayName", "CFBundleVersion",
            "CFBundleShortVersionString", "MinimumOSVersion", "UIDeviceFamily"]
    print("\n── Info.plist ──────────────────────────────────────────────────")
    for k in keys:
        if k in plist:
            print(f"  {k}: {plist[k]}")


def print_entitlements(binary: Path) -> None:
    print("\n── Entitlements ────────────────────────────────────────────────")
    result = run(["codesign", "-d", "--entitlements", "-", str(binary)])
    if result.returncode == 0 and result.stdout.strip():
        print(result.stdout)
    else:
        # Try ldid
        result2 = run(["ldid", "-e", str(binary)])
        if result2.returncode == 0 and result2.stdout.strip():
            print(result2.stdout)
        else:
            print("  (could not read entitlements – install codesign or ldid)")


def print_linked_libraries(binary: Path) -> None:
    print("\n── Linked dylibs / frameworks ──────────────────────────────────")
    result = run(["otool", "-L", str(binary)])
    if result.returncode == 0:
        for line in result.stdout.splitlines()[1:]:
            print(" ", line.strip())
    else:
        print("  (otool not available)")


def dump_objc_headers(binary: Path, output_dir: Path) -> None:
    print("\n── Objective-C headers (class-dump) ────────────────────────────")
    headers_dir = output_dir / "headers"
    headers_dir.mkdir(exist_ok=True)
    result = run(["class-dump", "--arch", "arm64", "-H", "-o", str(headers_dir), str(binary)])
    if result.returncode == 0:
        headers = list(headers_dir.glob("*.h"))
        print(f"  Wrote {len(headers)} header(s) to {headers_dir}")
    else:
        print("  (class-dump not available or binary is encrypted – install class-dump)")
        if result.stderr:
            print(" ", result.stderr.strip())


def print_strings(binary: Path, min_len: int = 6) -> None:
    print(f"\n── Strings (length ≥ {min_len}) ────────────────────────────────────")
    result = run(["strings", "-a", "-n", str(min_len), str(binary)])
    if result.returncode == 0:
        lines = result.stdout.splitlines()
        # Show a capped sample to avoid flooding the terminal
        cap = 200
        for line in lines[:cap]:
            print(" ", line)
        if len(lines) > cap:
            print(f"  … ({len(lines) - cap} more lines – see full output in analysis directory)")
    else:
        print("  (strings utility not found)")


def list_all_binaries(app_bundle: Path) -> None:
    print("\n── All Mach-O binaries ─────────────────────────────────────────")
    for root, _dirs, files in os.walk(app_bundle):
        for fname in files:
            fpath = Path(root) / fname
            result = run(["file", str(fpath)])
            if result.returncode == 0 and "Mach-O" in result.stdout:
                print(" ", fpath.relative_to(app_bundle.parent.parent))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description="Static analysis of an iOS IPA")
    parser.add_argument("ipa", help="Path to the .ipa file")
    parser.add_argument("--output-dir", default="analysis", help="Directory for generated artifacts (default: analysis/)")
    args = parser.parse_args()

    ipa_path = Path(args.ipa).resolve()
    if not ipa_path.exists():
        print(f"[-] File not found: {ipa_path}", file=sys.stderr)
        sys.exit(1)

    output_dir = Path(args.output_dir).resolve()
    output_dir.mkdir(parents=True, exist_ok=True)

    for tool in ("otool", "strings", "file", "class-dump"):
        require_tool(tool)

    with tempfile.TemporaryDirectory(prefix="re_analyze_") as tmpdir:
        tmp = Path(tmpdir)
        print(f"[*] Extracting {ipa_path.name} …")
        app_bundle = extract_ipa(ipa_path, tmp)
        print(f"[+] App bundle: {app_bundle.name}")

        print_info_plist(app_bundle)
        list_all_binaries(app_bundle)

        binary = find_main_binary(app_bundle)
        if binary is None:
            print("[-] Could not locate main binary.", file=sys.stderr)
            sys.exit(1)

        print(f"\n[*] Main binary: {binary.name}")
        print_entitlements(binary)
        print_linked_libraries(binary)
        dump_objc_headers(binary, output_dir)
        print_strings(binary)

    print(f"\n[+] Analysis artifacts written to: {output_dir}")


if __name__ == "__main__":
    main()
