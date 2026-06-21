#!/usr/bin/env bash
set -eEuvx

function error_help()
{
    ERROR_MSG="It looks like something went wrong building the Universal Binary."
    echo "error: ${ERROR_MSG}"
}
trap error_help ERR

# XCode tries to be helpful and overwrites the PATH. Reset that.
PATH="$(bash -l -c 'echo $PATH')"

# Resolve cargo binary: prefer ~/.cargo/bin, then PATH, then rustup
CARGO=""
if [ -x "$HOME/.cargo/bin/cargo" ]; then
  CARGO="$HOME/.cargo/bin/cargo"
elif command -v cargo &>/dev/null; then
  CARGO="$(command -v cargo)"
elif command -v rustup &>/dev/null; then
  CARGO="$(rustup which cargo 2>/dev/null)" || true
fi
if [ -z "$CARGO" ] || [ ! -x "$CARGO" ]; then
  echo "error: cargo not found. Install Rust via https://rustup.rs" >&2
  exit 1
fi
# Ensure rustc and other toolchain binaries are on PATH
export PATH="$(dirname "$CARGO"):$PATH"

# Ensure IPHONEOS_DEPLOYMENT_TARGET is set for Rust/cc crate builds
export IPHONEOS_DEPLOYMENT_TARGET="${IPHONEOS_DEPLOYMENT_TARGET:-16.5}"

# This should be invoked from inside xcode, not manually
if [[ "${#}" -ne 3 ]]
then
    echo "Usage (note: only call inside xcode!):"
    echo "path/to/build-scripts/xc-universal-binary.sh <FFI_TARGET> <SRC_ROOT_PATH> <buildvariant>"
    exit 1
fi
# what to pass to cargo build -p, e.g. logins_ffi
FFI_TARGET=${1}
# path to source code root
SRC_ROOT=${2}
# buildvariant from our xcconfigs
BUILDVARIANT=$(echo "${3}" | tr '[:upper:]' '[:lower:]')

BUILD_OUTPUT_DIR=debug
BUILD_MODE_FLAG=()
if [[ "${BUILDVARIANT}" != "debug" ]]; then
    BUILD_OUTPUT_DIR=release
    BUILD_MODE_FLAG=(--release)
fi

TARGET_ROOT="${CARGO_TARGET_DIR:-$SRC_ROOT/../../../target}"
IS_SIMULATOR=0
if [ "${LLVM_TARGET_TRIPLE_SUFFIX-}" = "-simulator" ]; then
  IS_SIMULATOR=1
fi

SIMULATOR_LIBS=()
BINDGEN_LIBRARY=""

build_rust_target() {
  local target="$1"
  "$CARGO" rustc -p "${FFI_TARGET}" --lib --crate-type staticlib "${BUILD_MODE_FLAG[@]}" --target "$target" --features use-as-lib
}

for arch in $ARCHS; do
  case "$arch" in
    x86_64)
      if [ $IS_SIMULATOR -eq 0 ]; then
        echo "Building for x86_64, but not a simulator build. What's going on?" >&2
        exit 2
      fi

      # Intel iOS simulator
      export CFLAGS_x86_64_apple_ios="-target x86_64-apple-ios"
      build_rust_target x86_64-apple-ios
      SIMULATOR_LIBS+=("$TARGET_ROOT/x86_64-apple-ios/${BUILD_OUTPUT_DIR}/lib${FFI_TARGET}.a")
      ;;

    arm64)
      if [ $IS_SIMULATOR -eq 0 ]; then
        # Hardware iOS targets
        build_rust_target aarch64-apple-ios
        BINDGEN_LIBRARY="$TARGET_ROOT/aarch64-apple-ios/${BUILD_OUTPUT_DIR}/lib${FFI_TARGET}.a"
        cp "$BINDGEN_LIBRARY" "$SRCROOT/lib${FFI_TARGET}.a"
      else
        # Apple Silicon iOS simulator
        build_rust_target aarch64-apple-ios-sim
        SIMULATOR_LIBS+=("$TARGET_ROOT/aarch64-apple-ios-sim/${BUILD_OUTPUT_DIR}/lib${FFI_TARGET}.a")
      fi
      ;;
  esac
done

if [ $IS_SIMULATOR -eq 1 ]; then
  if [ "${#SIMULATOR_LIBS[@]}" -eq 0 ]; then
    echo "No simulator Rust libraries were built." >&2
    exit 1
  fi
  BINDGEN_LIBRARY="${SIMULATOR_LIBS[0]}"
  if [ "${#SIMULATOR_LIBS[@]}" -eq 1 ]; then
    cp "$BINDGEN_LIBRARY" "$SRCROOT/lib${FFI_TARGET}.a"
  else
    lipo -create "${SIMULATOR_LIBS[@]}" -output "$SRCROOT/lib${FFI_TARGET}.a"
  fi
fi

$CARGO run -p affine_mobile_native --features use-as-lib --bin uniffi-bindgen generate --library "$BINDGEN_LIBRARY" --language swift --out-dir "$SRCROOT/../../ios/App/App/uniffi"
