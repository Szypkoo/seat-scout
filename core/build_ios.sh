#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

export SDKROOT="${IPHONEOS_SDK:-$(xcrun --sdk iphoneos --show-sdk-path)}"
export IPHONEOS_DEPLOYMENT_TARGET="${MIN_IOS:-18.0}"
export CC_aarch64_apple_ios="${CLANG:-$(xcrun --sdk iphoneos --find clang)}"
export AR_aarch64_apple_ios="${AR:-$(xcrun --sdk iphoneos --find ar)}"
export CFLAGS_aarch64_apple_ios="-target arm64-apple-ios${IPHONEOS_DEPLOYMENT_TARGET} -isysroot ${SDKROOT}"

cargo build --release --lib --target aarch64-apple-ios
mkdir -p dist/ios
cp target/aarch64-apple-ios/release/libseat_scout_core.a dist/ios/
