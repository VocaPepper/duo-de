# DUO-DE Connectivity patches

## 0001 — BpfNetMaps: guard local_net maps against null on BPF-less devices

Fixes the "soft reboot when updating or uninstalling an app" bug on the
Android 16 release (v2025.06.26 and later, `main-16`).

### Symptom

Updating or uninstalling any app restarts the system (the DUO-DE boot
animation shows and `system_server` comes back) while `adb shell uptime`
keeps increasing, i.e. it is a *soft* reboot / `SYSTEM_RESTART`, not a
cold reboot. Installing an app for the first time does **not** trigger it.

`logcat` / `dropbox` show:

```
FATAL EXCEPTION IN SYSTEM PROCESS: ConnectivityServiceThread
java.lang.RuntimeException: Error receiving broadcast
    Intent { act=android.intent.action.PACKAGE_REMOVED ... }
Caused by: java.lang.NullPointerException: Attempt to invoke interface method
    'boolean ...IBpfMap.deleteEntry(...)' on a null object reference
    at ...BpfNetMaps.removeUidFromLocalNetBlockMap(BpfNetMaps.java:1074)
    at ...connectivity.PermissionMonitor.onPackageRemoved(PermissionMonitor.java:918)
```

### Root cause

The Surface Duo 1 kernel is 4.14 (`4.14.190-duo-...`), which is BPF-less.
`bpfloader` is stopped (`init.svc.bpfloader=stopped`,
`ro.fuse.bpf.is_running=false`).

While initialising `BpfNetMaps`, `initBpfMaps()` throws
`IllegalStateException: Cannot open local_net_access map`. The TrebleDroid
patch `0009-Some-additional-handling-of-bpf-less-device.patch` wraps
`ensureInitialized()` in a `try/catch`, so the exception is swallowed and
every not-yet-initialised static map — including
`sLocalNetAccessMap` and `sLocalNetBlockedUidMap` — is left `null`.

Patch 0009 only added null guards for `addLocalNetAccess()` and
`removeLocalNetAccess()`. `PermissionMonitor.onPackageRemoved()` calls
`removeUidFromLocalNetBlockMap()`, which dereferences
`sLocalNetBlockedUidMap` without a guard, so the
`ACTION_PACKAGE_REMOVED` broadcast (sent for uninstall *and* for the
"replace" step of an update) crashed `system_server`.

A15 is not affected: `BpfNetMaps` there has no `local_net_*` maps at all
(they were introduced for 25Q2 / API 36).

### Fix

Apply the same null-guard pattern to the remaining `local_net_*` accessors:

* `getLocalNetAccess()` → return `true`
* `addUidToLocalNetBlockMap()` → return
* `isUidBlockedFromUsingLocalNetwork()` → return `false`
* `removeUidFromLocalNetBlockMap()` → return

On a BPF-less device the local-network-blocking feature is simply a no-op
instead of crashing the system. The patch is applied *after* the
TrebleDroid connectivity patches (`patches/duo` is applied last), so it
diffs against the already-patched `BpfNetMaps.java`.
