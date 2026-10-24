#!/usr/bin/env bash
# Build NFSU2Recomp for iOS (arm64) and package as an unsigned .ipa for sideloading.
# This script is intended to run on a macOS GitHub Actions runner with Xcode installed.

set -e

# -------- Configuration --------
# Minimum iOS version – must match the SDK version you target.
MIN_IOS="11.0"
# Output directory
ROOT="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="$ROOT/out"
OBJ_DIR="$OUT_DIR/obj"
APP_DIR="$OUT_DIR/NFSU2Recomp.app"
IPA_PATH="$OUT_DIR/NFSU2Recomp.ipa"

# -------- Prepare SDK paths --------
SDK_PATH=$(xcrun --sdk iphoneos --show-sdk-path)
CLANG=$(xcrun --sdk iphoneos --find clang)

# Compiler flags for iOS
OPT="-O3 -target arm64-apple-ios${MIN_IOS} -isysroot $SDK_PATH -fno-strict-aliasing -mmacosx-version-min=$MIN_IOS"

# Create directories
mkdir -p "$OBJ_DIR"
mkdir -p "$APP_DIR"

# Build each generated C shard in parallel (same logic as build.sh)
cd "$ROOT/gen/all"
J=$(sysctl -n hw.ncpu)
find . -name 'shard_*.c' -print0 | xargs -0 -n1 -P "$J" -I {} bash -c '
  src="{}"
  obj="$OBJ_DIR/$(basename "$src" .c).o"
  $CLANG $OPT -c -I "$ROOT/runtime" -I . -Wno-unused-label -Wno-parentheses-equality "$src" -o "$obj"
'

# Link the final executable for iOS
cd "$ROOT"
$CLANG $OPT -framework Metal -framework AudioToolbox -framework CoreGraphics -framework UIKit \
  -I runtime -I gen/all \
  $(find "$OBJ_DIR" -name "*.o") \
  -o "$OUT_DIR/NFSU2Recomp"

# Create a minimal .app bundle
cp -R runtime/Resources "$APP_DIR/"
cp "$OUT_DIR/NFSU2Recomp" "$APP_DIR/NFSU2Recomp"
plutil -convert binary1 "$APP_DIR/Info.plist" 2>/dev/null || true
# If an Info.plist does not exist, create a basic one
if [ ! -f "$APP_DIR/Info.plist" ]; then
cat > "$APP_DIR/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>io.github.allydevs0.NFSU2Recomp</string>
    <key>CFBundleName</key><string>NFSU2Recomp</string>
    <key>CFBundleVersion</key><string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleExecutable</key><string>NFSU2Recomp</string>
    <key>UIRequiredDeviceCapabilities</key><array><string>arm64</string></array>
    <key>UISupportedInterfaceOrientations</key><array><string>UIInterfaceOrientationPortrait</string></array>
</dict>
</plist>
EOF
fi

# Package as an unsigned .ipa (zip the .app bundle)
cd "$OUT_DIR"
zip -r "NFSU2Recomp.ipa" "NFSU2Recomp.app"

echo "✅ iOS build completed. IPA located at: $IPA_PATH"
