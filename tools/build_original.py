import os,json,math
import numpy as np
from scipy.spatial.transform import Rotation as R
from pygltflib import *
base=os.path.dirname(os.path.dirname(os.path.abspath(__file__))); root=os.path.join(base,'assets/character'); clipdir=os.path.join(base,'tools/unity_clips')
d=json.load(open(os.path.join(clipdir,'avatar.json')));a=d['m_Avatar'];s=a['m_AvatarSkeleton']['data'];pose=a['m_DefaultPose']['data']['m_X'];human=a['m_Human']['data']['m_Skeleton']['data'];hnames={dict(d['m_TOS']).get(i,'').split('/')[-1]:j for j,i in enumerate(human['m_ID'])};tos=dict(d['m_TOS']); names=[tos.get(v,'').split('/')[-1] or 'Root' for v in s['m_ID']]; ids={n:i for i,n in enumerate(names)}
partsdir=os.path.join(base,'tools/source_parts');meta=json.load(open(os.path.join(partsdir,'parts_metadata.json')))
def qmir(v):return [v['x'],-v['y'],-v['z'],v['w']]
def vv(v):return np.array([-v['x'],v['y'],v['z']])
# Source skeleton default reference, expressed in Godot coordinates.
ref=[];nodes=[]
for i,n in enumerate(s['m_Node']):
 q=R.from_quat(qmir(pose[i]['q']));t=vv(pose[i]['t']);mat=np.eye(4);mat[:3,:3]=q.as_matrix();mat[:3,3]=t;p=n['m_ParentId'];ref.append(ref[p]@mat if p>=0 else mat);children=[j for j,x in enumerate(s['m_Node']) if x['m_ParentId']==i];nodes.append(Node(name=names[i],translation=t.tolist(),rotation=q.as_quat().tolist(),children=children or None))
# Load curve reader / muscle mapping from previous investigation.
source=open(os.path.join(base,'tools/convert_muscles.py')).read().split("for f in ['player.glb'")[0];scope={'__file__':os.path.join(base,'tools/convert_muscles.py')};exec(compile(source,'curve_reader','exec'),scope); curves=scope['curves']; mp=scope['mp'];clips=scope['clips'].copy()
for prefix in ('walk_', 'crouch_', 'jump_'):
 for filename in os.listdir(clipdir):
  if filename.startswith(prefix) and filename.endswith('.json'):
   name=filename[:-5]; clips[name]=name
# Unity matrices to Godot matrices via reflection.
H=np.diag([-1.,1,1,1]);
for legs_only in [False,True]:
 g=GLTF2(asset=Asset(version='2.0',generator='Rust original modular model'));g.nodes=[Node(**node.to_dict()) for node in nodes];blob=bytearray();g.bufferViews=[];g.accessors=[]
 def add(arr,component,typ,target=None,bounds=False):
  while len(blob)%4:blob.append(0)
  arr=np.ascontiguousarray(arr);offset=len(blob);blob.extend(arr.tobytes());i=len(g.bufferViews);g.bufferViews.append(BufferView(buffer=0,byteOffset=offset,byteLength=arr.nbytes,target=target));n=len(g.accessors);ac=Accessor(bufferView=i,componentType=component,count=arr.shape[0],type=typ)
  if bounds:ac.min=np.atleast_1d(arr.min(0)).tolist();ac.max=np.atleast_1d(arr.max(0)).tolist()
  g.accessors.append(ac);return n
 def source_image(filename):
  dat=open(os.path.join(root,filename),'rb').read()
  while len(blob)%4:blob.append(0)
  off=len(blob);blob.extend(dat);vi=len(g.bufferViews);g.bufferViews.append(BufferView(buffer=0,byteOffset=off,byteLength=len(dat)));return Image(bufferView=vi,mimeType='image/jpeg')
 g.images=[source_image(n) for n in ('body_original.jpg','head_original.jpg','underwear_original.jpg')];g.textures=[Texture(source=i) for i in range(3)];g.materials=[Material(name='Original Rust body',pbrMetallicRoughness=PbrMetallicRoughness(baseColorTexture=TextureInfo(index=0),baseColorFactor=[0.9326,0.8509,0.8333,1],metallicFactor=0,roughnessFactor=.9)),Material(name='Original Rust head',pbrMetallicRoughness=PbrMetallicRoughness(baseColorTexture=TextureInfo(index=1),baseColorFactor=[0.9326,0.8509,0.8333,1],metallicFactor=0,roughnessFactor=.9)),Material(name='Original Rust underwear',pbrMetallicRoughness=PbrMetallicRoughness(baseColorTexture=TextureInfo(index=2),metallicFactor=0,roughnessFactor=.95),doubleSided=True)]
 g.skins=[Skin(joints=list(range(len(nodes))),inverseBindMatrices=add(np.array([np.linalg.inv(m).T.flatten() for m in ref],dtype='<f4'),5126,'MAT4'),skeleton=0)]
 parts=[('-7060186683444779785',0),('-7370544997436328256',0),('7997367388466599223',2)]
 if not legs_only:parts += [('1542740195783385851',0),('2900878314152527974',0),('6608249783596678305',1)]
 for code,mat in parts:
  data=np.load(os.path.join(partsdir,'part_'+code+'.npz'));info=meta[code];bones=info['bones'];mi=next(i for i,b in enumerate(bones) if b in ids); source_global=H@ref[ids[bones[mi]]]@H;M=source_global@data['bind'][mi]; trans=H@M@H
  p=np.array(data['verts'],dtype='f4');p[:,0]*=-1;p=(p@trans[:3,:3].T+trans[:3,3]).astype('f4')
  no=np.nan_to_num(data['normal']).astype('f4');no[:,0]*=-1;no=(no@trans[:3,:3].T).astype('f4')
  uv=np.array(data['uv'],dtype='f4');
  if code in ('-7060186683444779785','-7370544997436328256','6608249783596678305','1542740195783385851','2900878314152527974','7997367388466599223'): uv[:,1]=1-uv[:,1] # Testing image origin per source part
  jointmap=np.array([ids.get(n,ids['head']) for n in bones],dtype='u2');ji=jointmap[np.array(data['joints'],dtype='i4')];weights=np.maximum(data['weights'],0).astype('f4'); ji=np.pad(ji,((0,0),(0,4-ji.shape[1]))); weights=np.pad(weights,((0,0),(0,4-weights.shape[1])));sums=weights.sum(1);sums[sums==0]=1;weights/=sums[:,None]
  tri=np.array(data['tri']).reshape(-1,3)[:,[0,2,1]].astype('u2').reshape(-1);attr=Attributes(POSITION=add(p,5126,'VEC3',34962,True),NORMAL=add(no,5126,'VEC3',34962),TEXCOORD_0=add(uv,5126,'VEC2',34962),JOINTS_0=add(ji,5123,'VEC4',34962),WEIGHTS_0=add(weights,5126,'VEC4',34962));ia=add(tri,5123,'SCALAR',34963)
  g.meshes.append(Mesh(name=info['name'],primitives=[Primitive(attributes=attr,indices=ia,material=mat)]));g.nodes.append(Node(name='Part_'+info['name'],mesh=len(g.meshes)-1,skin=0));print(legs_only,code,info['name'],len(p),'bbox',p.min(0),p.max(0))
 g.scenes=[Scene(nodes=[0]+list(range(len(nodes),len(g.nodes))))];g.scene=0
 # In Humanoid muscle space use actual avatar's pre/post axes to write local joint rotations.
 for title,filename in clips.items():
  dur,read,rt=curves(filename);times=np.linspace(0,dur,max(2,round(dur*30)+1));ta=add(np.array(times,dtype='f4'),5126,'SCALAR',bounds=True);samp=[];channel=[]
  # Retargeted humanoid baseline T pose is different from default bind A pose.
  humanpose=a['m_Human']['data']['m_SkeletonPose']['data']['m_X']
  for bone,i in ids.items():
   if bone not in hnames or i==0 or bone=='pelvis':continue
   j=hnames[bone];node=human['m_Node'][j];k=node['m_AxesId'];out=[]
   for t in times:
    if bone in mp and k>=0:
     ax=human['m_AxesArray'][k];m=np.array([read(z,t) for z in mp[bone]]);lo=np.array([ax['m_Limit']['m_Min'][z] for z in 'xyz']);hi=np.array([ax['m_Limit']['m_Max'][z] for z in 'xyz']);sign=np.array([ax['m_Sgn'][z] for z in 'xyz']);ang=np.where(m>=0,m*hi,(-m)*lo)*sign; pre=R.from_quat([ax['m_PreQ'][z] for z in 'xyzw']);post=R.from_quat([ax['m_PostQ'][z] for z in 'xyzw']);rot=(pre*R.from_rotvec([0,ang[1],ang[2]])*R.from_rotvec([ang[0],0,0])*post.inv()).as_quat();rot[1:3]*=-1
    else:rot=np.array(qmir(humanpose[j]['q']))
    if out and np.dot(out[-1],rot)<0:rot=-rot
    out.append(rot)
   ac=add(np.array(out,dtype='f4'),5126,'VEC4');si=len(samp);samp.append(AnimationSampler(input=ta,output=ac,interpolation='LINEAR'));channel.append(AnimationChannel(sampler=si,target=AnimationChannelTarget(node=i,path='rotation')))
  # Humanoid RootQ is body orientation in avatar coordinates. Preserve it;
  # horizontal root translation belongs to the gameplay controller instead.
  rr=[]
  for t in times:
   q=np.array([rt(10,t),-rt(11,t),-rt(12,t),rt(13,t)],dtype=float)
   q=q/np.linalg.norm(q) if np.linalg.norm(q)>0.01 else np.array([0.,0.,0.,1.])
   if rr and np.dot(rr[-1],q)<0:q=-q
   rr.append(q)
  ac=add(np.array(rr,dtype='f4'),5126,'VEC4');si=len(samp);samp.append(AnimationSampler(input=ta,output=ac,interpolation='LINEAR'));channel.append(AnimationChannel(sampler=si,target=AnimationChannelTarget(node=ids['pelvis'],path='rotation')))
  if not title.startswith('jump'):
   b=np.array(nodes[ids['pelvis']].translation);vec=np.array([b+np.array([0,rt(8,t)-0.94,0]) for t in times],dtype='f4');ac=add(vec,5126,'VEC3');si=len(samp);samp.append(AnimationSampler(input=ta,output=ac,interpolation='LINEAR'));channel.append(AnimationChannel(sampler=si,target=AnimationChannelTarget(node=ids['pelvis'],path='translation')))
  g.animations.append(Animation(name=title,samplers=samp,channels=channel))
 while len(blob)%4:blob.append(0)
 g.buffers=[Buffer(byteLength=len(blob))];g.set_binary_blob(bytes(blob));g.save_binary(os.path.join(root,'legs.glb' if legs_only else 'player.glb'))
