#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Reproduce the development PSP core from reviewed source, outside the public tree."""
import argparse,subprocess,os,json,hashlib,shutil
from pathlib import Path
REVISION='9bece86f087c4f3a2fb1af58dd90d89282013616'
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--sdk',type=Path,default=os.environ.get('ANDROID_HOME'));a=p.parse_args()
src=a.source.resolve();out=a.output.resolve();assert a.sdk and not out.is_relative_to(Path(__file__).resolve().parents[1])
a.sdk=a.sdk.resolve()
def git(*args):return subprocess.check_output(['git',*args],cwd=src,text=True).strip()
assert git('rev-parse','HEAD')==REVISION,'Unexpected upstream revision'
patch_root=Path(__file__).resolve().parents[1]/'Android/patches'
patches=[(patch_root/'ppsspp-context-destroy-after-unload.patch',('libretro/LibretroGraphicsContext.cpp',)),(patch_root/'ppsspp-libretro-binary-append.patch',('Common/File/FileUtil.cpp',)),(patch_root/'ppsspp-kirk-public-field-inverse.patch',('ext/libkirk/bn.c','ext/libkirk/ec.c','ext/libkirk/kirk_engine.h'))]
for patch,paths in patches:
 if not git('diff','--',*paths):
  subprocess.run(['git','apply',str(patch)],cwd=src,check=True)
 assert git('diff','--',*paths)==patch.read_text().strip(),'Review unexpected source changes before building: '+str(paths)
assert set(git('diff','--name-only').splitlines())=={path for _,paths in patches for path in paths},'Unexpected modified source files'
cmake=a.sdk/'cmake/3.22.1/bin/cmake';build=out/'build/ppsspp-arm64'
flags=['-G','Ninja',f'-DCMAKE_MAKE_PROGRAM={a.sdk}/cmake/3.22.1/bin/ninja',f'-DCMAKE_TOOLCHAIN_FILE={a.sdk}/ndk/27.2.12479018/build/cmake/android.toolchain.cmake','-DANDROID_ABI=arm64-v8a','-DANDROID_PLATFORM=android-28','-DCMAKE_BUILD_TYPE=Release','-DLIBRETRO=ON','-DUSE_FFMPEG=ON','-DUSING_GLES2=ON','-DUSE_SYSTEM_LIBPNG=OFF','-DUSE_SYSTEM_ZSTD=OFF','-DUSE_SYSTEM_FFMPEG=OFF','-DVULKAN=OFF','-DUNITTEST=OFF','-DHEADLESS=OFF','-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384']
subprocess.run([str(cmake),'-S',str(src),'-B',str(build),*flags],check=True)
subprocess.run([str(cmake),'--build',str(build),'--target','ppsspp_libretro','-j','4'],check=True)
binary=out/'arm64-v8a/libppsspp_libretro.so';binary.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(build/'ppsspp_libretro_android.so',binary)
record={'component':'PPSSPP','source':'https://github.com/hrydgard/ppsspp','revision':REVISION,'submodules':git('submodule','status','--recursive').splitlines(),'flags':flags,'sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'patches':[{'file':str(patch.relative_to(Path(__file__).resolve().parents[1])),'sha256':hashlib.sha256(patch.read_bytes()).hexdigest()} for patch,_ in patches],'commercial_runtime_validated':False,'distribution_ready':False}
(out/'ppsspp-arm64-v8a-provenance.json').write_text(json.dumps(record,indent=2)+'\n')
print(binary)
