import subprocess as sp,tarfile,hashlib,json,re,pathlib
out=pathlib.Path(__file__).parent/'evidence'; results={}
for label,image in [('b','kkong:3.10.0-sec20261023b'),('c','kkong:3.10.0-sec20261023c-wolfi')]:
 cid=sp.check_output(['docker','create',image],text=True).strip(); p=sp.Popen(['docker','export',cid],stdout=sp.PIPE)
 payload={};bundles=[];bad=[];packages=[]
 try:
  with tarfile.open(fileobj=p.stdout,mode='r|') as tf:
   for m in tf:
    if not m.isfile():continue
    check=m.name.startswith(('etc/ssl/','etc/pki/','usr/share/ca-certificates/')) or m.name.endswith('cacert.pem')
    if not (m.name.startswith('usr/local/') or check or (m.name.endswith('/apk/db/installed') or m.name=='var/lib/dpkg/status')):continue
    data=tf.extractfile(m).read()
    if m.name.startswith('usr/local/'):payload[m.name]=hashlib.sha256(data).hexdigest()
    if (m.name.endswith('/apk/db/installed') or m.name=='var/lib/dpkg/status'):
     (out/('packages-'+label+'.txt')).write_bytes(data)
     if label=='c':packages=re.findall(rb'^P:(.+)$',data,re.M)
     else:packages=[x for x in data.split(b'\n\n') if b'Status: install ok installed' in x]
    if check:
     certs=re.findall(rb'-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----',data,re.S)
     if certs or m.name.endswith('cacert.pem'):
      bundles.append({'path':m.name,'certificates':len(certs),'sha256':hashlib.sha256(data).hexdigest()})
      for cert in certs:
       subject=sp.check_output(['openssl','x509','-noout','-subject'],input=cert).decode().strip()
       if 'emSign ECC Root CA - C3' in subject or 'emSign Root CA - C1' in subject:bad.append({'path':m.name,'subject':subject})
  assert p.wait()==0
 finally:
  p.stdout.close();sp.run(['docker','rm',cid],stdout=sp.DEVNULL)
 assert not [x for x in bad if not (label=='b' and x['path'].startswith('usr/share/ca-certificates/'))],bad
 info=json.loads(sp.check_output(['docker','image','inspect',image]))[0]
 results[label]={'image':image,'id':info['Id'],'size_bytes':info['Size'],'os_package_count':len(packages),'ca_files':bundles,'forbidden_active_ca_count':0,'inactive_source_certificates':bad,'payload_files':len(payload)}
 (out/('payload-'+label+'.json')).write_text(json.dumps(payload,indent=2))
 if label=='b':original=payload
 else:assert original==payload,'Kong payload changed'
results['payload_identical']=True
(out/'audit.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))
