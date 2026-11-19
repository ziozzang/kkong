#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
image=${1:-kkong:3.10.0-sec20261023}
work="$PWD/.work/smoke"
mkdir -p "$work"
name="kkong-smoke-$$"
upstream="$name-upstream"
network="$name-net"
cleanup() {
  docker logs "$name" > "$work/container.log" 2>&1 || true
  docker rm -f "$name" "$upstream" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
}
trap cleanup EXIT
cat > "$work/declarative.yml" <<'YAML'
_format_version: "3.0"
services:
- name: smoke-upstream
  url: http://upstream:8080
  routes:
  - name: smoke-route
    paths: ["/smoke"]
    strip_path: true
YAML
docker network create --internal "$network" >/dev/null
docker run -d --name "$upstream" --network "$network" --network-alias upstream \
  kkong-builder:sec20261023 python3 -u -c 'from http.server import BaseHTTPRequestHandler,HTTPServer
class H(BaseHTTPRequestHandler):
 def do_GET(self):
  body=b"kkong-upstream-ok\n";self.send_response(200);self.send_header("Content-Length",str(len(body)));self.end_headers();self.wfile.write(body)
 def do_POST(self):
  body=self.rfile.read(int(self.headers.get("Content-Length",0)));self.send_response(200);self.send_header("Content-Length",str(len(body)));self.end_headers();self.wfile.write(body)
HTTPServer(("0.0.0.0",8080),H).serve_forever()' >/dev/null
docker run -d --name "$name" --network "$network" --network-alias gateway --ulimit nofile=4096:4096 --cpus=2 --memory=1g \
  -v "$work/declarative.yml:/config/declarative.yml:ro" \
  -e KONG_DATABASE=off -e KONG_DECLARATIVE_CONFIG=/config/declarative.yml \
  -e KONG_ADMIN_LISTEN=0.0.0.0:8001 -e KONG_ADMIN_GUI_LISTEN=off \
  -e KONG_ANONYMOUS_REPORTS=off -e KONG_NGINX_WORKER_PROCESSES=1 "$image" >/dev/null
docker exec -i "$upstream" python3 - > "$work/result.json" <<'PYTEST'
import urllib.request,json,time,http.client
for attempt in range(60):
 try:
  status=json.load(urllib.request.urlopen("http://gateway:8001/status",timeout=2));break
 except Exception:
  if attempt==59:raise
  time.sleep(1)
admin=json.load(urllib.request.urlopen("http://gateway:8001/"))
routes=json.load(urllib.request.urlopen("http://gateway:8001/routes"))
assert admin['version']=='3.10.0'
assert any(x['name']=='smoke-route' for x in routes['data'])
c=http.client.HTTPConnection('gateway',8000,timeout=10)
c.request('GET','/smoke');r=c.getresponse();assert r.status==200;assert r.read()==b'kkong-upstream-ok\n'
c.request('POST','/smoke',body=b'body-must-survive',headers={'Connection':'content-length'})
r=c.getresponse();assert r.status==200;assert r.read()==b'body-must-survive'
c.request('GET','/no-such-route');r=c.getresponse();assert r.status==404;r.read();c.close()
print(json.dumps({'passed':True,'version':admin['version'],'status':status,'routes':routes,'checks':['dbless boot','Admin API','route GET','hop-by-hop Content-Length POST','404']},indent=2))
PYTEST
docker exec "$name" kong health
docker exec "$name" nginx -V > "$work/runtime-version.txt" 2>&1
docker logs "$name" > "$work/container.log" 2>&1
echo 'PASS: DB-less boot, Admin API/status/routes, upstream GET and POST, Connection: content-length regression, unmatched route 404, kong health'
