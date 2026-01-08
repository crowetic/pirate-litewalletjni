#!/usr/bin/env bash
set -euo pipefail

# macOS build script for pirate-litewalletjni.
# Builds OpenSSL and Rust cdylib for x86_64-apple-darwin and aarch64-apple-darwin.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WORKSPACE_DIR="${REPO_ROOT}/src"

HOST_ARCH="$(uname -m)"
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"

num_jobs() {
  sysctl -n hw.ncpu
}

build_openssl() {
  OPENSSL_VERSION="1.1.1w"
  OPENSSL_DIRNAME="openssl-${OPENSSL_VERSION}"
  OPENSSL_EXT="tar.gz"
  OPENSSL_FILENAME="${OPENSSL_DIRNAME}.${OPENSSL_EXT}"
  OPENSSL_URL_PREFIX="https://www.openssl.org/source/old/1.1.1/"
  OPENSSL_URL="${OPENSSL_URL_PREFIX}${OPENSSL_FILENAME}"

  if [ ! -f "${OPENSSL_FILENAME}" ]; then
    curl -fL "${OPENSSL_URL}" -o "${OPENSSL_FILENAME}"
  fi
  if ! gzip -t "${OPENSSL_FILENAME}" >/dev/null 2>&1; then
    echo "OpenSSL archive looks invalid, re-downloading..."
    rm -f "${OPENSSL_FILENAME}"
    curl -fL "${OPENSSL_URL}" -o "${OPENSSL_FILENAME}"
  fi
  if [ ! -d "${OPENSSL_DIRNAME}" ]; then
    tar xvf "${OPENSSL_FILENAME}"
  fi

  if [ ! -d "${OPENSSL_DIRNAME}/${OPENSSL_DIRNAME}/${ARCH}" ]; then
    cd "${OPENSSL_DIRNAME}"

    if [ -f "Makefile" ]; then
      make clean || true
      make distclean || true
    fi

    INSTALL_DIR="$(pwd)/${OPENSSL_DIRNAME}/${ARCH}"
    export CC="clang"
    export SDKROOT
    export CFLAGS="${OPENSSL_CFLAGS} -isysroot ${SDKROOT}"
    export LDFLAGS="${OPENSSL_LDFLAGS} -isysroot ${SDKROOT}"

    if [ -z "${OPENSSL_ARCH:-}" ]; then
      echo "OPENSSL_ARCH is not set; cannot configure OpenSSL."
      exit 1
    fi
    ./Configure "${OPENSSL_ARCH}" no-asm --prefix="${INSTALL_DIR}" --openssldir="${INSTALL_DIR}/ssl"
    make -j"$(num_jobs)"
    make -j"$(num_jobs)" install
    cd "${SCRIPT_DIR}"
  fi
}

build_libsodium() {
  LIBSODIUM_VERSION="1.0.18"
  LIBSODIUM_DIRNAME="libsodium-${LIBSODIUM_VERSION}"
  LIBSODIUM_EXT="tar.gz"
  LIBSODIUM_FILENAME="${LIBSODIUM_DIRNAME}.${LIBSODIUM_EXT}"
  LIBSODIUM_URL="https://download.libsodium.org/libsodium/releases/${LIBSODIUM_FILENAME}"

  if [ ! -f "${LIBSODIUM_FILENAME}" ]; then
    curl -fL "${LIBSODIUM_URL}" -o "${LIBSODIUM_FILENAME}"
  fi
  if ! gzip -t "${LIBSODIUM_FILENAME}" >/dev/null 2>&1; then
    echo "libsodium archive looks invalid, re-downloading..."
    rm -f "${LIBSODIUM_FILENAME}"
    curl -fL "${LIBSODIUM_URL}" -o "${LIBSODIUM_FILENAME}"
  fi
  if [ ! -d "${LIBSODIUM_DIRNAME}" ]; then
    tar xvf "${LIBSODIUM_FILENAME}"
  fi

  if [ ! -d "${LIBSODIUM_DIRNAME}/${LIBSODIUM_DIRNAME}/${ARCH}" ]; then
    cd "${LIBSODIUM_DIRNAME}"

    if [ -f "Makefile" ]; then
      make clean || true
      make distclean || true
    fi

    INSTALL_DIR="$(pwd)/${LIBSODIUM_DIRNAME}/${ARCH}"
    export CC="clang"
    export SDKROOT
    export CFLAGS="${LIBSODIUM_CFLAGS} -isysroot ${SDKROOT}"
    export LDFLAGS="${LIBSODIUM_LDFLAGS} -isysroot ${SDKROOT}"

    if [ -z "${LIBSODIUM_HOST:-}" ]; then
      echo "LIBSODIUM_HOST is not set; cannot configure libsodium."
      exit 1
    fi
    ./configure --host="${LIBSODIUM_HOST}" --prefix="${INSTALL_DIR}" --disable-asm --enable-shared=no
    make -j"$(num_jobs)"
    make -j"$(num_jobs)" install
    cd "${SCRIPT_DIR}"
  fi
}

build_rustlib() {
  export OPENSSL_STATIC=yes
  export OPENSSL_LIB_DIR="${SCRIPT_DIR}/${OPENSSL_DIRNAME}/${OPENSSL_DIRNAME}/${ARCH}/lib"
  export OPENSSL_INCLUDE_DIR="${SCRIPT_DIR}/${OPENSSL_DIRNAME}/${OPENSSL_DIRNAME}/${ARCH}/include"
  export CMAKE_POLICY_VERSION_MINIMUM=3.5
  export MACOSX_DEPLOYMENT_TARGET
  export CC="clang"
  export CXX="clang++"
  export CFLAGS="${RUST_CFLAGS}"
  export CXXFLAGS="${RUST_CFLAGS}"
  export CPPFLAGS="${RUST_CFLAGS}"
  export LDFLAGS="${RUST_LDFLAGS}"

  if ! command -v rustup >/dev/null 2>&1; then
    echo "rustup not found on PATH; please install rustup or add it to PATH."
    exit 1
  fi

  TOOLCHAIN="$(cd "${REPO_ROOT}/src" && rustup show active-toolchain | awk '{print $1}')"
  rustup target add --toolchain "${TOOLCHAIN}" "${RUST_ARCH}"
  rustup show

  unset RUSTC RUSTC_WRAPPER
  export RUSTUP_TOOLCHAIN="${TOOLCHAIN}"
  export RUSTC
  export CARGO
  RUSTC="$(rustup which --toolchain "${TOOLCHAIN}" rustc)"
  CARGO="$(rustup which --toolchain "${TOOLCHAIN}" cargo)"

  export SODIUM_LIB_DIR="${SCRIPT_DIR}/${LIBSODIUM_DIRNAME}/${LIBSODIUM_DIRNAME}/${ARCH}/lib"
  "${CARGO}" build --manifest-path "${SCRIPT_DIR}/Cargo.toml" --target "${RUST_ARCH}" --release
}

build() {
  local ARCH=$1

  echo "Building ${ARCH} architecture..."

  if [ "${ARCH}" == "aarch64-apple-darwin" ]; then
    export RUST_ARCH="aarch64-apple-darwin"
    export OPENSSL_ARCH="darwin64-arm64-cc"
    export OPENSSL_CFLAGS="-arch arm64 -target arm64-apple-macos11"
    export OPENSSL_LDFLAGS="-arch arm64 -target arm64-apple-macos11"
    export LIBSODIUM_CFLAGS="-arch arm64 -target arm64-apple-macos11"
    export LIBSODIUM_LDFLAGS="-arch arm64 -target arm64-apple-macos11"
    export LIBSODIUM_HOST="arm-apple-darwin"
    export MACOSX_DEPLOYMENT_TARGET="11.0"
    export RUST_CFLAGS="${OPENSSL_CFLAGS} -isysroot ${SDKROOT} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
    export RUST_LDFLAGS="${OPENSSL_LDFLAGS} -isysroot ${SDKROOT} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
  elif [ "${ARCH}" == "x86_64-apple-darwin" ]; then
    export RUST_ARCH="x86_64-apple-darwin"
    export OPENSSL_ARCH="darwin64-x86_64-cc"
    export OPENSSL_CFLAGS="-arch x86_64 -target x86_64-apple-macos10.13"
    export OPENSSL_LDFLAGS="-arch x86_64 -target x86_64-apple-macos10.13"
    export LIBSODIUM_CFLAGS="-arch x86_64 -target x86_64-apple-macos10.13"
    export LIBSODIUM_LDFLAGS="-arch x86_64 -target x86_64-apple-macos10.13"
    export LIBSODIUM_HOST="x86_64-apple-darwin"
    export MACOSX_DEPLOYMENT_TARGET="10.13"
    export RUST_CFLAGS="${OPENSSL_CFLAGS} -isysroot ${SDKROOT} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
    export RUST_LDFLAGS="${OPENSSL_LDFLAGS} -isysroot ${SDKROOT} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
  else
    echo "Unknown architecture: ${ARCH}"
    exit 1
  fi
  if [ -z "${OPENSSL_ARCH:-}" ]; then
    echo "OPENSSL_ARCH is empty for ${ARCH}"
    exit 1
  fi

  if [ "${HOST_ARCH}" == "x86_64" ] && [ "${ARCH}" == "aarch64-apple-darwin" ]; then
    echo "Host is Intel; cross-compiling OpenSSL for arm64 using SDK: ${SDKROOT}"
  fi

  build_openssl
  build_libsodium
  build_rustlib
}

build "aarch64-apple-darwin"
build "x86_64-apple-darwin"
