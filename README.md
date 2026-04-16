# OomAdjuster
A Magisk module keeps important apps like PolygonX safe from being terminated by Android's low memory killer (OOM).

## Root handler program
This module requires that your phone is rooted.
Root handler programs that this module is working on:
- Magisk 29+
- Kitsune
- Apatch
- KSU

## What the module does
This Magisk module automatically protects PolygonX (com.evermorelabs.polygonx) from being killed by Android’s memory management. 
It works by:

* Locking OOM Score: Sets oom_score_adj to -1000 for PolygonX, making it the least likely to be killed by the system.
* CPU Priority: Increases the CPU priority using renice for smoother performance.
* CGroup Boost: Moves the app to the top-app CPU and scheduler groups.
* Cache Management: Monitors RAM usage and automatically drops system caches if memory usage exceeds 80%.
* App Compaction: Compacts app memory when RAM is high.
* LRU Deprioritization: Every 60 seconds, scans for background/empty processes and either deprioritizes or force-stops them to free memory. PolygonX and Pokémon GO are always excluded from this.
* Watchdog: Restarts PolygonX if it crashes or is killed.
* Pokémon GO memory killer: kills PoGo when system RAM exceeds 95% or PoGo usage exceeds 3000MB (configurable in config.json).
All actions are logged to /data/adb/modules/oom_adjuster/oom_adjuster.log for troubleshooting.

### Install
1. Download the OOM Adjuster zip file from releases.
2. Open root manager (Magisk, Magisk Alpha, Kitsune, APatch or KernelSU).
3. Go to Modules
4. Tap Install from storage
5. Select the .zip file you just downloaded
6. Reboot device as required
