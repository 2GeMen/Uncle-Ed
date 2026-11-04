#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Serial per-device QA. Stop on instrumentation failures, not just adb exit codes.

Build beforehand with the private asset/core environment. Evidence must remain
outside public source. This runner never clears application data or imports ROMs.
"""
import argparse,datetime,hashlib,json,os,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--serial',required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--probe',action='append',required=True);p.add_argument('--install',action='store_true');a=p.parse_args()
root=Path(__file__).resolve().parents[1];out=a.output.resolve()
if out.is_relative_to(root):raise SystemExit('Keep private QA evidence outside public source')
if out.exists():raise SystemExit('Use a new evidence directory for each run')
sdk=Path(os.environ['ANDROID_HOME']);adb=sdk/'platform-tools/adb';apk=root/'Android/app/build/outputs/apk/debug/app-debug.apk';test=root/'Android/app/build/outputs/apk/androidTest/debug/app-debug-androidTest.apk'
run=lambda *args:subprocess.run([str(adb),'-s',a.serial,*args],capture_output=True,text=True,check=True).stdout
active=run('shell','dumpsys','activity')
if 'ActiveInstrumentation{' in active or 'InstrumentationRecord{' in active:raise SystemExit('This device is already running instrumentation; finish that run before installing or starting another')
out.mkdir(parents=True);report={'serial':a.serial,'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'apk_sha256':hashlib.sha256(apk.read_bytes()).hexdigest(),'test_apk_sha256':hashlib.sha256(test.read_bytes()).hexdigest(),'probes':[],'all_passed':False}
def save(): (out/'summary.json').write_text(json.dumps(report,indent=2)+'\n')
save()
if a.install:
 for path in (apk,test):run('install','-r',str(path))
for mode in a.probe:
 if not mode or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in mode):raise SystemExit('Invalid probe name')
 result=run('shell','am','instrument','--user','0','-w','-e','probe',mode,'org.uncleed.app.test/org.uncleed.app.CoreProbeInstrumentation');(out/(mode+'.txt')).write_text(result)
 passed='INSTRUMENTATION_RESULT: result=PASS:' in result and 'INSTRUMENTATION_CODE: -1' in result and 'INSTRUMENTATION_RESULT: error=' not in result
 report['probes'].append({'name':mode,'passed':passed});save()
 if not passed:raise SystemExit(f'Failed: {mode}. Evidence saved; remaining probes were not started')
 print('PASS:',mode,flush=True)
report['all_passed']=True;save()
