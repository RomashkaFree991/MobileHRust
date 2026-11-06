import os,sys,json,struct,math
import numpy as np
from scipy.spatial.transform import Rotation as R
from pygltflib import GLTF2, BufferView, Accessor, Animation, AnimationChannel, AnimationSampler, AnimationChannelTarget
base=os.path.dirname(os.path.dirname(os.path.abspath(__file__))); root=os.path.join(base,'assets/character'); clipdir=os.path.join(base,'tools/unity_clips')
# Load old curve sampling without executing previous writer.
src=open(os.path.join(base,'tools/convert_muscles.py')).read().split("for f in ['player.glb'")[0]; scope={'__file__':os.path.join(base,'tools/convert_muscles.py')}; exec(compile(src,'convert_muscles.py','exec'),scope); curves=scope['curves']; mp=scope['mp']
d=json.load(open(os.path.join(clipdir,'avatar.json'))); h=d['m_Avatar']['m_Human']['data']; sk=h['m_Skeleton']['data']; nodes=sk['m_Node']; pose=h['m_SkeletonPose']['data']['m_X']; tos=dict(d['m_TOS']); names=[tos.get(v,'').split('/')[-1] for v in sk['m_ID']]; idx={n:i for i,n in enumerate(names) if n};
def qmir(v): return R.from_quat([v['x'],-v['y'],-v['z'],v['w']])
refrots=[qmir(p['q']) for p in pose]; refg=[]; refp=[]
for i,n in enumerate(nodes):
 p=n['m_ParentId']; t=pose[i]['t']; v=np.array([-t['x'],t['y'],t['z']]); refg.append((refg[p] if p>=0 else R.identity())*refrots[i]); refp.append((refp[p]+refg[p].apply(v)) if p>=0 else v)
childs={'pelvis':'spine1','spine1':'spine2','spine2':'spine3','spine3':'neck','neck':'head',
 'l_hip':'l_knee','l_knee':'l_foot','l_foot':'l_toe','r_hip':'r_knee','r_knee':'r_foot','r_foot':'r_toe',
 'l_clavicle':'l_upperarm','l_upperarm':'l_forearm','l_forearm':'l_hand','r_clavicle':'r_upperarm','r_upperarm':'r_forearm','r_forearm':'r_hand'}
def shortest(a,b):
 a=a/np.linalg.norm(a);b=b/np.linalg.norm(b);v=np.cross(a,b); dot=np.dot(a,b)
 if dot<-0.9999:
  axis=np.cross(a,[1,0,0]);axis=axis if np.linalg.norm(axis)>1e-6 else np.cross(a,[0,1,0]);return R.from_rotvec(axis/np.linalg.norm(axis)*np.pi)
 return R.from_quat([*v,1+dot])
def convert(file):
 g=GLTF2().load(os.path.join(root,file)); data=bytearray(g.binary_blob());g.animations=[]; targetidx={n.name:i for i,n in enumerate(g.nodes)}; parents={c:i for i,n in enumerate(g.nodes) for c in n.children or []}; gt=[];pt=[]
 for i,n in enumerate(g.nodes):
  p=parents.get(i,-1);r=R.from_quat(n.rotation or [0,0,0,1]);v=np.array(n.translation or [0,0,0]);gt.append((gt[p] if p>=0 else R.identity())*r);pt.append((pt[p]+gt[p].apply(v)) if p>=0 else v)
 # Establish target reference T pose from segment direction of source avatar.
 tpose=[]
 for i,n in enumerate(g.nodes):
  name=n.name; par=parents.get(i,-1)
  if name in childs and name in idx and childs[name] in idx and childs[name] in targetidx:
   vtarget=pt[targetidx[childs[name]]]-pt[i]; vsrc=refp[idx[childs[name]]]-refp[idx[name]]
   tpose.append(shortest(vtarget,vsrc)*gt[i])
  else:
   tpose.append((tpose[par]*gt[par].inv()*gt[i]) if par>=0 else gt[i])
 def add(arr,typ):
  while len(data)%4:data.append(0)
  a=np.asarray(arr,dtype='<f4');off=len(data);data.extend(a.tobytes());vi=len(g.bufferViews);g.bufferViews.append(BufferView(buffer=0,byteOffset=off,byteLength=a.nbytes));ai=len(g.accessors);g.accessors.append(Accessor(bufferView=vi,componentType=5126,count=a.shape[0],type=typ,min=[float(a.min())] if typ=='SCALAR' else [],max=[float(a.max())] if typ=='SCALAR' else []));return ai
 for title,filename in scope['clips'].items():
  dur,read,rt=curves(filename);times=np.linspace(0,dur,max(2,round(dur*30)+1)); values={i:[] for i,n in enumerate(g.nodes) if n.name in idx and i!=0};
  for t in times:
   sg=[]
   for j,n in enumerate(nodes):
    name=names[j]; r=refrots[j];k=n['m_AxesId']
    if name in mp and k>=0:
     a=sk['m_AxesArray'][k]; m=np.array([read(z,t) for z in mp[name]]);lo=np.array([a['m_Limit']['m_Min'][z] for z in 'xyz']);hi=np.array([a['m_Limit']['m_Max'][z] for z in 'xyz']);sign=np.array([a['m_Sgn'][z] for z in 'xyz']);ang=np.where(m>=0,m*hi,(-m)*lo)*sign
     pre=R.from_quat([a['m_PreQ'][z] for z in 'xyzw']);post=R.from_quat([a['m_PostQ'][z] for z in 'xyzw']);swing=R.from_rotvec([0,ang[1],ang[2]]);twist=R.from_rotvec([ang[0],0,0]); quat=(pre*swing*twist*post.inv()).as_quat();quat[1:3]*=-1;r=R.from_quat(quat)
    p=n['m_ParentId'];sg.append((sg[p] if p>=0 else R.identity())*r)
   tg=[]
   for i,n in enumerate(g.nodes):
    p=parents.get(i,-1); gp=tg[p] if p>=0 else R.identity();
    if i in values:
     j=idx[n.name]; glob=sg[j]*refg[j].inv()*tpose[i]; local=gp.inv()*glob; q=local.as_quat()
     if values[i] and np.dot(values[i][-1],q)<0:q=-q
     values[i].append(q);tg.append(glob)
    else:
     r=R.from_quat(n.rotation or [0,0,0,1]);tg.append(gp*r)
  ta=add(times,'SCALAR'); samplers=[];channels=[]
  for i,out in values.items():
   ac=add(out,'VEC4');si=len(samplers);samplers.append(AnimationSampler(input=ta,output=ac,interpolation='LINEAR'));channels.append(AnimationChannel(sampler=si,target=AnimationChannelTarget(node=i,path='rotation')))
  if title in ('crouch_idle','crouch_walk'):
   b=np.array(g.nodes[0].translation); vec=[b+np.array([0,rt(8,t)-0.94,0]) for t in times];ac=add(vec,'VEC3');si=len(samplers);samplers.append(AnimationSampler(input=ta,output=ac,interpolation='LINEAR'));channels.append(AnimationChannel(sampler=si,target=AnimationChannelTarget(node=0,path='translation')))
  g.animations.append(Animation(name=title,samplers=samplers,channels=channels));print(file,title,len(channels))
 while len(data)%4:data.append(0)
 g.buffers[0].byteLength=len(data);g.set_binary_blob(bytes(data));g.save_binary(os.path.join(root,file))
for f in ['player.glb','legs.glb']:convert(f)
