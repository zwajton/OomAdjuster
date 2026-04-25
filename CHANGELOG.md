Version 11.5
WebUI
- Added WebUI accessible via the action button in KernelSU, APatch, Magisk, and compatible managers
- Apps tab: toggle per-app protection tier (Off / -999 Restartable / -1000 Critical); suggested app list with one-tap enable; custom package field saves immediately on Add
- Device tab: phone model, Android version, kernel, security patch, live oom_guardian daemon status, and per-app oom_score_adj readout
- ART tab: dynamically detects installed APEX version at runtime (no hardcoded version strings); shows package status for com.android.art and com.google.android.art
- ART uninstall: tries pm uninstall without --user 0 first (required for APEX packages), falls back to --user 0 for regular packages
- ART uninstall: after uninstall, disables com.google.android.modulemetadata if present; on Android 15+ (API 35) also disables GMS SystemUpdateService and GmsIntentOperationService to prevent silent ART reinstall
- ART uninstall: full debug output shown inline so every command and its result is visible
- action.sh: opens WebUI in KSU WebUI Standalone, WebUI X, or MMRL (in that order); auto-downloads and installs KSU WebUI Standalone if none are found

OOM scoring
- Two-tier protection: critical apps get -1000 (never killed by kernel), restartable apps get -999 (can be killed and restarted by root tools)
- oom_guardian daemon rewritten to apply both tiers natively in C
- Shell fallback loop updated to match two-tier behaviour
- config.conf: protected_apps split into protected_apps_critical and protected_apps_restartable; legacy protected_apps field still honoured for backward compatibility

Version 11
- Replaced the 100ms shell OOM-protection loop with a native C daemon (oom_guardian), statically compiled for arm64 and arm32
- The daemon writes directly to /proc — no process forking, no shell overhead, immune to memory pressure stalls
- Shell loop is kept as an automatic fallback for unsupported architectures
- Added .gitattributes to enforce LF line endings and prevent boot failures on Windows-built zips

Version 10.5
- Rewrite of script

Version 10
- Removed phantom_fix.sh and phantom_fix.sh feature entirely (was disabled by default and unused)
- Fixed LRU deprioritizer: PolygonX and Pokémon GO are now always excluded from force-stop and oom_score_adj changes
- Fixed PolygonX anti-kill block: removed dead oom_score write (read-only in kernel) and replaced bash-only $RANDOM with a compatible counter
- Updated PoGo memory killer default threshold in docs to match actual value (3000MB)

Version 9.1
- Configurable features: Enable/disable watchdog and phantom_fix.sh via config.json
- Customizable thresholds: Adjust Pokémon GO Memory killer values in config.json
- Config location: /data/adb/modules/oom_adjuster/config.json

Version 9
Update for texture heavy events.
- Pokémon GO Memory Killer, Automatically kills PoGo when memory usage exceeds thresholds (95% system RAM or 2800MB PoGo usage)
- Fixed PolygonX Watchdog
- This version addresses the core issue of Pokémon Go memory consumption triggering system-wide LMKD kills

Version 8
Critical Fixes:
- Fixed oom_score_adj not being applied to protected processes
- Fixed renice priority not setting correctly
- Resolved process protection reliability issues
  
**Now properly prevents protected apps from being killed by the system**

Version 7
Dynamic Sleep Interval:
- Introduces a dynamic sleep_interval to make the module react faster to high memory usage (10 seconds instead of 30 seconds) by speeding up cache drops.
Faster OOM Adjustment:
- The main adjustment loop now runs five times faster (every 100ms) for more consistent application of process priorities.
Safer Uninstallation:
- The uninstall script has been cleaned up, removing unsafe system calls (cmd/pkill) to ensure a reliable uninstall process.
Fixes:
- Resolved minor installation issues.

Version 6
- Removed Aerilate from the script
- Added uninstall script
- Decreased oom adjustment from 500 ms to 100 ms
- Added updateJson to module.prop

Version 4.3
-  It continuously sets their oom_score_adj to -1000 and optionally applies legacy oom_adj if supported by the kernel.
-  Boosts performance by increasing CPU scheduling priority (renice -18) for these apps.
-  Includes a watchdog that automatically restarts PolygonX's foreground service if the app is killed or crashes.
-  Features smart handling of Pokémon GO PID changes, pausing adjustments temporarily to avoid conflicts.
-  Includes dynamic log rotation to maintain a lightweight, readable logfile.
   -  Logfile location: /data/adb/modules/oom_adjuster/oom_adjuster.log
- Memory Optimization (🆕 !)
- Drop_caches loop: Frees up system RAM every 30 seconds if memory is low.
- LRU memory deprioritizer: Scans Android’s Least Recently Used (LRU) process list and:
   - Force-stops CACHED_EMPTY apps (procState 19).
   - Sets oom_score_adj to 999 for less critical background processes (procState 14–18) to help LMK prioritize better.
