#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
cd "$(dirname "$0")/.."
export IPHONEOS_DEPLOYMENT_TARGET=16.0
export MACOSX_DEPLOYMENT_TARGET=13.0
for target in aarch64-apple-ios aarch64-apple-ios-sim aarch64-apple-darwin; do
    cargo build --offline --locked --release -p meshcentral-ios-bridge --target "$target"
done
mkdir -p apple/Artifacts
if [ -e apple/Artifacts/MeshCore.xcframework ]; then
    echo "Move the previous apple/Artifacts/MeshCore.xcframework aside before rebuilding." >&2
    exit 1
fi
xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libmeshcentral_ios_bridge.a -headers bridge/include \
    -library target/aarch64-apple-ios-sim/release/libmeshcentral_ios_bridge.a -headers bridge/include \
    -library target/aarch64-apple-darwin/release/libmeshcentral_ios_bridge.a -headers bridge/include \
    -output apple/Artifacts/MeshCore.xcframework
