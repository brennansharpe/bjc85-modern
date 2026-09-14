#!/bin/sh
# Separate macOS 14 dependencies. Never overwrite the installed development libs.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
dependency_dir="$project_dir/build-release-deps"
prefix="$dependency_dir/install"
mkdir -p "$dependency_dir/work" "$project_dir/artifacts/original"
fetch() {
    archive="$project_dir/artifacts/original/$1"
    if [ ! -f "$archive" ]; then
        curl --fail --location --proto '=https' --max-time 120 "$2" -o "$archive.part"
        actual=$(shasum -a 256 "$archive.part"); actual=${actual%% *}
        [ "$actual" = "$3" ] || { echo "Checksum mismatch: $1" >&2; exit 1; }
        mv "$archive.part" "$archive"
        chmod a-w "$archive"
    fi
    actual=$(shasum -a 256 "$archive"); actual=${actual%% *}
    [ "$actual" = "$3" ] || { echo "Checksum mismatch: $1" >&2; exit 1; }
    if [ ! -d "$dependency_dir/work/$4" ]; then tar -xf "$archive" -C "$dependency_dir/work"; fi
}
fetch libusb-1.0.30.tar.bz2 https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2 fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf libusb-1.0.30
fetch openssl-3.6.4.tar.gz https://github.com/openssl/openssl/releases/download/openssl-3.6.4/openssl-3.6.4.tar.gz 9bffaa1ad1e07b354c21bd3324ec02fa15579f45a7d0494b3e74bc449b7333ef openssl-3.6.4
fetch gutenprint-5.3.5.tar.xz https://downloads.sourceforge.net/project/gimp-print/gutenprint-5.3/5.3.5/gutenprint-5.3.5.tar.xz f5a9f47de28530b1ae2069cfbc647a9a641baeeabe809bb0ef2b3ec5b9668d70 gutenprint-5.3.5
fetch pappl-1.4.12.tar.gz https://github.com/michaelrsweet/pappl/releases/download/v1.4.12/pappl-1.4.12.tar.gz 1684c4e06446e9f7d93a39729fa0ba56f07a4007560080fdad7d0e2076a3615f pappl-1.4.12
export MACOSX_DEPLOYMENT_TARGET=14.0
export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"
jobs=${BJC85_BUILD_JOBS:-6}
if [ ! -f "$dependency_dir/libusb.complete" ]; then
    cd "$dependency_dir/work/libusb-1.0.30"
    ./configure --prefix="$prefix" --enable-shared --disable-static CC=clang CFLAGS='-O2 -arch arm64 -mmacosx-version-min=14.0' > configure.log 2>&1
    make -j "$jobs" > build.log 2>&1
    make install > install.log 2>&1
    touch "$dependency_dir/libusb.complete"
fi
if [ ! -f "$dependency_dir/openssl.complete" ]; then
    cd "$dependency_dir/work/openssl-3.6.4"
    ./Configure darwin64-arm64-cc shared no-tests --prefix="$prefix" --openssldir="$prefix/ssl" -mmacosx-version-min=14.0 > configure.log 2>&1
    make -j "$jobs" > build.log 2>&1
    make install_sw > install.log 2>&1
    touch "$dependency_dir/openssl.complete"
fi
if [ ! -f "$dependency_dir/gutenprint.complete" ]; then
    mkdir -p "$dependency_dir/work/gutenprint-build"
    cd "$dependency_dir/work/gutenprint-build"
    ../gutenprint-5.3.5/configure --prefix="$prefix" --without-cups --without-gimp2 --without-readline \
        --disable-nls --disable-shared --enable-static --with-modules=static --disable-test --disable-testpattern \
        CC=clang CFLAGS='-O2 -arch arm64 -mmacosx-version-min=14.0 -std=gnu17' > configure.log 2>&1
    make -j "$jobs" > build.log 2>&1
    make install > install.log 2>&1
    touch "$dependency_dir/gutenprint.complete"
fi
if [ ! -f "$dependency_dir/pappl.complete" ]; then
    cd "$dependency_dir/work/pappl-1.4.12"
    ./configure --prefix="$prefix" --disable-shared --disable-libjpeg --disable-libpng --disable-libusb --disable-libpam \
        --with-tls=openssl CC=clang CFLAGS='-O2 -arch arm64 -mmacosx-version-min=14.0 -std=gnu17' > configure.log 2>&1
    make -C pappl -j "$jobs" > build.log 2>&1
    make -C pappl install > install.log 2>&1
    touch "$dependency_dir/pappl.complete"
fi
echo "macOS 14 ARM64 dependencies: $prefix"
