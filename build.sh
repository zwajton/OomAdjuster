#!/usr/bin/env bash
set -euo pipefail

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK:-}}"

if [ -z "$NDK" ]; then
    echo "ERROR: Set ANDROID_NDK_HOME to your NDK installation path."
    echo "  Example: export ANDROID_NDK_HOME=~/Android/Sdk/ndk/27.0.12077973"
    exit 1
fi

if [ -x "$NDK/ndk-build" ]; then
    NKDBUILD="$NDK/ndk-build"
elif [ -f "$NDK/ndk-build.cmd" ]; then
    NKDBUILD="$NDK/ndk-build.cmd"
else
    echo "ERROR: ndk-build not found at $NDK"
    exit 1
fi

echo "Building with NDK: $NDK"
"$NKDBUILD" \
    NDK_PROJECT_PATH=. \
    APP_BUILD_SCRIPT=jni/Android.mk \
    NDK_APPLICATION_MK=jni/Application.mk \
    NDK_OUT=obj \
    NDK_LIBS_OUT=libs

OUTDIR="OomAdjusterer/bin"
mkdir -p "$OUTDIR"

ARM64="libs/arm64-v8a/oom_guardian"
ARM32="libs/armeabi-v7a/oom_guardian"

if [ -f "$ARM64" ]; then
    cp "$ARM64" "$OUTDIR/oom_guardian_arm64"
    echo "  arm64-v8a  -> $OUTDIR/oom_guardian_arm64"
fi

if [ -f "$ARM32" ]; then
    cp "$ARM32" "$OUTDIR/oom_guardian_arm"
    echo "  armeabi-v7a -> $OUTDIR/oom_guardian_arm"
fi

echo "Done. Commit the binaries in $OUTDIR/ and rebuild the module zip."
