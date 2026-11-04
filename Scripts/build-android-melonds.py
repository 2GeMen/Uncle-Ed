#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Reproduce the reviewed DS core and pinned FetchContent dependencies."""
import argparse,subprocess,os,json,hashlib,shutil
from pathlib import Path
repo=Path(__file__).resolve().parents[1];lock=json.loads((repo/'Shared/android-core-lock.json').read_text())['melonds-ds']
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--sdk',type=Path,default=os.environ.get('ANDROID_HOME'));a=p.parse_args();src=a.source.resolve();out=a.output.resolve();assert a.sdk and not out.is_relative_to(repo)
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=src,text=True).strip()==lock['revision']
assert not subprocess.check_output(['git','status','--porcelain','--untracked-files=no'],cwd=src,text=True).strip()
cmake=a.sdk/'cmake/3.22.1/bin/cmake';build=out/'build/melonds-arm64'
flags=['-G','Ninja',f'-DCMAKE_MAKE_PROGRAM={a.sdk}/cmake/3.22.1/bin/ninja',f'-DCMAKE_TOOLCHAIN_FILE={a.sdk}/ndk/27.2.12479018/build/cmake/android.toolchain.cmake','-DANDROID_ABI=arm64-v8a','-DANDROID_PLATFORM=android-28','-DCMAKE_BUILD_TYPE=Release','-DENABLE_OPENGL=OFF','-DENABLE_JIT=ON','-DENABLE_TESTING=OFF','-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384']
flags += ['-D'+name.upper().replace('-','_')+'_REPOSITORY_TAG='+revision for name,revision in lock['dependencies'].items()]
subprocess.run([str(cmake),'-S',str(src),'-B',str(build),*flags],check=True);subprocess.run([str(cmake),'--build',str(build),'-j','4'],check=True)
binary=out/'arm64-v8a/libmelondsds_libretro.so';binary.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(build/'src/libretro/melondsds_libretro_android.so',binary)
record={'component':'melonDS DS','source':'https://github.com/JesseTG/melonds-ds',**lock,'flags':flags,'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'bios_or_firmware_bundled':False,'commercial_runtime_validated':False,'distribution_ready':False}
(out/'melonds-arm64-v8a-provenance.json').write_text(json.dumps(record,indent=2)+'\n');print(binary)
