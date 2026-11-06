#!/usr/bin/env python3
"""Verify private media on the owned local Supabase stack using synthetic bytes only."""
import argparse,json,secrets,subprocess,urllib.request,urllib.error,uuid
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
p=argparse.ArgumentParser();p.add_argument('--local-status',type=Path,required=True);p.add_argument('--output',type=Path,required=True);args=p.parse_args()
cfg=json.loads(args.local_status.read_text());base=cfg['API_URL'];assert base=='http://127.0.0.1:55321'
checks=[]
def check(name,ok):
 if not ok:raise AssertionError(name)
 checks.append({'check':name,'status':'PASS'})
def http(path,body=None,token=None,method=None,raw=None,mime='application/json'):
 if body is not None:raw=json.dumps(body).encode()
 url=path if path.startswith(base+'/') else base+path
 assert url.startswith(base+'/')
 req=urllib.request.Request(url,data=raw,method=method,headers={'apikey':cfg['ANON_KEY'],'Authorization':'Bearer '+(token or cfg['ANON_KEY']),'Content-Type':mime,'Cache-Control':'no-cache'})
 try:
  with urllib.request.urlopen(req,timeout=20) as r:code,data=r.status,r.read()
 except urllib.error.HTTPError as e:code,data=e.code,e.read()
 try:return code,json.loads(data)
 except:return code,data
def api(path,body=None,method=None):
 code,data=http(path,body,cfg['SERVICE_ROLE_KEY'],method);check('local setup '+path.split('?')[0],200<=code<300);return data
started=datetime.now(ZoneInfo('America/New_York')).isoformat()
users=[];password=secrets.token_urlsafe(24)
for _ in range(2):
 email='restoration-private-'+str(uuid.uuid4())+'@example.invalid'
 api('/auth/v1/admin/users',{'email':email,'password':password,'email_confirm':True})
 code,session=http('/auth/v1/token?grant_type=password',{'email':email,'password':password});assert code==200;users.append(session)
a,b=users
for name,mime in [('creative-works','image/png'),('generated-audio','audio/mpeg')]:
 code,_=http('/storage/v1/bucket',{'id':name,'name':name,'public':True,'file_size_limit':52428800,'allowed_mime_types':[mime]},cfg['SERVICE_ROLE_KEY'])
 assert code in (200,201,400,409)
 bucket=api('/storage/v1/bucket/'+name);assert bucket['public'] is True,'Before phase requires original public bucket state'
path=a['user']['id'].upper()+'/voice-journals/fixture.m4a'
code,_=http('/storage/v1/object/creative-works/'+path,token=cfg['SERVICE_ROLE_KEY'],raw=b'synthetic-audio',mime='audio/m4a')
check('before: original MIME list rejects voice journal audio',code==400)
for bucket,mime,extension in [('creative-works','image/png','png'),('generated-audio','audio/mpeg','mp3')]:
 object_path=a['user']['id'].upper()+'/fixture.'+extension
 code,_=http('/storage/v1/object/'+bucket+'/'+object_path,token=cfg['SERVICE_ROLE_KEY'],raw=b'synthetic-private-fixture',mime=mime)
 check('before: seed '+bucket,code in (200,201))
 code,_=http('/storage/v1/object/public/'+bucket+'/'+object_path)
 check('before: anonymous public URL exposes synthetic '+bucket,code==200)
for source in ['supabase/migrations/20261023082638_normalize_storage_owner_uuid.sql','supabase/operations/20261022_private_media.sql']:
 result=subprocess.run(['docker','exec','-i','supabase_db_mindfriend-restoration-local','psql','-U','postgres','-v','ON_ERROR_STOP=1'],input=Path(source).read_text(),text=True,capture_output=True)
 if result.returncode:raise RuntimeError('Local policy apply failed: '+result.stderr)
code,_=http('/storage/v1/object/creative-works/'+path,token=a['access_token'],raw=b'synthetic-audio',mime='audio/m4a')
check('after: owner uppercase UUID voice upload accepted',code in (200,201))
code,_=http('/storage/v1/object/creative-works/'+b['user']['id'].upper()+'/forged.m4a',token=a['access_token'],raw=b'synthetic-audio',mime='audio/m4a')
check('after: cross-user voice upload denied',code>=400)
for bucket,extension in [('creative-works','png'),('generated-audio','mp3')]:
 object_path=a['user']['id'].upper()+'/fixture.'+extension
 code,_=http('/storage/v1/object/public/'+bucket+'/'+object_path)
 check('after: anonymous public URL denied '+bucket,code>=400)
 code,link=http('/storage/v1/object/sign/'+bucket+'/'+object_path,{'expiresIn':3600},a['access_token'])
 check('after: owner signs '+bucket,code==200 and bool(link.get('signedURL')))
 signed=base+'/storage/v1'+link['signedURL']
 code,data=http(signed)
 check('after: explicitly issued bearer link downloads '+bucket,code==200 and data==b'synthetic-private-fixture')
 code,_=http('/storage/v1/object/sign/'+bucket+'/'+object_path,{'expiresIn':3600},b['access_token'])
 check('after: cross-user cannot sign '+bucket,code>=400)
 code,_=http('/storage/v1/object/sign/'+bucket+'/'+object_path,{'expiresIn':3600})
 check('after: anonymous cannot sign '+bucket,code>=400)
 code,data=http('/storage/v1/object/list/'+bucket,{'prefix':a['user']['id'].upper(),'limit':10},b['access_token'])
 check('after: cross-user object listing empty '+bucket,code==200 and data==[])
# Existing photo service also uses uppercase UUID prefixes.
api('/storage/v1/bucket/mood-photos',{'public':False,'file_size_limit':5242880,'allowed_mime_types':['image/jpeg','image/png']},method='PUT')
photo=a['user']['id'].upper()+'/synthetic.jpg'
code,_=http('/storage/v1/object/mood-photos/'+photo,token=a['access_token'],raw=b'synthetic-photo',mime='image/jpeg')
check('after: existing mood photo uppercase UUID upload accepted',code in (200,201))
code,_=http('/storage/v1/object/sign/mood-photos/'+photo,{'expiresIn':60},b['access_token'])
check('after: cross-user mood photo denied',code>=400)
args.output.write_text(json.dumps({'environment':'synthetic local stack','started_eastern':started,'finished_eastern':datetime.now(ZoneInfo('America/New_York')).isoformat(),'checks':checks,'provider_calls':0,'real_audio_or_images':False},indent=2)+'\n')
print('PASS:',len(checks),'local private-media assertions; synthetic bytes, zero provider calls')
