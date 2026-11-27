import numpy as np
from scipy.signal import lfilter, butter
from scipy.io import wavfile
SR=48000; DUR=21.0; BPM=120; BEAT=60/BPM; N=int(SR*DUR)
rng=np.random.default_rng(7)
def t_(d): return np.arange(int(SR*d))/SR
def hz(m): return 440*2**((m-69)/12)
def add(buf,sig,at,g=1.0):
    i=int(round(at*SR)); j=min(N,i+len(sig))
    if i<N: buf[i:j]+=g*sig[:j-i]
def lp(x,fc,o=2): b,a=butter(o,fc/(SR/2)); return lfilter(b,a,x)
def hp(x,fc,o=2): b,a=butter(o,fc/(SR/2),'high'); return lfilter(b,a,x)
drums=np.zeros(N); bass=np.zeros(N); pad=np.zeros(N); arp=np.zeros(N); sfx=np.zeros(N)
# chords per bar (2s): A minor key
A,F,C,G=[57,60,64],[53,57,60],[48,52,55],[55,59,62]
bars=[A,F,C,G,A,F,C,G,F,G,A]
roots={id(A):45,id(F):41,id(C):48,id(G):43}
def kick():
    t=t_(0.35); f=45+75*np.exp(-t*30); ph=2*np.pi*np.cumsum(f)/SR
    return np.sin(ph)*np.exp(-t*9)
def hat():
    t=t_(0.06); return hp(rng.standard_normal(len(t)),7000)*np.exp(-t*70)
def pluck(m,d=0.45):
    t=t_(d); f=hz(m); s=np.sin(2*np.pi*f*t)+0.3*np.sin(4*np.pi*f*t)+0.1*np.sin(6*np.pi*f*t)
    return s*np.exp(-t*7)*np.minimum(1,t/0.004)
def padv(notes,d):
    t=t_(d); s=np.zeros(len(t))
    for m in notes:
        for det in (-0.08,0.0,0.08):
            f=hz(m+12)*2**(det/12); s+=2*((f*t)%1)-1
    s=lp(s,1400,2)/9
    env=np.minimum(1,t/0.35)*np.minimum(1,(d-t)/0.25)
    return s*env
def bassn(m,d):
    t=t_(d); f=hz(m); s=np.sin(2*np.pi*f*t)+0.25*np.sign(np.sin(2*np.pi*f*t))
    return lp(s,500)*np.exp(-t*2.5)*np.minimum(1,t/0.005)*np.minimum(1,(d-t)/0.02)
nbeats=int(DUR/BEAT)
for b in range(nbeats):
    tb=b*BEAT
    if tb<20.0: add(drums,kick(),tb,0.9 if tb>=0 else 0)
    if tb<20.0: add(drums,hat(),tb+BEAT/2,0.12)
    if 4.0<=tb<20.0 and b%2==1: add(drums,hp(rng.standard_normal(int(SR*0.12)),1500)*np.exp(-t_(0.12)*25),tb,0.10)  # soft snare-ish on 2&4
for i,ch in enumerate(bars):
    t0=i*2.0
    if t0>=DUR: break
    d=min(2.0,DUR-t0) if i<10 else DUR-t0
    root=roots[id(ch)]
    add(pad,padv(ch,d),t0,0.55)
    if t0<20.0:
        for k in range(4):
            add(bass,bassn(root,BEAT*0.9),t0+k*BEAT,0.35)
    # arp eighths
    pat=[ch[0]+12,ch[1]+12,ch[2]+12,ch[1]+24]
    for k in range(8):
        at=t0+k*BEAT/2
        if at<20.0 and at>=0: add(arp,pluck(pat[k%4],0.4),at,0.16)
# final chord at 18 and 20
for m in A: add(arp,pluck(m+12,1.0),20.0,0.18)
# SFX: whoosh before cuts, ticks on pops, key clicks
def whoosh(d=0.5):
    t=t_(d); n=rng.standard_normal(len(t)); n=lp(hp(n,300),3000)
    return n*(t/d)**2*np.minimum(1,(d-t)/0.03)
for cut in (4.0,7.0,15.0,18.0): add(sfx,whoosh(0.5),cut-0.5,0.10)
for k in range(6): add(sfx,pluck(81,0.2),k*0.25,0.08)          # pane pops (A5)
for k in range(5): add(sfx,pluck(76+ (k%2)*5,0.2),7.25+k*0.25,0.07)  # rows (E5/A5)
def click():
    t=t_(0.03); return hp(rng.standard_normal(len(t)),2500)*np.exp(-t*180)
for at in (12.5,12.55,12.6,13.5): add(sfx,click(),at,0.18)
add(sfx,pluck(72,0.4),11.0,0.10); add(sfx,pluck(76,0.4),11.0,0.07)   # awaiting chime (C/E over F chord)
mix=drums*0.8+lp(bass,600)*1.0+pad*0.9+lp(arp,5000)*0.9+lp(sfx,6000)*1.0
fade=np.ones(N); fl=int(0.8*SR); fade[-fl:]=np.linspace(1,0,fl)**1.5
mix=np.tanh(mix*1.2)*fade
mix=mix/np.max(np.abs(mix))*0.89
st=np.stack([mix,mix],1)
wavfile.write("audio.wav",SR,(st*32767).astype(np.int16))
print("ok",N/SR)
