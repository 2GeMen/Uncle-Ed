#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Reproducible PRIVATE SceneKit -> Android model/rim export; no game contents."""
import argparse,hashlib,json,subprocess,shutil,tempfile
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--apple-assets',type=Path,required=True);p.add_argument('--output',type=Path,required=True);p.add_argument('--work',type=Path,required=True);a=p.parse_args()
root=Path(__file__).resolve().parents[1];out=a.output.resolve();work=a.work.resolve();assets=a.apple_assets.resolve()
if out.is_relative_to(root) or work.is_relative_to(root) or work.is_relative_to(out):raise SystemExit('Output and build work must be separate private directories outside source')
if not assets.is_dir():raise SystemExit('Existing private Apple Assets required')
work.mkdir(parents=True,exist_ok=True);out.mkdir(parents=True,exist_ok=True)
transaction=tempfile.TemporaryDirectory(prefix='validated-pack-',dir=work);stage=Path(transaction.name)
shared=[root/'Mobile/Sources/Rendering/SpatialMachine.swift',root/'Mobile/Sources/Domain/PickerMotion.swift']
def executable(name,source,main,defines=()):
 folder=work/name;folder.mkdir(exist_ok=True);entry=folder/'main.swift';entry.write_text(main)
 bundle=folder/(name+'.app');binary=bundle/'Contents/MacOS'/name;binary.parent.mkdir(parents=True,exist_ok=True);res=bundle/'Contents/Resources';res.mkdir(exist_ok=True);link=res/'Assets'
 if link.is_symlink() and link.resolve()!=assets:raise SystemExit('Refusing mismatched Assets link')
 if not link.exists():link.symlink_to(assets,target_is_directory=True)
 command=['xcrun','swiftc','-O'];[command.extend(['-D',d]) for d in defines]
 subprocess.run(command+[str(source),*[str(x) for x in shared],str(entry),'-o',str(binary)],check=True)
 return binary
main='''import Foundation
let base=URL(fileURLWithPath:CommandLine.arguments[1]);try! FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
for model in ["nds","gba","gbc","psp","3ds"] {for theme in 0..<4 {autoreleasepool{
let rig=SpatialMachine(model:model,theme:theme)!;let dual=model=="nds" || model=="3ds"
rig.update(openness:dual ? 0:1,loading:0,held:[],frame:nil,operating:false)
try! GLBWriter().write(rig.root,base.appendingPathComponent("\\(model)-\\(theme).glb"))
if dual{rig.update(openness:1,loading:0,held:[],frame:nil,operating:true);try! GLBWriter().write(rig.root,base.appendingPathComponent("\\(model)-open-\\(theme).glb"))}
}};let media=SpatialMachine.media(model:model,cover:nil,tint:0x67766b)!;try! GLBWriter().write(media,base.appendingPathComponent("media-\\(model).glb"))}
'''
exporter=executable('ModelExporter',root/'Scripts/export-android-gltf.swift',main,['UNCLEED_ANDROID_EXPORT']);subprocess.run([str(exporter),str(stage/'models')],check=True)
import struct
for theme in range(4):
 data=(stage/f'models/psp-{theme}.glb').read_bytes();j=json.loads(data[20:20+struct.unpack_from('<I',data,12)[0]])
 n=next(n for n in j['nodes'] if n.get('name')=='stick-textured-cap');primitives=j['meshes'][n['mesh']]['primitives'];assert len(primitives)==1
 assert j['accessors'][primitives[0]['attributes']['POSITION']]['count']>1000
rims='''import Foundation
let base=URL(fileURLWithPath:CommandLine.arguments[1])
for model in ["nds","gba","gbc","psp","3ds"]{for theme in 0..<4{try exportAndroidRims(model:model,theme:theme,glb:base.appendingPathComponent("models/\\(model)-\\(theme).glb"),destination:base.appendingPathComponent("rims/\\(model)-\\(theme)"))}}
'''
rim=executable('RimExporter',root/'Scripts/AndroidRimExport.swift',rims);subprocess.run([str(rim),str(stage)],check=True)
record={'private_only':True,'defines':['UNCLEED_ANDROID_EXPORT'],'sources':{str(x.relative_to(root)):hashlib.sha256(x.read_bytes()).hexdigest() for x in shared+[root/'Scripts/export-android-gltf.swift',root/'Scripts/AndroidRimExport.swift']},'psp_cap_single_mesh_verified':True,'models':{x.name:hashlib.sha256(x.read_bytes()).hexdigest() for x in sorted((stage/'models').glob('*.glb'))}}
shutil.copytree(stage/'models',out/'models',dirs_exist_ok=True);shutil.copytree(stage/'rims',out/'rims',dirs_exist_ok=True)
(out/'model-pack-provenance.json').write_text(json.dumps(record,indent=2)+'\n');print('PASS: 33 models, 20 rims; all four PSP textured caps present and batched')
