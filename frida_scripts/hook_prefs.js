/**
 * hook_prefs.js
 *
 * Frida script – intercept NSUserDefaults and CFPreferences read/write calls
 * so you can inspect and override in-app preference values at runtime.
 *
 * Attach:
 *   frida -H <ngrok-host>:<ngrok-port> -n AppName -l frida_scripts/hook_prefs.js
 *
 * Configuration (edit OVERRIDES below):
 *   Key   – NSUserDefaults key to override
 *   Value – replacement value (as a JavaScript string; coerced to NSString)
 */

"use strict";

// ── Personalisation overrides ─────────────────────────────────────────────────
// Add entries here to silently substitute values whenever the app reads them.
//
// Example:
//   { key: "isPremiumUser", value: "1" },
//   { key: "theme",         value: "dark" },
const OVERRIDES = [
    // { key: "exampleKey", value: "exampleValue" },
];
// ─────────────────────────────────────────────────────────────────────────────

const overrideMap = {};
for (const entry of OVERRIDES) {
    overrideMap[entry.key] = entry.value;
}

// ── NSUserDefaults ────────────────────────────────────────────────────────────

const NSUserDefaults = ObjC.classes.NSUserDefaults;

// -objectForKey:
Interceptor.attach(
    NSUserDefaults["- objectForKey:"].implementation,
    {
        onEnter(args) {
            this.key = ObjC.Object(args[2]).toString();
        },
        onLeave(retval) {
            const override = overrideMap[this.key];
            if (override !== undefined) {
                const ns = ObjC.classes.NSString.stringWithString_(override);
                retval.replace(ns.handle);
                console.log(`[prefs] ◀ objectForKey:"${this.key}" → overridden to "${override}"`);
            } else {
                const val = retval.isNull() ? "(nil)" : ObjC.Object(retval).toString();
                console.log(`[prefs] ◀ objectForKey:"${this.key}" → ${val}`);
            }
        }
    }
);

// -setObject:forKey:
Interceptor.attach(
    NSUserDefaults["- setObject:forKey:"].implementation,
    {
        onEnter(args) {
            const obj = args[2].isNull() ? "(nil)" : ObjC.Object(args[2]).toString();
            const key = ObjC.Object(args[3]).toString();
            console.log(`[prefs] ▶ setObject:${obj} forKey:"${key}"`);
        }
    }
);

// ── CFPreferences (lower-level) ───────────────────────────────────────────────

const CFPreferencesCopyAppValue = Module.findExportByName(
    "CoreFoundation", "CFPreferencesCopyAppValue"
);

if (CFPreferencesCopyAppValue) {
    Interceptor.attach(CFPreferencesCopyAppValue, {
        onEnter(args) {
            try {
                this.key = new ObjC.Object(args[0]).toString();
            } catch (_) {
                this.key = args[0].toString();
            }
        },
        onLeave(retval) {
            const override = overrideMap[this.key];
            if (override !== undefined) {
                const ns = ObjC.classes.NSString.stringWithString_(override);
                retval.replace(ns.handle);
                console.log(`[cfprefs] ◀ CFPreferencesCopyAppValue("${this.key}") → overridden to "${override}"`);
            } else {
                const val = retval.isNull()
                    ? "(nil)"
                    : new ObjC.Object(retval).toString();
                console.log(`[cfprefs] ◀ CFPreferencesCopyAppValue("${this.key}") → ${val}`);
            }
        }
    });
}

console.log("[frida] hook_prefs.js loaded – monitoring preferences …");
