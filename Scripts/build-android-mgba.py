#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Build a pinned upstream core into a SEPARATE local binary pack, never the repo."""
import argparse,hashlib,json,os,subprocess
from pathlib import Path
REVISION='7a12d6d4b9acb14c0ae62c9166b6a2f3d08007f6'
def run(args,**kwargs):return subprocess.check_output(list(map(str,args)),text=True,**kwargs).strip()
p=argparse.ArgumentParser();p.add_argument('--source',required=True,type=Path);p.add_argument('--output',required=True,type=Path);p.add_argument('--abi',choices=['arm64-v8a','x86_64'],default='arm64-v8a');p.add_argument('--sdk',type=Path,default=os.environ.get('ANDROID_HOME'));a=p.parse_args()
assert a.sdk,'Set ANDROID_HOME or --sdk'
source=a.source.resolve();out=a.output.resolve();repo=Path(__file__).resolve().parents[1]
assert not out.is_relative_to(repo),'Keep generated core binaries outside the public source tree'
assert run(['git','rev-parse','HEAD'],cwd=source)==REVISION,'Unexpected upstream source revision'
assert not run(['git','status','--porcelain','--untracked-files=no'],cwd=source),'Record and review upstream modifications before building'
cmake=a.sdk/'cmake/3.22.1/bin/cmake';build=out/'build'/a.abi
flags=['-G','Ninja',f'-DCMAKE_MAKE_PROGRAM={a.sdk}/cmake/3.22.1/bin/ninja',f'-DCMAKE_TOOLCHAIN_FILE={a.sdk}/ndk/27.2.12479018/build/cmake/android.toolchain.cmake',f'-DANDROID_ABI={a.abi}','-DANDROID_PLATFORM=android-28','-DCMAKE_BUILD_TYPE=Release','-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384','-DBUILD_LIBRETRO=ON']
flags+=['-D'+key+'=OFF' for key in ['BUILD_QT','BUILD_SDL','BUILD_GL','BUILD_GLES2','BUILD_GLES3','USE_FFMPEG','USE_LIBZIP','USE_SQLITE3','USE_LZMA','BUILD_LTO']]
subprocess.run([str(cmake),'-S',str(source),'-B',str(build),*flags],check=True)
subprocess.run([str(cmake),'--build',str(build),'--target','mgba_libretro','-j','6'],check=True)
binary=out/a.abi/'libmgba_libretro.so';binary.parent.mkdir(parents=True,exist_ok=True);binary.write_bytes((build/'mgba_libretro.so').read_bytes())
record={'component':'mGBA','license':'MPL-2.0','source':'https://github.com/mgba-emu/mgba','revision':REVISION,'patches':[],'abi':a.abi,'ndk':'27.2.12479018','cmake':'3.22.1','android_api':28,'flags':flags,'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'source_archive_required_before_release':True}
(out/f'mgba-{a.abi}-provenance.json').write_text(json.dumps(record,indent=2)+'\n');print(binary)
