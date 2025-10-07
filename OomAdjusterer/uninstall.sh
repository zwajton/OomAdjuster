#!/system/bin/sh
# =========================================
# OOM Adjuster - Uninstall Cleanup Script (Safe)
# =========================================

LOG_FILE="/data/adb/modules/oom_adjuster/oom_adjuster.log"

# Simple logger — only works if /data is mounted
if [ -d /data/adb/modules ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Uninstallation started..." >> "$LOG_FILE"
fi

# Only remove logs and leftover data — no cmd/pkill calls (unsafe in uninstall context)
rm -f "$LOG_FILE" 2>/dev/null
rm -rf /data/adb/modules/oom_adjuster/tmp 2>/dev/null

if [ -d /data/adb/modules ]; then
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Cleanup complete. Module fully uninstalled." >> "$LOG_FILE"
fi

exit 0
