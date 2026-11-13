#!/usr/bin/env python3
"""Recreate audit inputs from the immutable result refs; run in this git clone."""
import io, pathlib, subprocess, sys, tarfile
out = pathlib.Path(sys.argv[1]); out.mkdir(parents=True, exist_ok=True)
for path, sha in [('fresh','4bfbe4b29b36b24ce7e1b6ab381331ec96778129'),
                  ('upgrade','29040504ac466e72714ec0c357fdaca6e005e2e9')]:
    files = subprocess.check_output(['git','ls-tree','-r','--name-only',sha], text=True).splitlines()
    for name in files:
        if '/' in name: continue
        data = subprocess.check_output(['git','show',sha+':'+name])
        (out/name).write_bytes(data)
        if name.endswith('.tgz'):
            dest = out/name[:-4]; dest.mkdir(exist_ok=True)
            with tarfile.open(fileobj=io.BytesIO(data)) as archive:
                for member in archive.getmembers():
                    if member.isfile() and '..' not in pathlib.Path(member.name).parts:
                        target = dest/member.name.lstrip('/')
                        target.parent.mkdir(parents=True, exist_ok=True)
                        target.write_bytes(archive.extractfile(member).read())
print('Inputs:', out, '; next run docs/e2e4-fix1/audit.py with this path')
