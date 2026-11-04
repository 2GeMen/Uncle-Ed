#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Archive a reviewed core working tree, including tracked submodules and patches.

Use on exact source trees used for the shipped binary. This is not a substitute
for checking build flags, dependency revisions and binary provenance.
"""
import argparse, hashlib, io, json, subprocess, tarfile
from pathlib import Path

p = argparse.ArgumentParser()
p.add_argument('source', type=Path)
p.add_argument('output', type=Path)
p.add_argument('--prefix', required=True)
a = p.parse_args()
root = a.source.resolve()
def git(*args):
    return subprocess.check_output(['git', '-C', str(root), *args])

names = git('ls-files', '--recurse-submodules', '-z').decode().split('\0')
excluded, hashes = [], {}
private = {'.gb', '.gbc', '.gba', '.nds', '.3ds', '.cia', '.iso', '.cso',
           '.pbp', '.sav', '.srm', '.uestate', '.p12', '.pem', '.keystore'}
binaries = {'.a', '.so', '.dylib', '.dll', '.exe', '.prx', '.elf', '.o',
            '.zip', '.7z', '.apk', '.ipa'}
a.output.parent.mkdir(parents=True, exist_ok=True)
with tarfile.open(a.output, 'w:gz') as out:
    for name in sorted(set(names)):
        if not name:
            continue
        path = root / name
        if not path.exists() and not path.is_symlink():
            excluded.append({'path': name, 'reason': 'not present locally'})
            continue
        if path.is_dir():
            continue
        if path.suffix.lower() in private | binaries:
            excluded.append({'path': name, 'reason': 'game/test payload or binary, not build source'})
            continue
        if path.is_symlink():
            # Refuse links escaping the source tree; keep ordinary source links.
            if not path.resolve().is_relative_to(root):
                raise SystemExit('External source symlink: ' + name)
        else:
            data = path.read_bytes()
            if data[:4] == b'\x7fELF' or data[:4] in (b'\xcf\xfa\xed\xfe', b'\xca\xfe\xba\xbe'):
                excluded.append({'path': name, 'reason': 'executable payload'})
                continue
            hashes[name] = hashlib.sha256(data).hexdigest()
        out.add(path, arcname=a.prefix + '/' + name, recursive=False)
    diff = git('diff', '--binary', 'HEAD')
    manifest = {
        'revision': git('rev-parse', 'HEAD').decode().strip(),
        'submodules': git('submodule', 'status', '--recursive').decode().splitlines(),
        'working_tree_modifications_included': bool(diff),
        'files_sha256': hashes, 'excluded': excluded,
        'note': 'Files contain applied modifications. Do not apply LOCAL-CHANGES.patch twice.'
    }
    for name, data in [('SOURCE-MANIFEST.json', json.dumps(manifest, indent=2).encode()),
                       ('LOCAL-CHANGES.patch', diff)]:
        info = tarfile.TarInfo(a.prefix + '/' + name)
        info.size = len(data)
        out.addfile(info, io.BytesIO(data))
print(json.dumps({'archive': a.output.name, 'revision': manifest['revision'],
                  'files': len(hashes), 'excluded': len(excluded),
                  'sha256': hashlib.sha256(a.output.read_bytes()).hexdigest()}))
