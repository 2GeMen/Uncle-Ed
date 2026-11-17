#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Reuse the actual Uncle Ed icon. Do not invent an Android placeholder icon.
Approved original project branding may be regenerated into the tracked main resources.
"""
import argparse,hashlib,json,shutil,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--apple-assets',required=True,type=Path);p.add_argument('--output',required=True,type=Path);a=p.parse_args()
root=Path(__file__).resolve().parents[1];out=a.output.resolve();source=a.apple_assets/'Branding/UncleED-Icon.png'
if not source.is_file():raise SystemExit('Original Uncle Ed icon is missing; no placeholder will be substituted')
entry=json.loads((root/'Shared/asset-provenance.json').read_text()).get('assets',{}).get('Assets/Branding/UncleED-Icon.png',{})
approved=entry.get('status')=='approved' and entry.get('sha256')==hashlib.sha256(source.read_bytes()).hexdigest()
if out.is_relative_to(root) and not approved:raise SystemExit('Only the hash-approved original project icon can be written into public resources')
for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
 folder=out/('mipmap-'+density);folder.mkdir(parents=True,exist_ok=True)
 subprocess.run(['sips','-z',str(size),str(size),str(source),'--out',str(folder/'ic_launcher.png')],check=True,stdout=subprocess.DEVNULL)
folder=out/'drawable-nodpi';folder.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,folder/'uncleed_splash.png')
# Native adaptive masking, preserving the existing illustration and safe inset.
folder=out/'mipmap-anydpi-v26';folder.mkdir(parents=True,exist_ok=True)
(folder/'ic_launcher.xml').write_text('<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n    <background android:drawable="@color/uncleed_icon_background" />\n    <foreground><inset android:inset="12dp" android:drawable="@drawable/uncleed_splash" /></foreground>\n</adaptive-icon>\n')
folder=out/'values';folder.mkdir(parents=True,exist_ok=True)
(folder/'icon-colors.xml').write_text('<resources><color name="uncleed_icon_background">#FAF7E7</color></resources>\n')
record={'source':'Assets/Branding/UncleED-Icon.png','sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'status':'approved-project-branding' if approved else 'private-development-only','outputs':{str(f.relative_to(out)):hashlib.sha256(f.read_bytes()).hexdigest() for f in sorted(f for f in out.rglob('*') if f.suffix in ('.png','.xml'))}}
record_path=root/'Shared/android-icon-provenance.json' if out.is_relative_to(root) else out/'icon-provenance.json'
record_path.write_text(json.dumps(record,indent=2)+'\n');print('Prepared 5 legacy densities, adaptive launcher mask and the original splash image; no new artwork generated.')
