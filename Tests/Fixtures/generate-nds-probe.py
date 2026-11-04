#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Original ARM9/ARM7 self-loops, no Nintendo logo, BIOS or game data."""
import struct,sys
from pathlib import Path
b=bytearray(128*1024);b[:12]=b'UNCLEED TEST';b[12:16]=b'UEPR';b[16:18]=b'00'
for offset,rom,ram in [(0x20,0x200,0x02000000),(0x30,0x204,0x03800000)]:struct.pack_into('<4I',b,offset,rom,ram,ram,4)
struct.pack_into('<II',b,0x80,0x208,0x200);struct.pack_into('<II',b,0x200,0xeafffffe,0xeafffffe)
def crc(data):
 v=0xffff
 for x in data:
  v^=x
  for _ in range(8):v=(v>>1)^ (0xa001 if v&1 else 0)
 return v
struct.pack_into('<H',b,0x15e,crc(b[:0x15e]));p=Path(sys.argv[1]);p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(b)
