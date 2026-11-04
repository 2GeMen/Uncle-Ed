#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compare the pinned original KIRK implementation with the public-verify fast path on Android."""
import argparse,subprocess,shutil,re,json,uuid
from pathlib import Path
REVISION='9bece86f087c4f3a2fb1af58dd90d89282013616'
repo=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--source',type=Path,required=True);p.add_argument('--sdk',type=Path,required=True);p.add_argument('--serial',required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
src=a.source.resolve();sdk=a.sdk.resolve();out=a.output.resolve()
assert not out.is_relative_to(repo),'Keep binaries outside the public source tree'
assert subprocess.check_output(['git','rev-parse','HEAD'],cwd=src,text=True).strip()==REVISION
out.mkdir(parents=True,exist_ok=True);original=out/'reference-source';shutil.copytree(src/'ext/libkirk',original,dirs_exist_ok=True)
for file in ['bn.c','ec.c','kirk_engine.h']:
 (original/file).write_bytes(subprocess.check_output(['git','show',f'{REVISION}:ext/libkirk/{file}'],cwd=src))
curves=(src/'ext/libkirk/kirk_engine.c').read_text();names=['ec_p','ec_a','ec_b1','ec_b2','ec_N1','ec_N2','Gx1','Gy1','Gx2','Gy2'];definitions=[]
for name in names:
 match=re.search(r'static const u8 '+name+r'\[\d+\] = \{[^}]+\};',curves);assert match,name;definitions.append(match.group())
(out/'kirk-test-curves.h').write_text('\n'.join(definitions)+'\n')
clang=sdk/'ndk/27.2.12479018/toolchains/llvm/prebuilt/darwin-x86_64/bin/aarch64-linux-android28-clang';files=['bn.c','ec.c','AES.c','SHA1.c','kirk_engine.c','amctrl.c']
for root,name in [(original,'reference.so'),(src/'ext/libkirk','optimized.so')]:
 subprocess.run([str(clang),'-O3','-fno-strict-aliasing','-fsigned-char','-fPIC','-shared','-Wl,-Bsymbolic',*[str(root/f) for f in files],'-o',str(out/name)],check=True)
subprocess.run([str(clang),'-O2','-I',str(out),str(repo/'Tests/Native/kirk-public-inverse-check.c'),'-ldl','-o',str(out/'check')],check=True)
adb=[str(sdk/'platform-tools/adb'),'-s',a.serial];remote='/data/local/tmp/uncleed-kirk-qa-'+uuid.uuid4().hex
try:
 subprocess.run([*adb,'shell','mkdir','-p',remote],check=True)
 subprocess.run([*adb,'push',str(out/'reference.so'),str(out/'optimized.so'),str(out/'check'),remote+'/'],check=True)
 subprocess.run([*adb,'shell','chmod','700',remote+'/check'],check=True)
 result=subprocess.check_output([*adb,'shell',remote+'/check',remote+'/reference.so',remote+'/optimized.so'],text=True)
 (out/'result.txt').write_text(result);print(result,end='')
 (out/'scope.json').write_text(json.dumps({'originalRevision':REVISION,'cases':6153,'validSignatureChecks':16,'invalidSignatureChecks':16,'uniqueSignatureVectorPairs':2,'checksIncludeBenchmarkRepeats':True,'publicVerifyOnly':True,'romUsed':False},indent=2)+'\n')
finally:
 subprocess.run([*adb,'shell','rm','-r',remote],check=False)
