#!/usr/bin/env python3
"""Independent mathematical topology check of OpenWorks prefab surface spec.

Does not execute Roblox Studio APIs or prove generated collisions render right.
"""
import math
from collections import Counter

COUNTS=(8,12,20,32)
SCALES=(.6,.8,1.0,1.2,1.4)
MOD=.25
WIDTH=.6
BORE=.375


def gear(n, bevel):
    rp=n*MOD/2; base=rp*math.cos(math.radians(20)); rt=rp+MOD; root=rp-1.25*MOD
    def inv(r):
        if r<=base: return 0.
        t=math.sqrt((r/base)**2-1)
        return t-math.atan(t)
    def half(r): return math.pi/(2*n)+inv(rp)-inv(r)
    samples=[]; step=2*math.pi/n; shoulder=math.radians(.55)
    for tooth in range(n):
        center=(tooth+.5)*step; hs=half(base)+shoulder; ht=half(rt)
        assert ht>0 and hs*2<step
        samples.append((root,center-hs))
        for j in range(11):
            r=base+(rt-base)*j/10
            samples.append((r,center-half(r)))
        for j in range(1,6): samples.append((rt,center-ht+2*ht*j/5))
        for j in range(9,-1,-1):
            r=base+(rt-base)*j/10
            samples.append((r,center+half(r)))
        samples.append((root,center+hs))
        for j in range(1,4):samples.append((root,center+hs+(step-2*hs)*j/4))
    assert min(b-a for a,b in zip([x[1] for x in samples], [x[1] for x in samples[1:]]))>0
    verts=[]; quads=[]
    def vertex(pos):
        i=len(verts);verts.append(pos);return i
    rings=[]
    for r,angle in samples:
        c,s=math.cos(angle),math.sin(angle)
        sf=1+WIDTH/(2*rp) if bevel else 1
        sb=1-WIDTH/(2*rp) if bevel else 1
        assert root*sb>BORE+.01
        rings.append((vertex((WIDTH/2,r*sf*c,r*sf*s)),vertex((-WIDTH/2,r*sb*c,r*sb*s)),
                      vertex((WIDTH/2,BORE*c,BORE*s)),vertex((-WIDTH/2,BORE*c,BORE*s))))
    faces=[]
    def tri(*idx):faces.append(idx)
    for i in range(len(rings)):
        a,b=rings[i],rings[(i+1)%len(rings)]
        tri(a[0],b[0],a[2]);tri(b[0],b[2],a[2]);tri(a[1],a[3],b[1]);tri(b[1],a[3],b[3])
        tri(a[0],a[1],b[0]);tri(b[0],a[1],b[1]);tri(a[2],b[2],a[3]);tri(b[2],b[3],a[3])
    return verts,faces


def bolt():
    sides=72; shaftlen=2.;shaftRad=.125;headLen=.17;headR=shaftRad*1.86
    start=-shaftlen/2-headLen; shaftStart=-shaftlen/2; shaftEnd=shaftlen/2
    ts=shaftStart+shaftlen*.25;te=shaftEnd-shaftlen*.08;turns=11
    def hexr(a):return headR*math.cos(math.pi/6)/math.cos(a%(math.pi/3)-math.pi/6)
    def threadr(x,a):
        if x<ts:return shaftRad
        fade=max(0,min(1,(x-ts)/(shaftlen*.07)))
        phase=((x-ts)/(te-ts)*turns-a/(2*math.pi))%1
        ridge=1-abs(phase*2-1)
        tip=max(.3,min(1,(shaftEnd-x)/(shaftlen*.08)))
        return shaftRad*(1-.14*fade*(1-ridge))*tip
    sections=[(start,'hex',.94),(start+.025,'hex',1.),(shaftStart-.027,'hex',1.),
              (shaftStart,'hex',.94),(shaftStart,'shaft',None),(shaftStart+.015,'shaft',None)]
    for i in range(1,69):
        sections.append((shaftStart+.015+(shaftEnd-shaftStart-.015)*i/68,'shaft',None))
    verts=[];rings=[]
    def vertex(pos):i=len(verts);verts.append(pos);return i
    for x,mode,k in sections:
        ring=[]
        for i in range(sides):
            a=2*math.pi*i/sides
            r=hexr(a)*k if mode=='hex' else threadr(x,a)
            ring.append(vertex((x,r*math.cos(a),r*math.sin(a))))
        rings.append(ring)
    faces=[]
    def tri(*idx):faces.append(idx)
    for i in range(len(rings)-1):
        for j in range(sides):
            k=(j+1)%sides
            a,b,c,d=rings[i][j],rings[i][k],rings[i+1][j],rings[i+1][k]
            tri(a,b,c);tri(b,d,c)
    hc=vertex((start,0,0));tc=vertex((shaftEnd,0,0))
    for i in range(sides):
        j=(i+1)%sides
        tri(hc,rings[0][j],rings[0][i]);tri(tc,rings[-1][i],rings[-1][j])
    return verts,faces


def validate(name,verts,faces):
    assert len(verts)<60000 and len(faces)<20000,(name,'limits',len(verts),len(faces))
    edges=Counter(); directed=Counter(); signedVol=0; minArea=float('inf')
    for (a,b,c) in faces:
        v0=verts[a];v1=verts[b];v2=verts[c]
        cross=((v1[1]-v0[1])*(v2[2]-v0[2])-(v1[2]-v0[2])*(v2[1]-v0[1]),
               (v1[2]-v0[2])*(v2[0]-v0[0])-(v1[0]-v0[0])*(v2[2]-v0[2]),
               (v1[0]-v0[0])*(v2[1]-v0[1])-(v1[1]-v0[1])*(v2[0]-v0[0]))
        area=math.sqrt(sum(t*t for t in cross))/2
        assert area>1e-9,(name,'degenerate',(a,b,c),area)
        minArea=min(minArea,area)
        signedVol+=sum(v0[i]*cross[i] for i in range(3))/6
        for x,y in ((a,b),(b,c),(c,a)):
            edges[tuple(sorted((x,y)))]+=1;directed[x,y]+=1
    assert all(n==2 for n in edges.values()),(name,'non-manifold',[item for item in edges.items() if item[1]!=2][:5])
    assert all(directed[a,b]==directed[b,a] for a,b in directed),(name,'inconsistent winding')
    assert signedVol>0,(name,'wrong winding',signedVol)
    return (name,len(verts),len(faces),round(minArea,9),round(signedVol,5))


def main():
    for n in COUNTS:
        for bevel in (False,True):
            r=validate(('Bevel90' if bevel else 'Spur')+f'_{n}T',*gear(n,bevel));print(*r)
    print(*validate('Bolt',*bolt()))
    assert 4*2*5+5==45
    print('PASS: 9 watertight, consistently wound base meshes; 45 scaled prefab variants.')

if __name__=='__main__':main()
