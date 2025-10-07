#!/system/bin/sh

# Launch phantom fix in background
/data/adb/modules/oom_adjuster/phantom_fix.sh &

# Set the module path
MODPATH="/data/adb/modules/oom_adjuster"

# Log function
touch "$MODPATH/oom_adjuster.log"
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [OOM Adjuster] $*" >> "$MODPATH/oom_adjuster.log"
    tail -n 1000 "$MODPATH/oom_adjuster.log" > "$MODPATH/oom_adjuster.tmp"
    mv "$MODPATH/oom_adjuster.tmp" "$MODPATH/oom_adjuster.log"
}

log "Starting OOM adjustment..."

# Phantom process tweaks are handled by phantom_fix.sh (keep single source of truth)
# --------------------------------------------------

pause_on_pid_change=true
prev_pid_pogo=""

# OOM Adjuster loop (every 100ms)
(
    while true; do
        current_pid_pogo=$(pidof com.nianticlabs.pokemongo)
        if [ "$pause_on_pid_change" = true ] && [ -n "$prev_pid_pogo" ] && [ "$prev_pid_pogo" != "$current_pid_pogo" ]; then
            running_evermore=$(pidof com.evermorelabs.polygonx)
            if [ -n "$running_evermore" ]; then
                log "Pokémon GO PID changed while EvermoreLabs apps are running. Pausing OOM adjustment for 10 seconds."
				# Changed from 30 sec to 10 sec
                sleep 10
                log "Resuming OOM adjustment."
            fi
        fi
        prev_pid_pogo="$current_pid_pogo"

        for process in com.nianticlabs.pokemongo com.evermorelabs.polygonx; do
            pid=$(pidof "$process" | awk '{print $1}')
            if [ -n "$pid" ]; then
                # Move to top-app cgroup (Android 10+)
                echo "$pid" > /dev/cpuset/top-app/tasks 2>/dev/null && \
                   log "Moved $process (PID: $pid) to cpuset top-app group"
                echo "$pid" > /dev/stune/top-app/tasks 2>/dev/null && \
                   log "Moved $process (PID: $pid) to stune top-app group"
                current_adj=$(cat /proc/$pid/oom_score_adj 2>/dev/null)
                if [ "$current_adj" != "-1000" ]; then
				# 1. Set modern OOM score
                    echo -1000 > /proc/$pid/oom_score_adj 2>/dev/null && \
                        log "Adjusted oom_score_adj for $process (PID: $pid)" || \
                        log "Failed to set oom_score_adj for $process (PID: $pid)"
                fi

                   # 2. Increase CPU priority
				renice -18 -p "$pid" 2>/dev/null && \
                    log "Set CPU priority to -18 for $process (PID: $pid)" || \
                    log "Failed to set CPU priority for $process (PID: $pid)"

                # 3. Legacy OOM adjustments (only if supported)
				if [ -f "/proc/$pid/oom_adj" ]; then
                    echo -16 > "/proc/$pid/oom_adj" 2>/dev/null && \
                        log "Set legacy oom_adj=-16 for $process (PID: $pid)" || \
                        log "Failed to set oom_adj=-16 for $process (PID: $pid)"
                    echo -17 > "/proc/$pid/oom_adj" 2>/dev/null && \
                        log "Set legacy oom_adj=-17 for $process (PID: $pid)" || \
                        log "Failed to set oom_adj=-17 for $process (PID: $pid)"
                else
                    log "oom_adj not supported for $process (PID: $pid), skipping legacy memory lock."
                fi
            fi
        done
        sleep 0.1 ## Changed from 500 ms to 100 ms
    done
) &

# PolygonX watchdog loop
(
    while true; do
        if ! pidof com.evermorelabs.polygonx > /dev/null; then
            log "PolygonX not running - attempting to restart service."
            am startservice --user 0 com.evermorelabs.polygonx/.services.PolygonXService 2>>"$MODPATH/oom_adjuster.log"
        fi
        sleep 30
    done
) &

# drop_caches loop (every 30s if RAM usage > 80%)
(
    while true; do
        mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_avail_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        mem_used_kb=$((mem_total_kb - mem_avail_kb))
        mem_usage_percent=$(( (mem_used_kb * 100) / mem_total_kb ))

        if [ "$mem_usage_percent" -ge 80 ]; then
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

# Compact memory if RAM usage > 80% (every 60s)
(
    while true; do
        mem_total_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        mem_avail_kb=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        mem_used_kb=$((mem_total_kb - mem_avail_kb))
        mem_usage_percent=$(( (mem_used_kb * 100) / mem_total_kb ))

        if [ "$mem_usage_percent" -ge 80 ]; then
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

        if [ "$mem_usage_percent" -ge 80 ]; then
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


log "OOM adjustment, cache cleaner, and watchdog started in background."
exit 0
