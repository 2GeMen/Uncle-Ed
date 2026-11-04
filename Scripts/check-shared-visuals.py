#!/usr/bin/env python3
"""Read-only paired-source, asset-integrity and static-bake preflight."""
from pathlib import Path
import hashlib,json,sys
root=Path(__file__).resolve().parents[1]
mac=root if root.name=='uncleed' else root.parent/'uncleed'
ios=root if root.name=='uncleed-ios' else root.parent/'uncleed-ios'
paired=(mac/'Sources').is_dir() and (ios/'Mobile').is_dir()
errors=[]
def sha(path):return hashlib.sha256(path.read_bytes()).hexdigest()
def compare(a,b):
 if not b.exists() or a.read_bytes()!=b.read_bytes():errors.append(str(a)+' != '+str(b))
if paired:
 for a in sorted((mac/'Sources').glob('*.swift')):compare(a,ios/'Sources'/a.name)
 for name in ['SpatialMachine.swift','SpatialCarousel.swift']:compare(mac/'Sources'/name,ios/'Mobile/Sources/Rendering'/name)
 for folder in ['Assets/Skins/Spatial','Assets/Logos','Assets/Sounds','Assets/Skins/ThemePreviews','Assets/Patterns']:
  names={p.relative_to(mac/folder) for p in (mac/folder).rglob('*') if p.is_file() and p.name!='.DS_Store'}
  peer={p.relative_to(ios/folder) for p in (ios/folder).rglob('*') if p.is_file() and p.name!='.DS_Store'}
  for name in names|peer:
   a,b=mac/folder/name,ios/folder/name
   if not a.exists():errors.append('iOS-only shared asset: '+str(name))
   else:compare(a,b)
 for name in ['Assets/media-slots.json','Assets/Skins/spatial-manifest.json','Assets/game-catalog-seed-v1.json']:compare(mac/name,ios/name)
if paired:
 for name in ['GameCatalog.swift','PickerMotion.swift']:compare(mac/'Sources'/name,ios/'Mobile/Sources/Domain'/name)
manifest=root/'Assets/Skins/spatial-manifest.json'
if manifest.exists():
 data=json.loads(manifest.read_text())
 for name,digest in data['bakeInputs'].items():
  owner=ios if name.startswith('Mobile/') else root
  path=owner/name
  if path.exists() and sha(path)!=digest:errors.append('Stale bake input: '+name+'; run Mobile/Scripts/export-mac-layers.py')
 for name,digest in data['assets'].items():
  path=root/name
  if not path.exists() or sha(path)!=digest:errors.append('Changed/missing baked geometry: '+name)
 actual={str(p.relative_to(root)) for p in (root/'Assets/Skins/Spatial').rglob('*') if p.is_file() and p.name!='.DS_Store'}
 if actual!=set(data['assets']):errors.append('Baked package inventory differs from spatial-manifest.json')
else:errors.append('Missing shared spatial bake manifest')
if errors:
 print('Shared visuals are not ready:\n'+'\n'.join(errors));sys.exit(1)
print('Shared visuals: '+('Mac, iPad and iPhone sources/assets match; ' if paired else 'peer checkout absent; local checks only; ')+'geometry integrity and static bake freshness passed.')
