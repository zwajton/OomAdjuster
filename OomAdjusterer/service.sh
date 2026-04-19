#!/system/bin/sh
MODDIR=${0%/*}

# Wait for boot
while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 5; done
sleep 15

LOG_FILE="$MODDIR/oom_adjuster.log"
CONFIG="$MODDIR/config.conf"

# Write first entry with > (creates fresh log on each boot, proves path is valid)
printf '%s [OOM Adjuster] === Started ===\n' "$(date '+%Y-%m-%d %H:%M:%S')" > "$LOG_FILE"

log() {
    printf '%s [OOM Adjuster] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
}

# ── Defaults ────────────────────────────────────────────────────────────────
protected_apps="com.evermorelabs.polygonx com.nianticlabs.pokemongo"
enable_watchdog=false
enable_pogo_killer=true
system_memory_threshold=95
pogo_memory_threshold_mb=3200

# Source config — plain key=value, no JSON parsing required
if [ -f "$CONFIG" ]; then
    . "$CONFIG"
    log "Config loaded — protected: $protected_apps | watchdog: $enable_watchdog | pogo_killer: $enable_pogo_killer"
else
    log "No config at $CONFIG — using defaults"
fi

# ── OOM guardian daemon ──────────────────────────────────────────────────────
# Prefer the native C daemon; fall back to the shell loop if unavailable.
_arch=$(uname -m)
case "$_arch" in
    aarch64)       _guardian="$MODDIR/bin/oom_guardian_arm64" ;;
    armv7*|armv8l) _guardian="$MODDIR/bin/oom_guardian_arm"   ;;
    *)             _guardian=""                                ;;
esac

if [ -n "$_guardian" ] && [ -x "$_guardian" ]; then
    "$_guardian" &
    log "oom_guardian started (arch: $_arch, pid: $!)"
else
    log "oom_guardian not found for arch: $_arch — using shell loop"
    (
        while true; do
            for _pkg in $protected_apps; do
                _pid=$(pidof "$_pkg")
                [ -z "$_pid" ] && continue
                echo -1000 > /proc/$_pid/oom_score_adj 2>/dev/null
                echo -1000 > /proc/$_pid/oom_adj 2>/dev/null
                echo "$_pid" > /dev/cpuset/top-app/tasks 2>/dev/null
                echo "$_pid" > /dev/stune/top-app/tasks 2>/dev/null
                renice -18 -p "$_pid" 2>/dev/null
            done
            sleep 0.1
        done
    ) &
fi

# ── Loop 2: Memory management — every 10s ───────────────────────────────────
# Reads /proc/meminfo once per cycle. Handles drop_caches, compaction,
# swap pressure, PoGo killer, LRU deprioritization, and status logging.
(
    _cycle=0

    while true; do
        _cycle=$(( _cycle + 1 ))

        # Single meminfo read per cycle — all checks share these values
        _mem_total=$(awk '/MemTotal/{print $2; exit}' /proc/meminfo)
        _mem_avail=$(awk '/MemAvailable/{print $2; exit}' /proc/meminfo)
        _swap_total=$(awk '/SwapTotal/{print $2; exit}' /proc/meminfo)
        _swap_free=$(awk '/SwapFree/{print $2; exit}' /proc/meminfo)
        _mem_pct=$(( (_mem_total - _mem_avail) * 100 / _mem_total ))

        # Drop caches and compact protected apps at >=85% RAM
        if [ "$_mem_pct" -ge 85 ]; then
            echo 3 > /proc/sys/vm/drop_caches
            log "Dropped caches (RAM: ${_mem_pct}%)"
            for _pkg in $protected_apps; do
                cmd activity compact -m some "$_pkg" 2>/dev/null
            done
        fi

        # Swap pressure: stop a few cached apps to free swap
        if [ "${_swap_total:-0}" -gt 1000 ]; then
            _swap_pct=$(( (_swap_total - _swap_free) * 100 / _swap_total ))
            if [ "$_swap_pct" -ge 85 ]; then
                log "High swap (${_swap_pct}%) — emergency cleanup"
                echo 3 > /proc/sys/vm/drop_caches && sync
                pm list packages -3 2>/dev/null | cut -d: -f2 | head -3 | while read -r _pkg; do
                    _skip=0
                    for _p in $protected_apps; do [ "$_pkg" = "$_p" ] && _skip=1 && break; done
                    [ "$_skip" = "1" ] && continue
                    am force-stop "$_pkg" 2>/dev/null && log "Freed swap: stopped $_pkg"
                done
            fi
        fi

        # PoGo memory killer
        if [ "$enable_pogo_killer" = "true" ]; then
            _pogo_pid=$(pidof com.nianticlabs.pokemongo)
            if [ -n "$_pogo_pid" ]; then
                _pogo_mb=$(awk '/VmRSS/{printf "%d", $2/1024; exit}' /proc/$_pogo_pid/status 2>/dev/null)
                _pogo_mb=${_pogo_mb:-0}
                if [ "$_mem_pct" -ge "$system_memory_threshold" ] || [ "$_pogo_mb" -ge "$pogo_memory_threshold_mb" ]; then
                    log "Killing PoGo (RAM: ${_mem_pct}%, PoGo: ${_pogo_mb}MB)"
                    pgrep -f com.nianticlabs.pokemongo 2>/dev/null | while read -r _pid; do
                        kill -9 "$_pid" 2>/dev/null
                    done
                    am force-stop com.nianticlabs.pokemongo 2>/dev/null
                    echo 3 > /proc/sys/vm/drop_caches
                    log "PoGo killed"
                fi
            fi
        fi

        # LRU deprioritization every 60s (every 6 cycles of 10s)
        if [ $(( _cycle % 6 )) -eq 0 ] && [ "$_mem_pct" -ge 75 ]; then
            log "LRU scan (RAM: ${_mem_pct}%)"
            dumpsys activity lru 2>/dev/null | grep -E 'Proc #[0-9]+:' | while read -r _line; do
                _pkg=$(printf '%s' "$_line" | sed -n 's/.*ProcessRecord{[^ ]* [^ ]* \([^ ]*\)\/[^ ]*} .*/\1/p')
                _state=$(printf '%s' "$_line" | grep -oE 'procState=[0-9]+' | cut -d= -f2)
                _pid=$(printf '%s' "$_line" | grep -oE 'pid=[0-9]+' | cut -d= -f2)
                if [ -z "$_pkg" ] || [ -z "$_state" ] || [ -z "$_pid" ]; then continue; fi
                _skip=0
                for _p in $protected_apps; do [ "$_pkg" = "$_p" ] && _skip=1 && break; done
                [ "$_skip" = "1" ] && continue
                if [ "$_state" -eq 19 ]; then
                    am force-stop "$_pkg" 2>/dev/null && log "LRU: stopped $_pkg (procState=19)"
                elif [ "$_state" -ge 14 ] && [ "$_state" -lt 19 ]; then
                    echo 999 > /proc/$_pid/oom_score_adj 2>/dev/null
                fi
            done
        fi

        # Status log every 5 minutes (every 30 cycles of 10s)
        if [ $(( _cycle % 30 )) -eq 0 ]; then
            log "Status: RAM=${_mem_pct}%"
            for _pkg in $protected_apps; do
                _pid=$(pidof "$_pkg")
                [ -z "$_pid" ] && log "  $_pkg — not running" && continue
                _score=$(cat /proc/$_pid/oom_score_adj 2>/dev/null || echo "?")
                log "  $_pkg PID=$_pid oom_score_adj=$_score"
            done
        fi

        sleep 10
    done
) &

# ── Loop 3: PolygonX watchdog (optional) ────────────────────────────────────
if [ "$enable_watchdog" = "true" ]; then
(
    while true; do
        if ! pidof com.evermorelabs.polygonx > /dev/null 2>&1; then
            log "Watchdog: PolygonX not running — waiting 15s"
            sleep 15

            if pidof com.nianticlabs.pokemongo > /dev/null 2>&1; then
                log "Watchdog: LMKD kill suspected — killing PoGo, clearing caches"
                pgrep -f com.nianticlabs.pokemongo 2>/dev/null | while read -r _pid; do
                    kill -9 "$_pid" 2>/dev/null
                done
                am force-stop com.nianticlabs.pokemongo 2>/dev/null
            fi

            rm -rf /data/data/com.evermorelabs.polygonx/cache/* 2>/dev/null
            rm -rf /data/data/com.nianticlabs.pokemongo/cache/* 2>/dev/null
            log "Watchdog: caches cleared"

            echo 3 > /proc/sys/vm/drop_caches && sync
            sleep 8

            log "Watchdog: restarting PolygonX"
            timeout 10 /system/bin/monkey \
                -p com.evermorelabs.polygonx \
                -c android.intent.category.LAUNCHER 1 >> "$LOG_FILE" 2>&1

            sleep 8
            if pidof com.evermorelabs.polygonx > /dev/null 2>&1; then
                log "Watchdog: PolygonX restarted"
            else
                log "Watchdog: PolygonX restart FAILED"
            fi
            sleep 30
        fi
        sleep 35
    done
) &
fi

log "All loops started"
exit 0
