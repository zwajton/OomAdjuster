#!/system/bin/sh
MODDIR=${0%/*}

# Wait for system boot completion before doing ANYTHING
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    sleep 5
done
sleep 15  # Additional wait for system stability

# Ensure permissions for all scripts
chmod 755 "$MODDIR"/*.sh 2>/dev/null

# Config path
CONFIG="$MODDIR/config.json"
LOG_FILE="$MODDIR/oom_adjuster.log"

# Create log file
touch "$LOG_FILE"

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [OOM Adjuster] $*" >> "$LOG_FILE"
    tail -n 5000 "$LOG_FILE" > "$MODDIR/tmp_log" && mv "$MODDIR/tmp_log" "$LOG_FILE"
}

# Load config values
load_config() {
    # Default values
    protected_apps="com.nianticlabs.pokemongo com.evermorelabs.polygonx"
    enable_phantom_fix="false"
    enable_watchdog="false"
    pause_on_pid_change="true"
    pause_time=10
    
    # PoGo killer defaults
    KILL_POGO_ENABLED="true"
    SYSTEM_MEMORY_THRESHOLD=95
    POGO_MEMORY_THRESHOLD=3000

    if [ -f "$CONFIG" ]; then
        log "Loading config from $CONFIG"
        
        # Load protected apps
        protected_apps=$(grep -A 20 '"protected_apps"' "$CONFIG" | grep -o '"[^"]*"' | grep -v '"protected_apps"' | tr -d '"' | tr '\n' ' ')
        
        # Load enable_phantom_fix
        if grep -q '"enable_phantom_fix":\s*true' "$CONFIG"; then
            enable_phantom_fix="true"
            log "phantom_fix enabled in config"
        fi
        
        # Load enable_watchdog
        if grep -q '"enable_watchdog":\s*true' "$CONFIG"; then
            enable_watchdog="true"
            log "watchdog enabled in config"
        fi
        
        # Load PoGo killer settings
        if grep -q '"pogo_memory_killer"' "$CONFIG"; then
            # Check if enabled
            if grep -q '"enabled":\s*false' "$CONFIG"; then
                KILL_POGO_ENABLED="false"
                log "PoGo memory killer disabled in config"
            fi
            
            # Load system memory threshold
            sys_thresh=$(grep -o '"system_memory_threshold":\s*[0-9]*' "$CONFIG" | grep -o '[0-9]*$')
            if [ -n "$sys_thresh" ]; then
                SYSTEM_MEMORY_THRESHOLD="$sys_thresh"
                log "Custom system threshold: ${SYSTEM_MEMORY_THRESHOLD}%"
            fi
            
            # Load PoGo memory threshold
            pogo_thresh=$(grep -o '"pogo_memory_threshold_mb":\s*[0-9]*' "$CONFIG" | grep -o '[0-9]*$')
            if [ -n "$pogo_thresh" ]; then
                POGO_MEMORY_THRESHOLD="$pogo_thresh"
                log "Custom PoGo threshold: ${POGO_MEMORY_THRESHOLD}MB"
            fi
        fi
        
    else
        log "Config file not found at $CONFIG - using defaults"
    fi
    
    log "Final protected apps: '$protected_apps'"
    log "Settings - phantom_fix: $enable_phantom_fix, watchdog: $enable_watchdog"
    log "PoGo killer - enabled: $KILL_POGO_ENABLED, system: ${SYSTEM_MEMORY_THRESHOLD}%, pogo: ${POGO_MEMORY_THRESHOLD}MB"
}

# Launch phantom fix (only if enabled in config)
if [ "$enable_phantom_fix" = "true" ] && [ -f "$MODDIR/phantom_fix.sh" ]; then
    sh "$MODDIR/phantom_fix.sh" &
    log "Phantom fix started (enabled in config)"
elif [ "$enable_phantom_fix" = "true" ] && [ ! -f "$MODDIR/phantom_fix.sh" ]; then
    log "WARNING: phantom_fix enabled but phantom_fix.sh not found"
fi

# Load config
load_config

log "Starting OOM adjustment..."
# Phantom process tweaks are handled by phantom_fix.sh (keep single source of truth)
# --------------------------------------------------
# pause_on_pid_change=true
prev_pid_pogo=""
# Main loop variables
# Your OOM Adjuster loop (every 100ms)
(
    adjustment_count=0
    last_log_time=$(date +%s)
    logged_processes=""

    # Initial debug: check if processes are found
    log "DEBUG: Starting OOM loop, checking processes..."
    for process in $protected_apps; do
        pid=$(pidof "$process" | awk '{print $1}')
        if [ -n "$pid" ]; then
            log "DEBUG: Found $process with PID: $pid"
        else
            log "DEBUG: Process $process not found (not running?)"
        fi
    done

    while true; do
        current_pid_pogo=$(pidof com.nianticlabs.pokemongo)
        if [ "$pause_on_pid_change" = "true" ] && [ -n "$prev_pid_pogo" ] && [ "$prev_pid_pogo" != "$current_pid_pogo" ]; then
            running_evermore=$(pidof com.evermorelabs.polygonx)
            if [ -n "$running_evermore" ]; then
                log "Pokémon GO PID changed while EvermoreLabs apps are running. Pausing OOM adjustment for 10 seconds."
                sleep 10
                log "Resuming OOM adjustment."
            fi
        fi
        prev_pid_pogo="$current_pid_pogo"
        
        # Process protected apps - with validation
        if [ -n "$protected_apps" ]; then
            for process in $protected_apps; do
                # Skip empty entries
                [ -z "$process" ] && continue
                
                pid=$(pidof "$process" | awk '{print $1}')
                if [ -n "$pid" ]; then
                    # Log first time we see each process
                    if ! echo "$logged_processes" | grep -q "$process:$pid"; then
                        log "Started protecting $process (PID: $pid)"
                        logged_processes="$logged_processes $process:$pid"
                    fi

                    # Apply adjustments
                    echo "$pid" > /dev/cpuset/top-app/tasks 2>/dev/null
                    echo "$pid" > /dev/stune/top-app/tasks 2>/dev/null
                    echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null
                    renice -18 -p "$pid" 2>/dev/null
                    
                    adjustment_count=$((adjustment_count + 1))
                fi
            done
        fi
        
        # Log summary every 5 minutes
        current_time=$(date +%s)
        if [ $((current_time - last_log_time)) -ge 300 ]; then
            log "Applied $adjustment_count adjustments in the last 5 minutes"
            adjustment_count=0
            last_log_time=$current_time
        fi
        
        sleep 0.1
    done
) &
# ==========================
# PolygonX Watchdog (only if enabled in config)
# ==========================
if [ "$enable_watchdog" = "true" ]; then
(
    APP_PKG="com.evermorelabs.polygonx"
    POGO_PKG="com.nianticlabs.pokemongo"
    CHECK_INTERVAL=35
    RESTART_DELAY=15

    log "PolygonX watchdog started (enabled in config)"

    while true; do
        if ! pidof "$APP_PKG" > /dev/null; then
            log "PolygonX not running - waiting ${RESTART_DELAY}s and cleaning up..."
            sleep "$RESTART_DELAY"
            
            # Store whether PoGo was running before PolygonX died
            was_pogo_running=$(pidof "$POGO_PKG")
            
            # KILL PoGo if it was running when PolygonX died (LMKD scenario)
            if [ -n "$was_pogo_running" ]; then
                log "LMKD kill detected - force killing PoGo with kill -9..."
                
                # Aggressive kill of all PoGo processes
                pgrep -f "$POGO_PKG" | while read -r pid; do
                    kill -9 "$pid" 2>/dev/null
                    log "Killed -9 PoGo process: $pid"
                done
                
                # Force stop any remnants
                am force-stop "$POGO_PKG" 2>/dev/null
                
                log "PoGo force kill completed"
                
                # CLEAR CACHE FOR BOTH APPS (not data)
                log "Clearing cache for both PolygonX and Pokémon Go..."
                
                # Clear PolygonX cache
                cmd package trim-caches com.evermorelabs.polygonx >> "$LOG_FILE" 2>&1
                pm clear-com.evermorelabs.polygonx.CACHE >> "$LOG_FILE" 2>&1
                rm -rf /data/data/com.evermorelabs.polygonx/cache/* 2>/dev/null
                log "PolygonX cache cleared"
                
                # Clear Pokémon Go cache
                cmd package trim-caches com.nianticlabs.pokemongo >> "$LOG_FILE" 2>&1
                pm clear-com.nianticlabs.pokemongo.CACHE >> "$LOG_FILE" 2>&1
                rm -rf /data/data/com.nianticlabs.pokemongo/cache/* 2>/dev/null
                log "Pokémon Go cache cleared"
                
                log "Dual cache clearing completed (both apps)"
            fi
            
            # Free memory before restarting PolygonX
            log "Pre-restart memory cleanup..."
            echo 3 > /proc/sys/vm/drop_caches
            sync
            sleep 8
            
            # Restart PolygonX using monkey (the working method)
            log "Restarting PolygonX via monkey..."
            timeout 10 /system/bin/monkey -p com.evermorelabs.polygonx -c android.intent.category.LAUNCHER 1 >> "$LOG_FILE" 2>&1
            
            sleep 8
            if pidof "$APP_PKG" > /dev/null; then
                log "SUCCESS: PolygonX restarted via monkey after dual cache clear"
                
                # Log the restart cycle completion
                if [ -n "$was_pogo_running" ]; then
                    log "LMKD recovery cycle completed: Both apps killed → Both caches cleared → PolygonX restarted"
                fi
            else
                log "FAILED: PolygonX restart failed after cache clear"
            fi
            
            # Extended wait after restart attempt
            sleep 30
        fi
        sleep "$CHECK_INTERVAL"
    done
) &
else
    log "PolygonX watchdog disabled in config"
fi

# ==========================
# Swap Space Monitor & Protector
# ==========================
(
    while true; do
        # Check swap usage to prevent LMKD kills
        if [ -f /proc/swaps ] && [ -f /proc/meminfo ]; then
            swap_total=$(grep SwapTotal /proc/meminfo | awk '{print $2}')
            swap_free=$(grep SwapFree /proc/meminfo | awk '{print $2}')
            
            if [ "$swap_total" -gt 1000 ]; then  # Only if swap is configured
                swap_used=$((swap_total - swap_free))
                swap_usage_percent=$(( (swap_used * 100) / swap_total ))
                
                # If swap is critically low, LMKD will kill aggressively
                if [ "$swap_usage_percent" -ge 85 ]; then
                    log "CRITICAL: High swap usage (${swap_usage_percent}%) - clearing to prevent LMKD kills"
                    
                    # Emergency memory recovery
                    echo 3 > /proc/sys/vm/drop_caches
                    sync
                    
                    # Kill some user apps to free swap
                    pm list packages -3 | cut -d: -f2 | head -3 | while read -r pkg; do
                        if [ "$pkg" != "com.evermorelabs.polygonx" ] && [ "$pkg" != "com.nianticlabs.pokemongo" ]; then
                            am force-stop "$pkg" 2>/dev/null && \
                                log "Freed swap by stopping: $pkg"
                        fi
                    done
                    
                    # Compact memory to reduce swap usage
                    cmd activity compact -m full com.nianticlabs.pokemongo 2>/dev/null
                    cmd activity compact -m full com.evermorelabs.polygonx 2>/dev/null
                fi
            fi
        fi
        
        sleep 30
    done
) &

# ==========================
# PolygonX Anti-Kill Protection
# ==========================
(
    while true; do
        polygonx_pid=$(pidof com.evermorelabs.polygonx)
        
        if [ -n "$polygonx_pid" ]; then
            # Maximum protection against LMKD
            echo -1000 > /proc/$polygonx_pid/oom_score_adj 2>/dev/null
            echo -1000 > /proc/$polygonx_pid/oom_adj 2>/dev/null
            
            # Prevent swap pressure kills
            if [ -f /proc/$polygonx_pid/oom_score ]; then
                echo 0 > /proc/$polygonx_pid/oom_score 2>/dev/null
            fi
            
            # Keep in foreground cgroups
            echo $polygonx_pid > /dev/cpuset/foreground/tasks 2>/dev/null
            echo $polygonx_pid > /dev/stune/foreground/tasks 2>/dev/null
            
            # Log protection status occasionally
            if [ $((RANDOM % 10)) -eq 0 ]; then
                oom_score=$(cat /proc/$polygonx_pid/oom_score_adj 2>/dev/null || echo "unknown")
                log "PolygonX protection active (PID: $polygonx_pid, oom_score_adj: $oom_score)"
            fi
        fi
        
        sleep 20
    done
) &

# --------------------------------------------------
# drop_caches loop (every 30s if RAM usage > 80%)
(
    while true; do
        mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_avail_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        mem_used_kb=$((mem_total_kb - mem_avail_kb))
        mem_usage_percent=$(( (mem_used_kb * 100) / mem_total_kb ))

        if [ "$mem_usage_percent" -ge 70 ]; then
            echo 3 > /proc/sys/vm/drop_caches
            log "Dropped caches due to high memory usage (${mem_usage_percent}%)"
            sleep_interval=10
        else
            log "Memory usage at ${mem_usage_percent}%. Skipped cache drop."
            sleep_interval=30
        fi

        sleep "$sleep_interval"
    done
) &
# --------------------------------------------------
# Compact memory if RAM usage > 80% (every 60s)
(
    while true; do
        mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_avail_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        mem_used_kb=$((mem_total_kb - mem_avail_kb))
        mem_usage_percent=$(( (mem_used_kb * 100) / mem_total_kb ))

        if [ "$mem_usage_percent" -ge 70 ]; then
            log "Memory usage at ${mem_usage_percent}%. Compacting app memory..."
            cmd activity compact -m some com.nianticlabs.pokemongo 2>/dev/null && \
                log "Compacted PoGo memory"
            cmd activity compact -m some com.evermorelabs.polygonx 2>/dev/null && \
                log "Compacted PolygonX memory"
        else
            log "Memory usage at ${mem_usage_percent}%. Skipping app compaction."
        fi

        sleep 60
    done
) &

# LRU memory deprioritizer loop with 80% RAM usage threshold
(
    while true; do
        mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_avail_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        mem_used_kb=$((mem_total_kb - mem_avail_kb))
        mem_usage_percent=$(( (mem_used_kb * 100) / mem_total_kb ))

        if [ "$mem_usage_percent" -ge 75 ]; then
            log "Memory usage at ${mem_usage_percent}%. Running LRU deprioritization."

            dumpsys activity lru | grep -E 'Proc #[0-9]+:' | while read -r line; do
                pkg=$(echo "$line" | sed -n 's/.*ProcessRecord{[^ ]* [^ ]* \([^ ]*\)\/[^ ]*} .*/\1/p')
                proc_state=$(echo "$line" | grep -oE 'procState=[0-9]+' | cut -d= -f2)
                pid=$(echo "$line" | grep -oE 'pid=[0-9]+' | cut -d= -f2)

                if [ -n "$proc_state" ] && [ -n "$pid" ] && [ -n "$pkg" ]; then
                    if [ "$proc_state" -eq 19 ]; then
                        # Processes with a procstate of 19 will be force stopped
                        am force-stop "$pkg" && \
                            log "Force-stopped CACHED_EMPTY app $pkg (PID: $pid, procState=$proc_state)"
                    elif [ "$proc_state" -ge 14 ] && [ "$proc_state" -lt 19 ]; then
                        # Processes with a procstate between 14-18 will have their OOM Score adjusted to 999
                        echo 999 > /proc/$pid/oom_score_adj 2>/dev/null && \
                            log "Set oom_score_adj=999 for background app $pkg (PID: $pid, procState=$proc_state)"
                    fi
                fi
            done
        else
            log "Memory usage at ${mem_usage_percent}%. Skipping LRU scan."
        fi

        sleep 60
    done
) &

# ==========================
# Pokémon GO Memory Killer (only if enabled)
# ==========================
if [ "$KILL_POGO_ENABLED" = "true" ]; then
(
    log "PoGo memory killer started (System: ${SYSTEM_MEMORY_THRESHOLD}%, PoGo: ${POGO_MEMORY_THRESHOLD}MB)"

    while true; do
        pogo_pid=$(pidof "com.nianticlabs.pokemongo")
        if [ -n "$pogo_pid" ]; then
            # Calculate system memory usage percentage
            mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
            mem_avail_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
            mem_used_kb=$((mem_total_kb - mem_avail_kb))
            mem_usage_percent=$(( (mem_used_kb * 100) / mem_total_kb ))
            
            # Get PoGo specific memory usage (in MB)
            pogo_memory_mb=$(cat /proc/$pogo_pid/status 2>/dev/null | grep VmRSS | awk '{print $2}')
            pogo_memory_mb=$((pogo_memory_mb / 1024))
            
            log "Memory: Total=${mem_usage_percent}%, PoGo=${pogo_memory_mb}MB"
            
            # Kill if system memory > threshold OR PoGo using > threshold
            if [ "$mem_usage_percent" -ge "$SYSTEM_MEMORY_THRESHOLD" ] || [ "$pogo_memory_mb" -ge "$POGO_MEMORY_THRESHOLD" ]; then
                log "KILLING PoGo - System RAM: ${mem_usage_percent}%, PoGo RAM: ${pogo_memory_mb}MB"
                
                # Clear PoGo cache before killing
                cmd package trim-caches com.nianticlabs.pokemongo >> "$LOG_FILE" 2>&1
                
                # Kill all PoGo processes aggressively
                pgrep -f "com.nianticlabs.pokemongo" | while read -r pid; do
                    kill -9 "$pid" 2>/dev/null
                done
                
                # Force stop any remnants
                am force-stop "com.nianticlabs.pokemongo" 2>/dev/null
                
                # Free system memory
                echo 3 > /proc/sys/vm/drop_caches
                
                log "SUCCESS: PoGo killed and memory freed"
            fi
        fi
        sleep 10
    done
) &
else
    log "PoGo memory killer disabled in config"
fi
log "OOM adjustment, cache cleaner, and watchdog started in background."
exit 0
