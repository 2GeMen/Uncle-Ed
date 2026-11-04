#!/usr/bin/env python3
"""Compile the checked-in AppKit renderer as a graphics-only exporter. No ROM or user data is opened."""
from pathlib import Path
import subprocess,tempfile,hashlib,json,re,shutil
root=Path(__file__).resolve().parents[2]
source=root/'Sources';output=root/'Assets/Skins/MobileRenders';output.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='uncleed-layer-export-') as temp:
 work=Path(temp);staging=work/'Rendered';staging.mkdir();s=(source/'main.swift').read_text();s=s[:s.index('let app = NSApplication.shared')]
 s=s.replace('let support = fm.homeDirectoryForCurrentUser.appendingPathComponent(\n  "Library/Application Support/UncleED")','let support = URL(fileURLWithPath:CommandLine.arguments[1]).appendingPathComponent("scratch")')
 s=s.replace('let bundledAssets = Bundle.main.resourceURL!.appendingPathComponent("Assets")','let bundledAssets = URL(fileURLWithPath:CommandLine.arguments[2])')
 a=s.index('    prepareStorage()',s.index('override init(frame: NSRect)'));b=s.index('  required init?(coder:',a);s=s[:a]+'  }\n'+s[b:]
 s=s.replace('contentsOf: assets.appendingPathComponent("Skins/NDS/black-edition-lid.png")','contentsOf: bundledAssets.appendingPathComponent("Skins/NDS/black-edition-lid.png")')
 (work/'main.swift').write_text(s+'\n'+Path(__file__).with_name('MacLayerExport.swift').read_text()+'\n'+Path(__file__).with_name('SpatialBake.swift').read_text())
 # Graphics-only linking shims: no emulation is executed by this tool.
 header=(source/'Bridge.h').read_text();stubs=['#include "Bridge.h"']
 for ret,name,args in re.findall(r'^(.+?)\b(emu_\w+)\(([^;]*)\);',header,re.MULTILINE):
  ret=ret.strip().split('\n')[-1].strip();value='return "";' if 'char' in ret and '*' in ret else '' if ret=='void' else 'return 0;'
  stubs.append(f'{ret} {name}({args})'+'{'+value+'}')
 (work/'bridge.c').write_text('\n'.join(stubs))
 subprocess.run(['xcrun','clang','-I',str(source),'-c',str(work/'bridge.c'),'-o',str(work/'bridge.o')],check=True)
 command=['xcrun','swiftc','-module-cache-path',str(work/'cache'),'-import-objc-header',str(source/'Bridge.h'),str(work/'main.swift')]+[str(source/(name+'.swift')) for name in ['Classic','Modern','Controls','Cartridges','Library','GameCatalog','PickerMotion','GBCScene','MechanicalControls','SpatialMachine','SpatialCarousel','UniversalStage']]+[str(work/'bridge.o')]
 for framework in ['Cocoa','CoreImage','QuartzCore','UniformTypeIdentifiers','SceneKit']:command+=['-framework',framework]
 subprocess.run(command+['-o',str(work/'export')],check=True)
 subprocess.run([str(work/'export'),str(staging),str(root/'Assets'),"--render-source"]+(["--workflow"] if "--workflow" in __import__("sys").argv else []),check=True)
 files=[source/(name+'.swift') for name in ['main','Classic','Modern','Controls','Cartridges','Library','GameCatalog','PickerMotion','GBCScene','MechanicalControls','SpatialMachine','SpatialCarousel','UniversalStage']]
 files.append(root/'Assets/media-slots.json')
 files += [Path(__file__),Path(__file__).with_name('MacLayerExport.swift'),Path(__file__).with_name('SpatialBake.swift')]
 manifest={'description':'Shared baked SceneKit geometry and materials from native Mac drawing sources; live game frames remain independent screen textures.','sourceSHA256':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
 (staging/'source-manifest.json').write_text(json.dumps(manifest,indent=2))
 # Publish only after the complete render and opaque-lid checks succeed.
 for rendered in staging.iterdir():
  if rendered.is_file(): shutil.copy2(rendered,output/rendered.name)
 for spatial_destination in [root/'Assets/Skins/Spatial',root.parent/'uncleed/Assets/Skins/Spatial']:
  if spatial_destination.exists(): shutil.rmtree(spatial_destination)
  shutil.copytree(staging/'Spatial',spatial_destination)
 # The native 3D caps replace cropped pressed-state screenshots.
 for obsolete in output.glob("*-key-*.png"): obsolete.unlink()

# Workflow previews are verification artifacts, never runtime assets.
validation=root/"Validation/iPad-Refinement-2026-10-23"
validation.mkdir(parents=True,exist_ok=True)
for preview in output.glob("mac-*"):
 preview.replace(validation/preview.name)

# The same preview bitmap is consumed by the desktop and mobile theme grids.
import shutil
for destination in [root/"Assets/Skins/ThemePreviews",root.parent/"uncleed/Assets/Skins/ThemePreviews"]:
 destination.mkdir(parents=True,exist_ok=True)
 for preview in output.glob("*-preview.png"):
  shutil.copy2(preview,destination/preview.name.replace("-preview.png",".png"))

for preview in output.glob("*-preview.png"):
 preview.unlink()

# Keep an independent digest for baked inputs and the actual geometry package.
# Live camera/input code is intentionally separate from static bake freshness.
bake_inputs=['Sources/Classic.swift','Sources/Modern.swift','Sources/Controls.swift','Sources/Cartridges.swift','Sources/GBCScene.swift','Sources/MechanicalControls.swift','Assets/media-slots.json','Assets/Patterns/3ds-sunmoon-silk.json','Mobile/Scripts/MacLayerExport.swift','Mobile/Scripts/SpatialBake.swift','Mobile/Scripts/export-mac-layers.py']
spatial_manifest={'format':1,'bakeInputs':{p:hashlib.sha256((root/p).read_bytes()).hexdigest() for p in bake_inputs},'assets':{str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((root/'Assets/Skins/Spatial').rglob('*')) if p.is_file() and p.name!='.DS_Store'}}
for target in [root,root.parent/'uncleed']:
 (target/'Assets/Skins/spatial-manifest.json').write_text(json.dumps(spatial_manifest,indent=2)+'\n')
