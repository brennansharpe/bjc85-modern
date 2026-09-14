#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive="$project_dir/artifacts/original/pappl-1.4.12.tar.gz"
expected=1684c4e06446e9f7d93a39729fa0ba56f07a4007560080fdad7d0e2076a3615f
url=https://github.com/michaelrsweet/pappl/releases/download/v1.4.12/pappl-1.4.12.tar.gz
mkdir -p "$project_dir/artifacts/original" "$project_dir/artifacts/source"
if [ ! -f "$archive" ]; then
  curl --fail --location --proto '=https' --tlsv1.2 --max-time 120 "$url" -o "$archive.part"
  mv "$archive.part" "$archive"
fi
actual=$(shasum -a 256 "$archive")
actual=${actual%% *}
[ "$actual" = "$expected" ] || { echo "PAPPL source checksum mismatch" >&2; exit 1; }
if [ ! -d "$project_dir/artifacts/source/pappl-1.4.12" ]; then
  tar -xzf "$archive" -C "$project_dir/artifacts/source"
fi
if [ ! -d "$project_dir/build-pappl" ]; then
  cp -R "$project_dir/artifacts/source/pappl-1.4.12" "$project_dir/build-pappl"
fi
pkg-config --exists openssl || { echo "Install native openssl@3 and pkgconf first." >&2; exit 1; }
cd "$project_dir/build-pappl"
./configure --prefix="$project_dir/.local" --disable-shared --disable-libjpeg \
  --disable-libpng --disable-libusb --disable-libpam --with-tls=openssl \
  CC=clang CFLAGS='-O2 -arch arm64 -std=gnu17' > configure.log 2>&1
make -C pappl -j "${BJC85_BUILD_JOBS:-6}" > build.log 2>&1
make -C pappl install > install.log 2>&1
echo "PAPPL 1.4.12 installed locally in $project_dir/.local"
