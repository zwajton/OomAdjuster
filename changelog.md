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
