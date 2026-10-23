import subprocess as s,pathlib,sys,json,time,os
base=pathlib.Path(__file__).parent; image=sys.argv[1]; label=sys.argv[2]; w=base/'evidence'/label/'tls-upstream';w.mkdir(parents=True,exist_ok=True)
def run(a,**kw):return s.check_output(a,text=True,**kw).strip()
def openssl(*a):s.run(['openssl',*a],cwd=w,check=True,stdout=s.DEVNULL,stderr=s.DEVNULL)
openssl('req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=Wolfi Test Root','-keyout','root.key','-out','root.pem')
openssl('req','-newkey','rsa:2048','-nodes','-subj','/CN=upstream','-keyout','server.key','-out','server.csr')
(w/'ext').write_text('subjectAltName=DNS:upstream\nextendedKeyUsage=serverAuth\n')
openssl('x509','-req','-in','server.csr','-CA','root.pem','-CAkey','root.key','-CAcreateserial','-days','1','-extfile','ext','-out','server.pem')
for p in w.iterdir():p.chmod(0o644)
(w/'config.yml').write_text('''_format_version: "3.0"
services:
- name: good
  url: https://upstream:8443
  tls_verify: true
  routes:
  - paths: [/good]
- name: wrong-host
  url: https://wronghost:8443
  tls_verify: true
  routes:
  - paths: [/wrong-host]
- name: untrusted
  url: https://upstream:9443
  tls_verify: true
  routes:
  - paths: [/untrusted]
''')
cfg=(w/'config.yml').read_text().replace('  tls_verify: true', '  tls_verify: true\n  ca_certificates: [11111111-1111-4111-8111-111111111111]')
cfg+='ca_certificates:\n- id: 11111111-1111-4111-8111-111111111111\n  cert: |\n'+''.join('    '+line+'\n' for line in (w/'root.pem').read_text().splitlines())
(w/'config.yml').write_text(cfg)
server='''import ssl,threading,time
from http.server import BaseHTTPRequestHandler,HTTPServer
class H(BaseHTTPRequestHandler):
 def do_GET(self):
  b=b'tls-upstream-ok';self.send_response(200);self.send_header('Content-Length',str(len(b)));self.end_headers();self.wfile.write(b)
for port,cert,key in [(8443,'server.pem','server.key'),(9443,'root.pem','root.key')]:
 h=HTTPServer(('0.0.0.0',port),H);ctx=ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER);ctx.load_cert_chain('/config/'+cert,'/config/'+key);h.socket=ctx.wrap_socket(h.socket,server_side=True);threading.Thread(target=h.serve_forever,daemon=True).start()
time.sleep(180)
'''
# An independent untrusted certificate is essential: generate a separate self-signed root for 9443.
openssl('req','-x509','-newkey','rsa:2048','-nodes','-days','1','-subj','/CN=upstream','-addext','subjectAltName=DNS:upstream','-keyout','untrusted.key','-out','untrusted.pem')
server=server.replace("(9443,'root.pem','root.key')","(9443,'untrusted.pem','untrusted.key')")
net='kkwolfi-tls-'+label;up=net+'-up';gw=net+'-gw'
try:
 run(['docker','network','create','--internal',net])
 run(['docker','run','-d','--name',up,'--network',net,'--network-alias','upstream','--network-alias','wronghost','--cpus=1','--memory=256m','-v',str(w)+':/config:ro','--entrypoint','python3','litellm:v1.106.2-sec20261023b','-u','-c',server])
 run(['docker','run','-d','--name',gw,'--network',net,'--network-alias','gateway','--cpus=2','--memory=1g','--ulimit','nofile=4096:4096','-v',str(w)+':/config:ro','-e','KONG_DECLARATIVE_CONFIG=/config/config.yml','-e','KONG_LUA_SSL_TRUSTED_CERTIFICATE=/config/root.pem','-e','KONG_ADMIN_LISTEN=0.0.0.0:8001','-e','KONG_NGINX_WORKER_PROCESSES=1',image])
 test='''import urllib.request,urllib.error,time,json
for i in range(60):
 try: urllib.request.urlopen('http://gateway:8001/status',timeout=2);break
 except Exception: time.sleep(1)
results={}
for path,expected in [('good',200),('wrong-host',502),('untrusted',502)]:
 try:
  r=urllib.request.urlopen('http://gateway:8000/'+path,timeout=15);code=r.status;body=r.read()
 except urllib.error.HTTPError as e:code=e.code;body=e.read()
 assert code==expected,(path,code,body)
 if expected==200:assert body==b'tls-upstream-ok'
 results[path]=code
print(json.dumps(results))
'''
 result=run(['docker','exec','-i',up,'python3','-c',test]);(w/'result.json').write_text(result);print(result)
finally:
 for name in [gw,up]:
  with (w/(name+'.log')).open('w') as f:s.run(['docker','logs',name],stdout=f,stderr=s.STDOUT)
  s.run(['docker','rm','-f',name],stdout=s.DEVNULL,stderr=s.DEVNULL)
 s.run(['docker','network','rm',net],stdout=s.DEVNULL,stderr=s.DEVNULL)
 for p in w.glob('*.key'):p.unlink()
 for p in w.glob('*.csr'):p.unlink()
