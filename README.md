# OOM Adjuster

A Magisk/KernelSU/APatch module that protects important apps from Android's low-memory killer (LMKD) and provides a built-in WebUI for configuration.

## Supported root managers

- Magisk 29+
- Kitsune
- APatch
- KernelSU

---

## What it does

### OOM protection
Apps are protected in two tiers:

| Tier | `oom_score_adj` | Behaviour |
|---|---|---|
| **Critical** | -1000 | Never killed by the kernel OOM killer |
| **Restartable** | -999 | Can be killed under extreme pressure; expected to be restarted by root tools |

Every 100 ms, the native `oom_guardian` daemon scans running processes and enforces the correct score, cgroup assignment, and CPU priority for each protected app. A shell loop runs as an automatic fallback on unsupported architectures.

### Memory management
- Drops system caches when RAM usage exceeds 85%
- Compacts protected app memory under pressure
- Monitors swap usage and force-stops low-priority cached processes when swap exceeds 85%
- Pokémon GO memory killer — kills PoGo when system RAM exceeds 95% or PoGo's own RSS exceeds 3200 MB (configurable)
- LRU deprioritisation every 60 s — force-stops empty processes (procState 19) and raises `oom_score_adj` to 999 for background processes (procState 14–18)

### PolygonX watchdog (optional)
If enabled, automatically restarts PolygonX if it is killed. Clears app caches and drops system caches before restarting.

All actions are logged to `/data/adb/modules/oom_adjuster/oom_adjuster.log`.

---

## WebUI

Tap the **action button** in your root manager to open the configuration interface.

**KernelSU / APatch** — opens natively in the manager's built-in WebView.

**Magisk** — `action.sh` tries to open the WebUI in one of these apps (in order):
1. [KSU WebUI Standalone](https://github.com/5ec1cff/KsuWebUIStandalone)
2. [WebUI X (MMRL)](https://github.com/DerGoogler/MMRL)
3. MMRL

If none are installed, it automatically downloads and installs **KSU WebUI Standalone** from GitHub.

> ⚠️ **Magisk users:** when prompted, grant superuser access to the installer. Without it the download will be blocked and the WebUI will not open.

### Apps tab
- Set each app to **Off**, **-999 Restartable**, or **-1000 Critical**
- Suggested apps are listed with their default recommended tier
- Add any custom package name — saves immediately

### Device tab
- Phone model, Android version, kernel version, security patch date
- Live `oom_guardian` daemon status (native C or shell loop)
- Current `oom_score_adj` for PolygonX and Pokémon GO

### ART tab
Detects and displays the active ART APEX version dynamically (no hardcoded version strings).

Shows install status for `com.android.art` and `com.google.android.art`.

**Uninstall** downgrades the ART runtime to the built-in version:
1. Runs `pm uninstall` (no `--user 0`) — required for APEX packages
2. Falls back to `pm uninstall --user 0` if the first attempt fails
3. Disables `com.google.android.modulemetadata` if present (prevents scheduled ART updates)
4. On Android 15+ (API 35), also disables `com.google.android.gms/.update.SystemUpdateService` and `com.google.android.gms/.chimera.GmsIntentOperationService` to prevent silent GMS-driven reinstall

A reboot is required after uninstalling. Full command output is shown inline for debugging.

> ⚠️ Only uninstall ART if you know what you are doing.

---

## Configuration

Edit `/data/adb/modules/oom_adjuster/config.conf` directly or use the WebUI Apps tab.

```sh
# Apps that must never be killed
protected_apps_critical="com.evermorelabs.polygonx com.theappninjas.fakegpsjoystick com.anydesk.anydeskandroid com.evermorelabs.yamla"

# Apps that can be killed and will be restarted by root tools
protected_apps_restartable="com.nianticlabs.pokemongo"

# Watchdog — restarts PolygonX if killed
enable_watchdog=false

# PoGo memory killer
enable_pogo_killer=true
system_memory_threshold=95
pogo_memory_threshold_mb=3200
```

The legacy `protected_apps` field is still supported for backward compatibility.

---

## Install

1. Download the zip from [Releases](https://github.com/zwajton/OomAdjuster/releases)
2. Open your root manager (Magisk, APatch, KernelSU, etc.)
3. Go to **Modules → Install from storage**
4. Select the downloaded zip
5. Reboot


## Credits


**Credit:** [Furtif](https://github.com/Furtif) for the ART blockage fix.
