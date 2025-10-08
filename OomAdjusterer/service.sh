#!/system/bin/sh
MODDIR=${0%/*}
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
    tail -n 1000 "$LOG_FILE" > "$MODDIR/tmp_log" && mv "$MODDIR/tmp_log" "$LOG_FILE"
}

# Load config values
load_config() {
    if [ -f "$CONFIG" ]; then
        log "Loading config from $CONFIG"
        
        # Load protected apps - more robust parsing
        protected_apps=$(grep -A 20 '"protected_apps"' "$CONFIG" | grep -o '"[^"]*"' | grep -v '"protected_apps"' | tr -d '"' | tr '\n' ' ')
        
        # Debug: log what was loaded
        log "Raw protected apps from config: '$protected_apps'"
        
        # Set default values
        pause_on_pid_change="true"
        pause_time=10
        
    else
        log "Config file not found at $CONFIG"
        # Default values
        protected_apps="com.nianticlabs.pokemongo com.evermorelabs.polygonx"
        pause_on_pid_change="true"
        pause_time=10
    fi
    
    log "Final protected apps: '$protected_apps'"
}

# Launch phantom fix
if [ -f "$MODDIR/phantom_fix.sh" ]; then
    sh "$MODDIR/phantom_fix.sh" &
    log "Phantom fix started"
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
# --------------------------------------------------
# PolygonX watchdog loop
(
    while true; do
        if ! pidof com.evermorelabs.polygonx > /dev/null; then
            log "PolygonX not running - attempting to restart service."
            am startservice --user 0 com.evermorelabs.polygonx/.services.PolygonXService 2>>"$MODDIR/oom_adjuster.log"
        fi
        sleep 30
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

        if [ "$mem_usage_percent" -ge "$drop_cache_threshold" ]; then # Now configurable
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

        if [ "$mem_usage_percent" -ge "$compact_threshold" ]; then # Now configurable
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
# --------------------------------------------------
# LRU memory deprioritizer loop with 80% RAM usage threshold
(
    while true; do
        mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_avail_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        mem_used_kb=$((mem_total_kb - mem_avail_kb))
        mem_usage_percent=$(( (mem_used_kb * 100) / mem_total_kb ))
# --------------------------------------------------
        if [ "$mem_usage_percent" -ge "$lru_threshold" ]; then # Now configurable
            log "Memory usage at ${mem_usage_percent}%. Running LRU deprioritization."
# --------------------------------------------------
            dumpsys activity lru | grep -E 'Proc #[0-9]+:' | while read -r line; do
                pkg=$(echo "$line" | sed -n 's/.*ProcessRecord{[^ ]* [^ ]* \([^ ]*\)\/[^ ]*} .*/\1/p')
                proc_state=$(echo "$line" | grep -oE 'procState=[0-9]+' | cut -d= -f2)
                pid=$(echo "$line" | grep -oE 'pid=[0-9]+' | cut -d= -f2)
# --------------------------------------------------
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
# --------------------------------------------------
        sleep 60
    done
) &
# --------------------------------------------------
# --------------------------------------------------
log "OOM adjustment, cache cleaner, and watchdog started in background."
exit 0
