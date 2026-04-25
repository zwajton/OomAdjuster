#!/system/bin/sh
# action.sh — OOM Adjuster
# Tries to open the module WebUI in KSUWebUIStandalone, WebUI X, or MMRL.
# If none are installed, downloads and installs KSUWebUIStandalone automatically.
# Based on tricky-addon's action script, adapted for OOM Adjuster.

ORG_PATH=$PATH
MODPATH="/data/adb/modules/oom_adjuster"
TMP_DIR="$MODPATH/tmp"
APK_PATH="$TMP_DIR/base.apk"
MODULE_ID="oom_adjuster"

mkdir -p "$TMP_DIR"

# ===== Helper Functions =====

manual_download() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  $1"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    sleep 3
    PATH=$ORG_PATH
    am start -a android.intent.action.VIEW \
        -d "https://github.com/5ec1cff/KsuWebUIStandalone/releases"
    exit 1
}

download() {
    PATH=/data/data/com.termux/files/usr/bin:/data/adb/magisk:$PATH
    for attempt in 1 2 3; do
        if command -v curl >/dev/null 2>&1; then
            timeout 10 curl -Ls "$1" && return 0
        elif command -v busybox >/dev/null 2>&1 && busybox wget --help >/dev/null 2>&1; then
            timeout 10 busybox wget --no-check-certificate -qO- "$1" && return 0
        fi
        echo "⚠️  Download failed, retrying ($attempt/3)..."
        sleep 3
    done
    echo "❌ Download failed after 3 attempts. Check your internet connection." >&2
    return 1
}

# ===== WebUI installer =====

get_webui() {
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📥 Downloading KSU WebUI Standalone..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    API="https://api.github.com/repos/5ec1cff/KsuWebUIStandalone/releases/latest"
    ping -c 1 -w 5 raw.githubusercontent.com >/dev/null 2>&1 || \
        manual_download "Unable to reach GitHub. Please download manually."
    URL=$(download "$API" | grep -o '"browser_download_url": "[^"]*"' | cut -d '"' -f4) || \
        manual_download "Unable to fetch latest release info. Please download manually."
    download "$URL" > "$APK_PATH" || \
        manual_download "APK download failed. Please download manually."

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📲 Installing..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    pm install -r "$APK_PATH" || {
        rm -f "$APK_PATH"
        manual_download "APK installation failed. Please download manually."
    }
    rm -f "$APK_PATH"
    echo "✅ Installed."

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🚀 Launching WebUI..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    PATH=$ORG_PATH
    am start -n "io.github.a13e300.ksuwebui/.WebUIActivity" -e id "$MODULE_ID"
}

# ===== Main =====

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 Checking for WebUI apps..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if pm path io.github.a13e300.ksuwebui >/dev/null 2>&1; then
    echo "🚀 Launching in KSU WebUI Standalone..."
    PATH=$ORG_PATH
    am start -n "io.github.a13e300.ksuwebui/.WebUIActivity" -e id "$MODULE_ID"
elif pm path com.dergoogler.mmrl.wx >/dev/null 2>&1; then
    echo "🚀 Launching in WebUI X..."
    PATH=$ORG_PATH
    am start -n "com.dergoogler.mmrl.wx/.ui.activity.webui.WebUIActivity" \
        -e MOD_ID "$MODULE_ID"
elif pm path com.dergoogler.mmrl >/dev/null 2>&1; then
    echo "🚀 Launching in MMRL..."
    PATH=$ORG_PATH
    am start -n "com.dergoogler.mmrl/.ui.activity.webui.WebUIActivity" \
        -e MOD_ID "$MODULE_ID"
else
    echo "❌ No WebUI app found — installing KSU WebUI Standalone..."
    get_webui
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Done."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
