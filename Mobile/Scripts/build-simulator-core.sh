#!/bin/sh
# Builds only an iOS Simulator ARM64 core. Device binaries are a different platform.
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SOURCE=${1:?Usage: build-simulator-core.sh /path/to/libretro-mgba [/path/to/build]}
BUILD=${2:-"$ROOT/.core-build"}
cmake -S "$SOURCE" -B "$BUILD" -DCMAKE_SYSTEM_NAME=iOS \
 -DCMAKE_OSX_SYSROOT=iphonesimulator -DCMAKE_OSX_ARCHITECTURES=arm64 \
 -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 -DCMAKE_BUILD_TYPE=Release \
 -DBUILD_LIBRETRO=ON -DBUILD_QT=OFF -DBUILD_SDL=OFF -DBUILD_GL=OFF \
 -DBUILD_GLES2=OFF -DBUILD_GLES3=OFF -DBUILD_SHARED=OFF -DBUILD_STATIC=OFF \
 -DBUILD_TEST=OFF -DUSE_FFMPEG=OFF -DUSE_PNG=OFF -DUSE_ZLIB=OFF \
 -DUSE_MINIZIP=OFF -DUSE_LIBZIP=OFF -DUSE_SQLITE3=OFF -DUSE_LUA=OFF \
 -DUSE_JSON_C=OFF -DUSE_FREETYPE=OFF -DUSE_EDITLINE=OFF -DUSE_LZMA=OFF
cmake --build "$BUILD" --target mgba_libretro -j 8
mkdir -p "$ROOT/Cores/Simulator"
cp "$BUILD/mgba_libretro.dylib" "$ROOT/Cores/Simulator/mgba_libretro.dylib"
xcrun vtool -show-build "$ROOT/Cores/Simulator/mgba_libretro.dylib"
