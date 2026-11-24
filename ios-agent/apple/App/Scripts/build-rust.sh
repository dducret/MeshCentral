#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
export PATH="$HOME/.cargo/bin:$PATH"
: "${SRCROOT:?Run this script from the Xcode build phase}"
: "${BUILT_PRODUCTS_DIR:?Missing Xcode environment}"
: "${TARGET_TEMP_DIR:?Missing Xcode environment}"
AGENT_ROOT=$(cd "$SRCROOT/../.." && pwd)
command -v cargo >/dev/null 2>&1 || { echo 'error: Install Rust, then run Scripts/prepare-mac.sh.'; exit 1; }
export CARGO_TARGET_DIR="$TARGET_TEMP_DIR/rust-target"
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-16.0}"
set --
for arch in $ARCHS; do
    case "$PLATFORM_NAME:$arch" in
        iphoneos:arm64) target=aarch64-apple-ios ;;
        iphonesimulator:arm64) target=aarch64-apple-ios-sim ;;
        iphonesimulator:x86_64) target=x86_64-apple-ios ;;
        *) echo "error: Unsupported platform/architecture: $PLATFORM_NAME:$arch"; exit 1 ;;
    esac
    cargo build --manifest-path "$AGENT_ROOT/Cargo.toml" --offline --locked --release \
        --package meshcentral-ios-bridge --lib --target "$target"
    set -- "$@" "$CARGO_TARGET_DIR/$target/release/libmeshcentral_ios_bridge.a"
done
[ "$#" -gt 0 ] || { echo 'error: Xcode did not select an architecture.'; exit 1; }
mkdir -p "$BUILT_PRODUCTS_DIR"
RUST_OUTPUT_NAME="${RUST_OUTPUT_NAME:-libmeshcentral_ios_bridge.a}"
if [ "$#" -eq 1 ]; then
    cp "$1" "$BUILT_PRODUCTS_DIR/$RUST_OUTPUT_NAME"
else
    xcrun lipo -create "$@" -output "$BUILT_PRODUCTS_DIR/$RUST_OUTPUT_NAME"
fi
