#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""An original two-instruction MIPS loop, for core loading only; no game assets."""
import struct,sys
from pathlib import Path
out=Path(sys.argv[1]);base=0x08804000
b=bytearray(0x2100)
ident=b'\x7fELF'+bytes([1,1,1])+bytes(9)
b[:52]=struct.pack('<16sHHIIIIIHHHHHH',ident,2,8,1,base,52,0x2000,0x10a23001,52,32,1,40,4,3)
b[52:84]=struct.pack('<IIIIIIII',1,0x1000,base,base,0x200,0x1000,7,0x1000)
b[0x1000:0x1008]=struct.pack('<II',(2<<26)|((base>>2)&0x03ffffff),0)
module=struct.pack('<HBB28sIIIII',0,1,0,b'UncleEd Original Probe',0,0,0,0,0)
b[0x1100:0x1100+len(module)]=module
names=b'\0.text\0.rodata.sceModuleInfo\0.shstrtab\0';b[0x1200:0x1200+len(names)]=names
for i,row in enumerate([(0,0,0,0,0,0,0,0,0,0),(1,1,6,base,0x1000,8,0,0,4,0),(7,1,2,base+0x100,0x1100,len(module),0,0,4,0),(29,3,0,0,0x1200,len(names),0,0,1,0)]):
 b[0x2000+i*40:0x2000+(i+1)*40]=struct.pack('<10I',*row)
# PBP with an ELF DATA.PSP section; other optional sections are empty.
header=struct.pack('<4sI8I',b'\0PBP',0x10000,*([40]*7+[40+len(b)]))
out.parent.mkdir(parents=True,exist_ok=True);out.write_bytes(header+b)
