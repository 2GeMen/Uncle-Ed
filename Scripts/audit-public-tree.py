#!/usr/bin/env python3
"""Fail closed before publishing source or an unpacked installer.

This is a content/provenance gate, not a legal opinion. Run on the exported
staging tree too; .gitignore alone does not inspect an archive or old history.
"""
from pathlib import Path
import argparse,json,re,hashlib,sys
ROM_EXT={'.gba','.gb','.gbc','.nds','.3ds','.cci','.cxi','.3dsx','.cia','.iso','.cso','.chd','.pbp','.srm','.sav','.state','.uestate','.rtc','.dsv'}
SECRET_EXT={'.p12','.p8','.mobileprovision','.keystore','.jks','.pem'}
PRIVATE_DIRS={'roms','saves','savedata','bios','firmware','backups','validation','previews','incoming','references','retiredassets','privateassets','covers'}
IGNORE={'.git','.gradle','.build','__pycache__','node_modules'}
BINARY_EXT={'.so','.dylib','.dll','.a','.framework','.aar','.jar','.apk','.ipa','.zip','.7z','.dmg'}
ASSET_EXT={'.png','.jpg','.jpeg','.svg','.scn','.glb','.gltf','.wav','.mp3','.m4a','.icns','.pdf','.ttf','.otf','.ktx','.ktx2','.hdr','.exr'}
SECRET_PATTERNS=[re.compile(rb'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),re.compile(rb'\b(?:ghp_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,}|AKIA[A-Z0-9]{16})\b')]

def content_kind(p):
 with p.open('rb') as f:
  h=f.read(0x8200)
 if len(h)>0x108 and h[0x104:0x108]==bytes([0xce,0xed,0x66,0x66]):return 'Game Boy payload signature'
 if len(h)>0x10 and h[4:12]==bytes.fromhex('24ffae51699aa221'):return 'GBA payload signature'
 if len(h)>0x104 and h[0x100:0x104] in (b'NCSD',b'NCCH'):return '3DS payload signature'
 if len(h)>0x8006 and h[0x8001:0x8006]==b'CD001':return 'disc image payload signature'
 return None

def audit(root,require_release=False):
 root=Path(root).resolve();findings=[];registry=root/'Shared/asset-provenance.json'
 assets=json.loads(registry.read_text()).get('assets',{}) if registry.exists() else {}
 for p in sorted(root.rglob('*')):
  rel=p.relative_to(root)
  if any(x in IGNORE for x in rel.parts):continue
  if p.is_symlink():findings.append((str(rel),'symlink is not a distributable asset'));continue
  if not p.is_file():continue
  ext=p.suffix.lower();parts={x.lower() for x in rel.parts[:-1]}
  if ext in ROM_EXT or parts&PRIVATE_DIRS:findings.append((str(rel),'private/game content path'))
  if ext in SECRET_EXT:findings.append((str(rel),'signing or credential file'))
  if ext in BINARY_EXT:findings.append((str(rel),'unreviewed binary/archive in source tree'))
  kind=content_kind(p)
  if kind:findings.append((str(rel),kind))
  if p.stat().st_size<4_000_000:
   data=p.read_bytes()
   if any(rx.search(data) for rx in SECRET_PATTERNS):findings.append((str(rel),'credential signature; value redacted'))
   if re.search(rb'/Users/[A-Za-z0-9._-]+/',data) or (b'CODE_SIGN_IDENTITY' + b' = "Apple Development:') in data:findings.append((str(rel),'private build-machine identity'))
  if ext in ASSET_EXT:
   entry=assets.get(str(rel));sha=hashlib.sha256(p.read_bytes()).hexdigest()
   if not entry or entry.get('status')!='approved' or entry.get('sha256')!=sha or not entry.get('license'):
    findings.append((str(rel),'asset requires rights review and hash approval'))
 if require_release:
  release=root/'Shared/release-readiness.json'
  if not release.exists():findings.append(('release','missing readiness record'))
  else:
   d=json.loads(release.read_text())
   for key in ['source_license_approved','assets_approved','core_corresponding_source_verified','android_phone_validated','android_tablet_validated','apple_builds_validated','signing_ready']:
    if d.get(key) is not True:findings.append(('release',key+' is not complete'))
 return findings

if __name__=='__main__':
 ap=argparse.ArgumentParser();ap.add_argument('root',nargs='?',default=Path(__file__).resolve().parents[1]);ap.add_argument('--release',action='store_true');ap.add_argument('--json',action='store_true');a=ap.parse_args();issues=audit(a.root,a.release)
 if a.json:print(json.dumps({'ready':not issues,'findings':[{'path':p,'reason':r} for p,r in issues]},indent=2))
 else:
  for p,r in issues:print(f'BLOCKED {p}: {r}')
  print('PASS' if not issues else f'BLOCKED: {len(issues)} finding(s)')
 sys.exit(bool(issues))
