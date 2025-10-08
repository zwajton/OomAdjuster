#!/system/bin/sh
MODDIR=${0%/*}
LOGFILE="$MODDIR/phantom_fix.log"

# Clear previous log
echo "=== Phantom Fix Started $(date) ===" > "$LOGFILE"

# Log initial state
echo "[$(date '+%H:%M:%S')] Script started" >> "$LOGFILE"
echo "[$(date '+%H:%M:%S')] Android version: $(getprop ro.build.version.release)" >> "$LOGFILE"

# Optional: short delay to let system stabilize
(sleep 60 && {
    android_ver=$(getprop ro.build.version.release | cut -d. -f1)
    echo "[$(date '+%H:%M:%S')] Processing phantom tweaks for Android $android_ver..." >> "$LOGFILE"
    
    if [ "$android_ver" -gt 9 ]; then
        echo "[$(date '+%H:%M:%S')] Android $android_ver detected – applying phantom tweaks..." >> "$LOGFILE"
        
        # Log current values before changes
        current_cached=$(cmd device_config get activity_manager max_cached_processes 2>/dev/null || echo "failed")
        current_phantom=$(cmd device_config get activity_manager max_phantom_processes 2>/dev/null || echo "failed")
        current_empty=$(cmd device_config get activity_manager max_empty_time_millis 2>/dev/null || echo "failed")
        
        echo "[$(date '+%H:%M:%S')] Current values - cached: $current_cached, phantom: $current_phantom, empty: $current_empty" >> "$LOGFILE"
        
        # Only change if different
        if [ "$current_cached" != "256" ]; then
            result=$(cmd device_config put activity_manager max_cached_processes 256 2>&1)
            echo "[$(date '+%H:%M:%S')] Set max_cached_processes to 256: $result" >> "$LOGFILE"
        fi
        
        if [ "$current_phantom" != "2147483647" ]; then
            result=$(cmd device_config put activity_manager max_phantom_processes 2147483647 2>&1)
            echo "[$(date '+%H:%M:%S')] Set max_phantom_processes to 2147483647: $result" >> "$LOGFILE"
        fi
        
        if [ "$current_empty" != "43200000" ]; then
            result=$(cmd device_config put activity_manager max_empty_time_millis 43200000 2>&1)
            echo "[$(date '+%H:%M:%S')] Set max_empty_time_millis to 43200000: $result" >> "$LOGFILE"
        fi
        
        # Apply other settings
        sync_result=$(cmd device_config set_sync_disabled_for_tests persistent 2>&1)
        monitor_result=$(cmd settings put global settings_enable_monitor_phantom_procs false 2>&1)
        
        echo "[$(date '+%H:%M:%S')] Sync disabled result: $sync_result" >> "$LOGFILE"
        echo "[$(date '+%H:%M:%S')] Monitor phantom procs result: $monitor_result" >> "$LOGFILE"
        
        # Verify final values
        final_cached=$(cmd device_config get activity_manager max_cached_processes 2>/dev/null || echo "failed")
        final_phantom=$(cmd device_config get activity_manager max_phantom_processes 2>/dev/null || echo "failed")
        final_empty=$(cmd device_config get activity_manager max_empty_time_millis 2>/dev/null || echo "failed")
        
        echo "[$(date '+%H:%M:%S')] Final values - cached: $final_cached, phantom: $final_phantom, empty: $final_empty" >> "$LOGFILE"
        echo "[$(date '+%H:%M:%S')] Phantom tweaks completed." >> "$LOGFILE"
    else
        echo "[$(date '+%H:%M:%S')] Android $android_ver too old, skipping phantom tweaks" >> "$LOGFILE"
    fi
}) &