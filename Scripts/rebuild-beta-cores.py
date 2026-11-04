#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Rebuild ARM64 Android cores from the release's adjacent source archives."""
import argparse, hashlib, json, os, subprocess, tarfile
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('archives', type=Path)
p.add_argument('work', type=Path)
p.add_argument('--sdk', type=Path, default=os.environ.get('ANDROID_HOME'))
a = p.parse_args()
if not a.sdk:
    p.error('Set ANDROID_HOME or pass --sdk')
sdk, work = a.sdk.resolve(), a.work.resolve()
work.mkdir(parents=True, exist_ok=True)
def unpack(archive, destination):
    with tarfile.open(archive) as t:
        t.extractall(destination, filter='data')

unpack(a.archives / 'mgba-corresponding-source.tar.gz', work)
unpack(a.archives / 'ppsspp-corresponding-source.tar.gz', work)
deps = work / 'dependency-archives'
deps.mkdir(exist_ok=True)
unpack(a.archives / 'melonds-ds-corresponding-source.tar.gz', deps)
for archive in sorted(deps.glob('*.tar.gz')):
    unpack(archive, work)
for manifest in work.glob('*/SOURCE-MANIFEST.json'):
    data = json.loads(manifest.read_text())
    for name, sha in data['files_sha256'].items():
        if hashlib.sha256((manifest.parent / name).read_bytes()).hexdigest() != sha:
            raise SystemExit('Source integrity mismatch: ' + name)

cmake = sdk / 'cmake/3.22.1/bin/cmake'
flags = ['-G', 'Ninja', f'-DCMAKE_MAKE_PROGRAM={sdk}/cmake/3.22.1/bin/ninja',
         f'-DCMAKE_TOOLCHAIN_FILE={sdk}/ndk/27.2.12479018/build/cmake/android.toolchain.cmake',
         '-DANDROID_ABI=arm64-v8a', '-DANDROID_PLATFORM=android-28',
         '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384']
configurations = {
    'mgba': ['-DBUILD_LIBRETRO=ON'] + ['-D'+k+'=OFF' for k in
             ['BUILD_QT','BUILD_SDL','BUILD_GL','BUILD_GLES2','BUILD_GLES3',
              'USE_FFMPEG','USE_LIBZIP','USE_SQLITE3','USE_LZMA','BUILD_LTO']],
    'ppsspp': ['-DLIBRETRO=ON','-DUSE_FFMPEG=ON','-DUSING_GLES2=ON',
               '-DUSE_SYSTEM_LIBPNG=OFF','-DUSE_SYSTEM_ZSTD=OFF','-DUSE_SYSTEM_FFMPEG=OFF',
               '-DVULKAN=OFF','-DUNITTEST=OFF','-DHEADLESS=OFF'],
    'melonds-ds': ['-DENABLE_OPENGL=OFF','-DENABLE_JIT=ON','-DENABLE_TESTING=OFF']
}
for dep in sorted(deps.glob('*.tar.gz')):
    name = dep.name.removesuffix('.tar.gz')
    if name != 'melonds-ds':
        key = name.upper().replace('-', '_')
        configurations['melonds-ds'].append(f'-DFETCHCONTENT_SOURCE_DIR_{key}={work / name}')
targets = {'mgba': 'mgba_libretro', 'ppsspp': 'ppsspp_libretro'}
for name, extra in configurations.items():
    build = work / ('build-' + name)
    subprocess.run([str(cmake), '-S', str(work/name), '-B', str(build), *flags, *extra], check=True)
    command = [str(cmake), '--build', str(build), '-j', '4']
    if name in targets:
        command += ['--target', targets[name]]
    subprocess.run(command, check=True)
