# OomAdjuster
A Magisk module keeps important apps like PolygonX and Pokémon GO safe from being terminated by Android's low memory killer (OOM).

## Root handler program
This module requires that your phone is rooted.
Root handler programs that this module is working on:
- Magisk 29+
- Kitsune
- Apatch
- KSU

## What the module does
This Magisk module automatically protects Pokémon GO (com.nianticlabs.pokemongo) and PolygonX (com.evermorelabs.polygonx) from being killed by Android’s memory management. 
It works by:

* Locking OOM Score: Sets oom_score_adj to -1000 for both apps, making them the least likely to be killed by the system.
* CPU Priority: Increases their CPU priority using renice for smoother performance.
* CGroup Boost: Moves both apps to the top-app CPU and scheduler groups.
* Phantom Process Tweaks: Applies system tweaks to allow more cached/phantom processes and prevent aggressive background process killing (especially on Android 10+).
* Cache Management: Monitors RAM usage and automatically drops system caches if memory usage exceeds 80%.
* App Compaction: Compacts app memory when RAM is high.
* LRU Deprioritization: Every 60 seconds, scans for background/empty processes and either deprioritizes or force-stops them to keep more memory available for Pokémon GO and PolygonX.
* Watchdog: Restarts PolygonX if it crashes or is killed.
All actions are logged to /data/adb/modules/oom_adjuster/oom_adjuster.log for troubleshooting.

### Install
1. Download the OOM Adjuster zip file from releases.
2. Open root manager (Magisk, Magisk Alpha, Kitsune, APatch or KernelSU).
3. Go to Modules
4. Tap Install from storage
5. Select the .zip file you just downloaded
6. Reboot device as required
