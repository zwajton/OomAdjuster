#!/system/bin/sh
sleep 90

# Persistent phantom tweaks (Android 10+)
android_ver=$(getprop ro.build.version.release | cut -d. -f1)
[ "$android_ver" -gt 9 ] && {
  cmd device_config set_sync_disabled_for_tests persistent
  cmd device_config put activity_manager max_cached_processes 256
  cmd device_config put activity_manager max_phantom_processes 2147483647
  cmd device_config put activity_manager max_empty_time_millis 43200000
  cmd settings put global settings_enable_monitor_phantom_procs false
}
