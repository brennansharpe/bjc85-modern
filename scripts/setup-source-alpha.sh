#!/bin/sh
# One-time network setup; no queue, service or device operation.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
deps="$project_dir/build-source-deps"
mkdir -p "$deps"
archive="$deps/libusb-1.0.30.tar.bz2"
if [ ! -f "$archive" ]; then
    curl --fail --location --proto '=https' --max-time 120 \
      https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2 -o "$archive.part"
    mv "$archive.part" "$archive"
fi
echo "fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf  $archive" | shasum -a 256 -c -
if [ ! -f "$deps/install/lib/libusb-1.0.0.dylib" ]; then
    tar -xf "$archive" -C "$deps"
    cd "$deps/libusb-1.0.30"
    ./configure --prefix="$deps/install" --enable-shared --disable-static CC=clang CFLAGS='-O2 -arch arm64 -mmacosx-version-min=14.0'
    make -j 3
    make install
fi
printf '%s\n' 'Pinned libusb setup complete. Offline tests perform no downloads.'
