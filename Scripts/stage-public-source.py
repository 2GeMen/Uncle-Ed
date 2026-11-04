#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Create a new, audited SOURCE snapshot. No private history or build outputs.

Unapproved artwork is reported and omitted. This does not approve an installer
or make asset-dependent Apple targets runnable without a local resource pack.
"""
import argparse,importlib.util,json,shutil,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
SKIP_DIRS={'.git','.gradle','.build','.cxx','build','Build','DerivedData','__pycache__','xcuserdata','Cores','Frameworks','Vendor','PrivateAssets','release-artifacts'}
# Sources/Vendor is the checked-in, licensed Vulkan HEADER inventory, handled below.
SKIP_FILES={'local.properties','.DS_Store'}
ASSET_SUFFIX={'.png','.jpg','.jpeg','.svg','.scn','.glb','.gltf','.wav','.mp3','.m4a','.icns','.pdf','.ttf','.otf','.ktx','.ktx2','.hdr','.exr'}
p=argparse.ArgumentParser();p.add_argument('destination',type=Path);a=p.parse_args();dest=a.destination.resolve()
if dest.exists() or dest.is_relative_to(ROOT):sys.exit('Destination must be a NEW directory outside the working tree')
registry=json.loads((ROOT/'Shared/asset-provenance.json').read_text()).get('assets',{})
roots=['Sources','Mobile','Android','Shared','Scripts','Tests','Docs','LICENSES','Assets','README.md','UPSTREAM.md','LICENSE','THIRD_PARTY_NOTICES.md','AGENTS.md','.gitignore','build.command']
files=[];omitted=[]
for entry in roots:
 base=ROOT/entry
 for file in ([base] if base.is_file() else base.rglob('*')):
  if not file.is_file():continue
  rel=file.relative_to(ROOT)
  if file.is_symlink():sys.exit('Refusing source symlink: '+str(rel))
  parts=set(rel.parts[:-1]);skip=parts&SKIP_DIRS
  if rel.parts[:2]==('Sources','Vendor'):skip.discard('Vendor')
  if skip or file.name in SKIP_FILES or file.suffix in {'.log','.pyc','.apk','.ipa','.so','.dylib','.a','.jar','.aar'}:continue
  if file.suffix.lower() in ASSET_SUFFIX and registry.get(str(rel),{}).get('status')!='approved':omitted.append(str(rel));continue
  files.append((file,rel))
dest.mkdir(parents=True)
for file,rel in files:
 out=dest/rel;out.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(file,out)
spec=importlib.util.spec_from_file_location('audit',ROOT/'Scripts/audit-public-tree.py');module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
issues=module.audit(dest)
report={'source_snapshot_ready':not issues,'installer_ready':False,'files':len(files),'omitted_unapproved_assets':omitted,'findings':issues}
print(json.dumps(report,indent=2));sys.exit(bool(issues))
