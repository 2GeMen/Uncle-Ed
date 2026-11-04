#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Compile and run the original GLES readback check inside a debuggable app UID."""
import argparse,os,subprocess,tempfile,uuid
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--serial',required=True);p.add_argument('--sdk',type=Path,default=os.environ.get('ANDROID_HOME'));a=p.parse_args()
if a.sdk is None:raise SystemExit('Set ANDROID_HOME or --sdk')
sdk=a.sdk.resolve();adb=sdk/'platform-tools/adb';ndk=sdk/'ndk/27.2.12479018/toolchains/llvm/prebuilt';hosts=list(ndk.glob('*/bin/aarch64-linux-android28-clang++'));assert len(hosts)==1,'Pinned ARM64 NDK required'
root=Path(__file__).resolve().parents[1];name='uncleed-frame-check-'+uuid.uuid4().hex;remote='/data/local/tmp/'+name;private='cache/'+name
run=lambda *args,**kw:subprocess.run([str(adb),'-s',a.serial,*args],check=True,**kw)
with tempfile.TemporaryDirectory(prefix='uncleed-gles-check-') as t:
 binary=Path(t)/name
 subprocess.run([str(hosts[0]),'-std=c++17','-O2','-static-libstdc++',str(root/'Tests/Native/frame-readback-egl-check.cpp'),'-lEGL','-lGLESv3','-o',str(binary)],check=True)
 try:
  run('push',str(binary),remote);run('shell','run-as','org.uncleed.app','cp',remote,private);run('shell','run-as','org.uncleed.app','chmod','700',private);run('shell','run-as','org.uncleed.app',private)
 finally:
  run('shell','run-as','org.uncleed.app','rm','-f',private);run('shell','rm','-f',remote)
