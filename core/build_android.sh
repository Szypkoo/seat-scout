#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Locate Android NDK
NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [ -z "$NDK" ]; then
    # Search common locations on Linux and macOS
    for cand in \
        "$HOME/Android/Sdk/ndk/"* \
        "$HOME/Library/Android/sdk/ndk/"* \
        "/opt/android-sdk/ndk/"* \
        "/usr/local/share/android-sdk/ndk/"*; do
        if [ -d "$cand" ]; then
            NDK="$cand"
            break
        fi
    done
fi

TARGET_API="${ANDROID_API:-26}"
OUT_DIR="$(pwd)/dist/android/jniLibs"
mkdir -p "$OUT_DIR/arm64-v8a" "$OUT_DIR/x86_64"

if command -v cargo-ndk >/dev/null 2>&1; then
    echo "Buduję bibliotekę core dla Androida za pomocą cargo-ndk (API $TARGET_API)..."
    cargo ndk -t arm64-v8a -t x86_64 -o "$OUT_DIR" build --release --lib
    echo "Gotowe: $OUT_DIR"
    exit 0
fi

if [ -n "$NDK" ] && [ -d "$NDK" ]; then
    echo "Znaleziono Android NDK: $NDK"
    HOST_TAG="linux-x86_64"
    if [ "$(uname -s)" = "Darwin" ]; then
        HOST_TAG="darwin-x86_64"
    fi
    TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"

    if [ -d "$TOOLCHAIN" ]; then
        # aarch64-linux-android (arm64-v8a)
        if rustup target list 2>/dev/null | grep -q "aarch64-linux-android (installed)"; then
            echo "Kompilacja dla aarch64-linux-android..."
            CC_aarch64_linux_android="$TOOLCHAIN/aarch64-linux-android${TARGET_API}-clang" \
            AR_aarch64_linux_android="$TOOLCHAIN/llvm-ar" \
            cargo build --release --lib --target aarch64-linux-android
            cp target/aarch64-linux-android/release/libseat_scout_core.so "$OUT_DIR/arm64-v8a/"
        fi

        # x86_64-linux-android (x86_64 emulator)
        if rustup target list 2>/dev/null | grep -q "x86_64-linux-android (installed)"; then
            echo "Kompilacja dla x86_64-linux-android..."
            CC_x86_64_linux_android="$TOOLCHAIN/x86_64-linux-android${TARGET_API}-clang" \
            AR_x86_64_linux_android="$TOOLCHAIN/llvm-ar" \
            cargo build --release --lib --target x86_64-linux-android
            cp target/x86_64-linux-android/release/libseat_scout_core.so "$OUT_DIR/x86_64/"
        fi
        echo "Gotowe: $OUT_DIR"
        exit 0
    fi
fi

echo "Informacja: Brak skonfigurowanego Android NDK lub targetów rustup."
echo "Zainstaluj Android NDK oraz targety:"
echo "  rustup target add aarch64-linux-android x86_64-linux-android"
echo "  cargo install cargo-ndk (opcjonalnie)"
