#!/system/bin/sh
# =========================================
# OOM Adjuster - Uninstall Cleanup Script
# =========================================

LOG_FILE="/data/adb/modules/oom_adjuster/oom_adjuster.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Uninstallation started..."

# --- Stop watchdog or background loops if any ---
pkill -f "oom_adjuster.sh" 2>/dev/null
pkill -f "watchdog" 2>/dev/null
pkill -f "drop_caches" 2>/dev/null
pkill -f "LRU" 2>/dev/null
log "Stopped background OOM adjuster and watchdog processes"

# --- Reset process priorities for known apps (if running) ---
TARGET_APPS="com.evermorelabs.polygonx com.nianticlabs.pokemongo"

for APP in $TARGET_APPS; do
    PID=$(pidof "$APP" 2>/dev/null)
    if [ -n "$PID" ]; then
        log "Reverting OOM and priority settings for $APP (PID $PID)"
        echo 0 > /proc/$PID/oom_score_adj 2>/dev/null
        renice 0 -p $PID 2>/dev/null
    fi
done

# --- Restore global OOM and device_config tweaks ---
cmd device_config put activity_manager max_cached_processes 32
cmd device_config put activity_manager max_phantom_processes 64
cmd device_config put activity_manager max_empty_time_millis 1800000
cmd settings put global settings_enable_monitor_phantom_procs true
cmd device_config set_sync_disabled_for_tests none
log "Restored system phantom process and activity manager defaults"

# --- Remove logs and temp data ---
rm -f "$LOG_FILE"
log "Removed OOM Adjuster logs"

log "Uninstallation complete. All settings reverted."
exit 0