Version 8
Critical Fixes:
- Fixed oom_score_adj not being applied to protected processes
- Fixed renice priority not setting correctly
- Resolved process protection reliability issues
Now properly prevents protected apps from being killed by the system

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
