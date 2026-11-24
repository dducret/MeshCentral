#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
[ "$(uname -s)" = Darwin ] || { echo 'This preparation script requires macOS and Xcode.'; exit 1; }
export PATH="$HOME/.cargo/bin:$PATH"
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
AGENT_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
xcrun --sdk iphoneos --show-sdk-path >/dev/null
command -v rustup >/dev/null 2>&1 || {
    echo 'Install Rust with rustup from https://rust-lang.org/tools/install/ and run this script again.'
    exit 1
}
rustc --version
echo 'This project requires Rust 1.99 or later. Use rustup update stable if needed.'
rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
cargo test --manifest-path "$AGENT_ROOT/Cargo.toml" --offline --locked --workspace
xcodebuild -list -project "$SCRIPT_DIR/../MeshCentralIOS.xcodeproj"
echo ''
echo 'Ready. Open apple/App/MeshCentralIOS.xcodeproj, select your signing Team and iPhone, then Run.'
