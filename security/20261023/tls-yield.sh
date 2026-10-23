#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
image=${1:-kkong:3.10.0-sec20261023}
work="$PWD/.work/tls-yield"
mkdir -p "$work"
openssl req -x509 -newkey rsa:2048 -nodes -days 1 -subj /CN=exact.example.test \
  -keyout "$work/key.pem" -out "$work/cert.pem" > "$work/certificate.log" 2>&1
chmod 644 "$work/key.pem"
cat > "$work/nginx.conf" <<'NGINX'
worker_processes 1;
pid /tmp/tls-yield.pid;
error_log stderr notice;
events { worker_connections 64; }
http {
  access_log off;
  server {
    listen 8443 ssl;
    ssl_certificate /config/cert.pem;
    ssl_certificate_key /config/key.pem;
    ssl_certificate_by_lua_block { ngx.sleep(0.02) }
    location / { return 200 "tls-yield-ok\n"; }
  }
}
NGINX
name="kkong-tls-yield-$$"
cleanup() {
  docker logs "$name" > "$work/container.log" 2>&1 || true
  docker rm -f "$name" >/dev/null 2>&1 || true
}
trap cleanup EXIT
docker run -d --name "$name" --network none --cpus=1 --memory=256m \
  -v "$work:/config:ro" --entrypoint nginx "$image" -p /tmp/ -c /config/nginx.conf -g 'daemon off;' >/dev/null
docker run --rm -i --network "container:$name" kkong-builder:sec20261023 python3 - <<'PY'
import ssl,socket,time
ctx=ssl._create_unverified_context()
for attempt in range(30):
 try:
  with socket.create_connection(('127.0.0.1',8443),timeout=3) as s:
   with ctx.wrap_socket(s,server_hostname='exact.example.test') as tls:
    tls.sendall(b'GET / HTTP/1.0\r\nHost: exact.example.test\r\n\r\n');data=b''
    while True:
     chunk=tls.recv(4096)
     if not chunk:break
     data+=chunk
    assert b'200 OK' in data and data.endswith(b'tls-yield-ok\n'),data
 except ConnectionRefusedError:
  time.sleep(0.1);continue
 break
else:raise AssertionError('TLS server did not become ready')
for i in range(20):
 with socket.create_connection(('127.0.0.1',8443),timeout=3) as s:
  with ctx.wrap_socket(s,server_hostname='exact.example.test') as tls:
   tls.sendall(b'GET / HTTP/1.0\r\nHost: exact.example.test\r\n\r\n');data=b''
   while True:
    chunk=tls.recv(4096)
    if not chunk:break
    data+=chunk
   assert b'200 OK' in data and data.endswith(b'tls-yield-ok\n'),data
print('PASS: 21 TLS handshakes with ssl_certificate_by_lua ngx.sleep yield and HTTP response')
PY
