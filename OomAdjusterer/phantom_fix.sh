#!/system/bin/sh
sleep 90

# Persistent phantom tweaks (Android 10+)
android_ver=$(getprop ro.build.version.release | cut -d. -f1)
[ "$android_ver" -gt 9 ] && {
  # helper: set device_config only if different
  current=$(cmd device_config get activity_manager max_cached_processes 2>/dev/null)
  [ "$current" != "256" ] && cmd device_config put activity_manager max_cached_processes 256
  current=$(cmd device_config get activity_manager max_phantom_processes 2>/dev/null)
  [ "$current" != "2147483647" ] && cmd device_config put activity_manager max_phantom_processes 2147483647
  current=$(cmd device_config get activity_manager max_empty_time_millis 2>/dev/null)
  [ "$current" != "43200000" ] && cmd device_config put activity_manager max_empty_time_millis 43200000
  cmd device_config set_sync_disabled_for_tests persistent 2>/dev/null || true
  cmd settings put global settings_enable_monitor_phantom_procs false 2>/dev/null || true
}