#!/bin/bash

# Builds and runs tests for a particular target passed as an argument to this
# script.

set -e
set -x

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST_PATH="${BASE_DIR}/Cargo.toml"

VERSION="$1"
TARGET="$2"

echo "======================================================="
echo "TESTING VERSION: ${VERSION}, TARGET: ${TARGET}"
echo "======================================================="

#
# Tell cargo what linker to use and whatever else is required
#
configure_cargo() {
  rm -rf .cargo
  mkdir .cargo
  cp "${BASE_DIR}/ci/cargo-config" .cargo/config
}

cross_compile_tests() {
  case "$TARGET" in
    *-apple-ios)
      cargo test --no-run --manifest-path="${MANIFEST_PATH}" --target "$TARGET" -- \
            -C link-args=-mios-simulator-version-min=7.0
      ;;

    *)
      cargo test --no-run --verbose \
            --manifest-path="${MANIFEST_PATH}" \
            --target "$TARGET"
      ;;
  esac
}

# This is a hack as we cannot currently
# ask cargo what test files it generated:
# https://github.com/rust-lang/cargo/issues/1924
find_binaries() {
  target_base_dir="target/${TARGET}/debug"

  # find [[test]] sections and print the first line and
  # hack it to what we want from there.  Also "nix" for
  # tests that are implicitly prsent
  for test_base in $( awk '/\[\[test\]\]/{getline; print}' Cargo.toml | \
                          cut -d '='  -f2 | \
                          tr -d '"' | \
                          tr '-' '_' | \
                          tr -d ' '; echo "nix" ); do
    for path in ${target_base_dir}/${test_base}-* ; do
      echo "${path} "
    done
  done
}

test_binary() {
  binary=$1

  case "$TARGET" in
    arm-linux-gnueabi-gcc)
      qemu-arm -L /usr/arm-linux-gnueabihf "$binary"
      ;;

    arm-unknown-linux-gnueabihf)
      qemu-arm -L /usr/arm-linux-gnueabihf "$binary"
      ;;

    mips-unknown-linux-gnu)
      qemu-mips -L /usr/mips-linux-gnu "$binary"
      ;;

    aarch64-unknown-linux-gnu)
      qemu-aarch64 -L /usr/aarch64-linux-gnu "$binary"
      ;;

    *-rumprun-netbsd)
      rumprun-bake hw_virtio /tmp/nix-test.img "${binary}"
      qemu-system-x86_64 -nographic -vga none -m 64 \
                         -kernel /tmp/nix-test.img 2>&1 | tee /tmp/out &
      sleep 5
      grep "^PASSED .* tests" /tmp/out
      ;;

    *)
      echo "Running binary: ${binary}"
      ${binary}
      ;;
  esac
}

configure_cargo

# select the proper version
multirust override ${VERSION}

# build the tests
cross_compile_tests

# and run the tests
for bin in $(find_binaries); do
  test_binary "${bin}"
done