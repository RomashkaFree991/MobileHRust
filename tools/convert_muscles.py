import os,json,struct,math
import numpy as np
from scipy.spatial.transform import Rotation as R
from pygltflib import GLTF2, BufferView, Accessor, Animation, AnimationChannel, AnimationSampler, AnimationChannelTarget
base=os.path.dirname(os.path.dirname(os.path.abspath(__file__))); root=os.path.join(base,'assets/character/') ; clipdir=os.path.join(base,'tools/unity_clips')
d=json.load(open(os.path.join(clipdir,'avatar.json'))); s=d['m_Avatar']['m_Human']['data']['m_Skeleton']['data']; tos=dict(d['m_TOS']); axes={}
for i,node in enumerate(s['m_Node']):
 name=tos.get(s['m_ID'][i],'').split('/')[-1]; j=node['m_AxesId']
 if name and j>=0: axes[name]=s['m_AxesArray'][j]
src_global=[]; src_name={}
for i,node in enumerate(s['m_Node']):
 q=d['m_Avatar']['m_Human']['data']['m_SkeletonPose']['data']['m_X'][i]['q']; r=R.from_quat([q['x'],-q['y'],-q['z'],q['w']]); parent=node['m_ParentId']; src_global.append(src_global[parent]*r if parent>=0 else r); src_name[tos.get(s['m_ID'][i],'').split('/')[-1]]=i
# order x twist, y swing, z swing (muscle index within 55)
mp={'spine1':(2,1,0),'spine3':(5,4,3),'neck':(11,10,9),'head':(14,13,12),
'l_hip':(23,22,21),'l_knee':(25,None,24),'l_foot':(27,None,26),'l_toe':(None,None,28),
'r_hip':(31,30,29),'r_knee':(33,None,32),'r_foot':(35,None,34),'r_toe':(None,None,36),
'l_clavicle':(None,38,37),'l_upperarm':(41,40,39),'l_forearm':(43,None,42),'l_hand':(None,45,44),
'r_clavicle':(None,47,46),'r_upperarm':(50,49,48),'r_forearm':(52,None,51),'r_hand':(None,54,53)}
clips={'idle':'idle','walk':'walk','run':'run','crouch_idle':'crouch_idle','crouch_walk':'crouchwalk','jump':'jump','preview':'preview'}
def curves(name):
 x=json.load(open(os.path.join(clipdir,name+'.json'))); c=x['m_MuscleClip']['m_Clip']['data']; stream=c['m_StreamedClip']; dense=c['m_DenseClip']; const=c['m_ConstantClip']['data']; raw=struct.pack('<%dI'%len(stream['data']),*stream['data']); pos=0; keys={}
 while pos<len(raw):
  t,n=struct.unpack_from('<fi',raw,pos); pos+=8
  for _ in range(n):
   idx,a,b,cc,val=struct.unpack_from('<iffff',raw,pos);pos+=20
   if -1e5<t<1e5: keys.setdefault(idx,[]).append((t,val,a,b,cc))
 def sample(idx,t):
  ns=stream['curveCount']; nd=dense['m_CurveCount']
  if idx<ns:
   k=keys.get(idx,[])
   if not k:return 0.
   i=max(0,min(len(k)-1,np.searchsorted([z[0] for z in k],t,side='right')-1)); tm,v,a,b,cc=k[i]; dt=max(0,t-tm)
   return ((a*dt+b)*dt+cc)*dt+v
  if idx<ns+nd:
   col=idx-ns; f=(t-dense['m_BeginTime'])*dense['m_SampleRate']; i=max(0,min(dense['m_FrameCount']-1,int(f))); j=min(i+1,dense['m_FrameCount']-1); alpha=max(0,min(1,f-i)); arr=dense['m_SampleArray'];return arr[i*nd+col]*(1-alpha)+arr[j*nd+col]*alpha
  return const[idx-ns-nd]
 attr={};off=0
 for b in x['m_ClipBindingConstant']['genericBindings']:
  if b['typeID']==95 and b['customType']==8: attr[b['attribute']]=off
  off+= (3 if b['attribute'] in (1,3,4) else 4 if b['attribute']==2 else 1) if b['typeID']==4 else 1
 if off != stream['curveCount']+dense['m_CurveCount']+len(const):print('COUNTS MISMATCH',name,off,stream['curveCount']+dense['m_CurveCount']+len(const))
 return x['m_MuscleClip']['m_StopTime'], lambda i,t: sample(attr[i+42],t) if i is not None and i+42 in attr else 0., lambda attrid,t: sample(attr[attrid],t) if attrid in attr else 0.

def write(file):
 g=GLTF2().load(root+file); data=bytearray(g.binary_blob()); names={n.name:i for i,n in enumerate(g.nodes)}; g.animations=[]
 parents={child:i for i,node in enumerate(g.nodes) for child in (node.children or [])}
 def global_rot(i):
  r=R.from_quat(g.nodes[i].rotation or [0,0,0,1]); return global_rot(parents[i])*r if i in parents else r
 def add(arr,type):
  while len(data)%4:data.append(0)
  a=np.asarray(arr,dtype='<f4'); off=len(data); data.extend(a.tobytes()); view=len(g.bufferViews);g.bufferViews.append(BufferView(buffer=0,byteOffset=off,byteLength=a.nbytes)); acc=len(g.accessors); g.accessors.append(Accessor(bufferView=view,componentType=5126,count=a.shape[0],type=type,min=[float(a.min())] if type=='SCALAR' else [],max=[float(a.max())] if type=='SCALAR' else []));return acc
 for title,filename in clips.items():
  dur,read,rt=curves(filename); times=np.linspace(0,dur,max(2,round(dur*30)+1)); samp=[]; channels=[]; ta=add(times,'SCALAR')
  for bone,mi in mp.items():
   if bone not in names or bone not in axes:continue
   ax=axes[bone]; align=global_rot(names[bone]).inv()*src_global[src_name[bone]]; post=R.from_quat([ax['m_PostQ'][k] for k in 'xyzw']); rest=R.from_quat(g.nodes[names[bone]].rotation or [0,0,0,1]); sign=np.array([ax['m_Sgn'][k] for k in 'xyz']); lo=np.array([ax['m_Limit']['m_Min'][k] for k in 'xyz']); hi=np.array([ax['m_Limit']['m_Max'][k] for k in 'xyz']); out=[]
   for t in times:
    m=np.array([read(i,t) for i in mi]); angles=np.where(m>=0,m*hi,(-m)*lo)*sign
    swing=R.from_rotvec([0,angles[1],angles[2]]); twist=R.from_rotvec([angles[0],0,0]); delta=(post*swing*twist*post.inv()).as_quat(); delta[1:3]*=-1
    q=(rest*align*R.from_quat(delta)*align.inv()).as_quat()
    if out and np.dot(out[-1],q)<0:q=-q
    out.append(q)
   a=add(out,'VEC4'); si=len(samp);samp.append(AnimationSampler(input=ta,output=a,interpolation='LINEAR'));channels.append(AnimationChannel(sampler=si,target=AnimationChannelTarget(node=names[bone],path='rotation')))
  if title in ('crouch_idle','crouch_walk') and 'pelvis' in names:
   base=np.array(g.nodes[names['pelvis']].translation); vec=[base+np.array([0,rt(8,t)-0.94,0]) for t in times]; a=add(vec,'VEC3'); si=len(samp); samp.append(AnimationSampler(input=ta,output=a,interpolation='LINEAR')); channels.append(AnimationChannel(sampler=si,target=AnimationChannelTarget(node=names['pelvis'],path='translation')))
  g.animations.append(Animation(name=title,samplers=samp,channels=channels));print(file,title,'duration',round(dur,2),'bones',len(channels),'rootY',round(rt(8,0),3))
 while len(data)%4:data.append(0)
 g.buffers[0].byteLength=len(data);g.set_binary_blob(bytes(data));g.save_binary(root+file)
for f in ['player.glb','legs.glb']:write(f)
