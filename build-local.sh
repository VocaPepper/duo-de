#!/bin/bash
#
# Local, unsigned build of DUO-DE (no release keys required).
#
# This mirrors the upstream build.sh but skips the release-signing / OTA /
# upload steps so the ROM can be built and flashed for testing without
# access to the private release keys.
#
# Run inside the build container (see build/Dockerfile). Expected layout:
#   /aosp             -> AOSP workspace (mounted from external disk)
#   /aosp/treble_aosp -> this repository (duo-de)
#
# Usage: bash /aosp/treble_aosp/build-local.sh [variant] [--with-treble-app]
#   variant defaults to treble_arm64_bvN (vanilla). Use treble_arm64_bgN for gapps.
#
set -e

VARIANT="${1:-treble_arm64_bvN}"
BUILD_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${BUILD_DIR:-/aosp/builds}"
JOBS="${JOBS:-$(nproc --all)}"

echo "==> workspace : $PWD"
echo "==> repo      : $BUILD_ROOT"
echo "==> output    : $BUILD_DIR"
echo "==> variant   : $VARIANT"
echo "==> jobs      : $JOBS"
echo

applyPatches() {
    echo "--> Applying TrebleDroid patches"
    bash "$BUILD_ROOT/patch.sh" "$BUILD_ROOT" trebledroid
    echo "--> Applying personal patches"
    bash "$BUILD_ROOT/patch.sh" "$BUILD_ROOT" personal
    echo "--> Applying DUO-DE patches"
    bash "$BUILD_ROOT/patch.sh" "$BUILD_ROOT" duo
    echo "--> Generating makefiles"
    ( cd device/phh/treble && cp "$BUILD_ROOT/build/aosp.mk" . && bash generate.sh aosp )
    echo
}

buildTrebleApp() {
    echo "--> Building treble_app (best effort)"
    local out="vendor/hardware_overlay/TrebleApp/app.apk"
    mkdir -p "$(dirname "$out")"
    if [ -d treble_app ] && ( cd treble_app && bash build.sh release ); then
        cp treble_app/TrebleApp.apk "$out"
    elif [ ! -f "$out" ] && [ -f "${TREBLE_APP_FALLBACK:-/aosp/TrebleApp.apk}" ]; then
        echo "!!! treble_app build failed; using fallback ${TREBLE_APP_FALLBACK:-/aosp/TrebleApp.apk}"
        cp "${TREBLE_APP_FALLBACK:-/aosp/TrebleApp.apk}" "$out"
    else
        echo "!!! treble_app build failed; leaving existing $out"
    fi
    echo
}

buildVariant() {
    mkdir -p "$BUILD_DIR"
    echo "--> Building $VARIANT"
    source build/envsetup.sh
    lunch "$VARIANT"-userdebug
    make -j"$JOBS" systemimage
    cp "$OUT/system.img" "$BUILD_DIR/system-$VARIANT.img"
    echo "--> image: $BUILD_DIR/system-$VARIANT.img"
    ls -la "$BUILD_DIR/system-$VARIANT.img"
}

# Patch the tree if it has not been patched yet.
if [ ! -f device/phh/treble/aosp.mk ]; then
    applyPatches
fi
[ "$2" == "--with-treble-app" ] && buildTrebleApp
buildVariant
