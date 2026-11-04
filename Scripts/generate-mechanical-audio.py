#!/usr/bin/env python3
"""Deterministic local Foley synthesis; no recordings, ROM audio or network used."""
from pathlib import Path
import math,random,struct,wave
root=Path(__file__).resolve().parents[1]
rate=32000
for name,duration in [('psp-door-open',.36),('psp-disc-seat',.18),('psp-door-close',.22),('psp-disc-read',1.8)]:
 rng=random.Random(408);samples=[];phase=0;low=0
 for i in range(int(duration*rate)):
  t=i/rate;noise=rng.uniform(-1,1);low=.86*low+.14*noise
  if name=='psp-disc-read':
   ramp=min(1,t/.70);freq=170+650*ramp*ramp;phase+=2*math.pi*freq/rate
   env=min(1,t/.20)*min(1,(duration-t)/.45)
   motor=(math.sin(phase)+.22*math.sin(2.01*phase))*.060
   servo=sum(math.exp(-max(0,t-at)*85)*math.sin((t-at)*2*math.pi*1250)*.055 for at in [.83,1.05,1.26] if t>=at)
   value=env*(motor+servo+.02*low)
  elif name=='psp-disc-seat':value=.24*math.exp(-t*45)*(math.sin(2*math.pi*720*t)+noise*.40)
  elif name=='psp-door-close':value=.32*math.exp(-t*70)*noise+.15*math.exp(-max(0,t-.036)*95)*math.sin(2*math.pi*290*t) if t>=.036 else .25*math.exp(-t*70)*noise
  else:value=.12*math.exp(-t*35)*noise+.045*math.sin(2*math.pi*(180*t+260*t*t))*math.sin(math.pi*t/duration)**2+.04*low
  samples.append(struct.pack('<h',int(max(-.95,min(.95,value))*32767)))
 dest=root/'Assets/Sounds'/f'{name}.wav';dest.parent.mkdir(parents=True,exist_ok=True)
 with wave.open(str(dest),'wb') as f:f.setnchannels(1);f.setsampwidth(2);f.setframerate(rate);f.writeframes(b''.join(samples))
