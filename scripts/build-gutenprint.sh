#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
archive="$project_dir/artifacts/original/gutenprint-5.3.5.tar.xz"
expected=f5a9f47de28530b1ae2069cfbc647a9a641baeeabe809bb0ef2b3ec5b9668d70
url=https://downloads.sourceforge.net/project/gimp-print/gutenprint-5.3/5.3.5/gutenprint-5.3.5.tar.xz
mkdir -p "$project_dir/artifacts/original" "$project_dir/artifacts/source" "$project_dir/build-gutenprint"
if [ ! -f "$archive" ]; then
  curl -fL --max-time 120 "$url" -o "$archive.part"
  mv "$archive.part" "$archive"
fi
actual=$(shasum -a 256 "$archive")
actual=${actual%% *}
if [ "$actual" != "$expected" ]; then
  echo "Gutenprint source checksum mismatch" >&2
  exit 1
fi
if [ ! -d "$project_dir/artifacts/source/gutenprint-5.3.5" ]; then
  tar -xf "$archive" -C "$project_dir/artifacts/source"
fi
command -v pkg-config >/dev/null || { echo "Install pkgconf first: brew install pkgconf" >&2; exit 1; }
cd "$project_dir/build-gutenprint"
"$project_dir/artifacts/source/gutenprint-5.3.5/configure" \
  --prefix="$project_dir/.local" --without-cups --without-gimp2 --without-readline \
  --disable-nls --disable-shared --enable-static --with-modules=static \
  --disable-test --disable-testpattern CC=clang CFLAGS='-O2 -arch arm64 -std=gnu17' > configure.log 2>&1
make -j "${BJC85_BUILD_JOBS:-6}" > build.log 2>&1
make install > install.log 2>&1
echo "Gutenprint 5.3.5 installed locally in $project_dir/.local"
