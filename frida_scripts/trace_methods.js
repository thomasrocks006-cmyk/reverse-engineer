/**
 * trace_methods.js
 *
 * Frida script – dynamic Objective-C method tracing.
 *
 * Attach to a running app:
 *   frida -H <ngrok-host>:<ngrok-port> -n AppName -l frida_scripts/trace_methods.js
 *
 * Or spawn it:
 *   frida -H <ngrok-host>:<ngrok-port> -f com.example.app -l frida_scripts/trace_methods.js --no-pause
 *
 * Configuration (edit the constants below):
 *   CLASS_FILTER   – substring match on class name  (empty = all classes)
 *   METHOD_FILTER  – substring match on method name (empty = all methods)
 *   MAX_DEPTH      – stop tracing nested calls deeper than this level
 */

"use strict";

const CLASS_FILTER  = "";   // e.g. "ViewController"
const METHOD_FILTER = "";   // e.g. "viewDidLoad"
const MAX_DEPTH     = 5;

// ── Helpers ──────────────────────────────────────────────────────────────────

function shouldTrace(className, methodName) {
    if (CLASS_FILTER  && !className.includes(CLASS_FILTER))   return false;
    if (METHOD_FILTER && !methodName.includes(METHOD_FILTER)) return false;
    return true;
}

function indent(depth) {
    return "  ".repeat(depth);
}

// ── Main ─────────────────────────────────────────────────────────────────────

// Track call depth per native thread ID to handle concurrent / recursive calls
const depthMap = {};

function getDepth() {
    const tid = Process.getCurrentThreadId();
    return depthMap[tid] || 0;
}

function incDepth() {
    const tid = Process.getCurrentThreadId();
    depthMap[tid] = (depthMap[tid] || 0) + 1;
    return depthMap[tid];
}

function decDepth() {
    const tid = Process.getCurrentThreadId();
    if ((depthMap[tid] || 0) > 0) depthMap[tid]--;
}

function hookClass(className) {
    const klass = ObjC.classes[className];
    if (!klass) return;

    const methods = klass.$ownMethods;
    for (const method of methods) {
        if (!shouldTrace(className, method)) continue;

        try {
            const impl = klass[method];
            Interceptor.attach(impl.implementation, {
                onEnter(args) {
                    if (getDepth() >= MAX_DEPTH) return;
                    const depth = incDepth();
                    const self = new ObjC.Object(args[0]);
                    const sel  = ObjC.selectorAsString(args[1]);
                    console.log(`${indent(depth)}▶ [${className} ${sel}]  self=${self}`);
                },
                onLeave(retval) {
                    const depth = getDepth();
                    if (depth <= 0) return;
                    console.log(`${indent(depth)}◀ [${className}] → ${retval}`);
                    decDepth();
                }
            });
        } catch (_) {
            // Some methods cannot be hooked – silently skip
        }
    }
}

// Enumerate all loaded Objective-C classes and hook matching ones
Object.keys(ObjC.classes).forEach(hookClass);

console.log("[frida] trace_methods.js loaded – waiting for calls …");
