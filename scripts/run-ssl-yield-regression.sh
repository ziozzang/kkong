#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
UPSTREAM_PID=""
PG_CONTAINER="kkong-ssl-regression-pg"
OFF_PREFIX="$TMP_DIR/off-prefix"
PG_PREFIX="$TMP_DIR/postgres-prefix"

pick_port() {
  python3 - <<'PY'
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])
s.close()
PY
}

UPSTREAM_PORT="$(pick_port)"
OFF_PROXY_PORT="$(pick_port)"
OFF_ADMIN_PORT="$(pick_port)"
OFF_STATUS_PORT="$(pick_port)"
PG_PORT="$(pick_port)"
PG_PROXY_PORT="$(pick_port)"
PG_ADMIN_PORT="$(pick_port)"
PG_STATUS_PORT="$(pick_port)"

source_venv() {
  set +u
  . "$ROOT_DIR/bazel-bin/build/kong-dev-venv.sh"
  set -u
}

cleanup() {
  set +e
  if [ -f "$ROOT_DIR/bazel-bin/build/kong-dev-venv.sh" ]; then
    source_venv
    bin/kong stop -p "$OFF_PREFIX" >/dev/null 2>&1
    bin/kong stop -p "$PG_PREFIX" >/dev/null 2>&1
  fi
  if [ -n "$UPSTREAM_PID" ]; then
    kill "$UPSTREAM_PID" >/dev/null 2>&1
  fi
  docker rm -f "$PG_CONTAINER" >/dev/null 2>&1
  rm -rf "$TMP_DIR"
}

wait_for_http() {
  local url="$1"
  for _ in $(seq 1 60); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

wait_for_https_body() {
  local host="$1"
  local port="$2"
  local expected="$3"

  for _ in $(seq 1 30); do
    if curl --resolve "${host}:${port}:127.0.0.1" -ksS "https://${host}:${port}/" | grep -q "$expected"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

assert_subject() {
  local port="$1"
  local sni="$2"
  local expected="$3"
  local output

  output="$(echo 'GET /' | openssl s_client -connect "127.0.0.1:${port}" -servername "$sni" 2>/dev/null || true)"
  echo "$output" | grep -Fq "$expected"
  if echo "$output" | grep -Fq "unexpected eof while reading"; then
    echo "TLS handshake failed for ${sni}" >&2
    return 1
  fi
}

write_pem_block() {
  local cert_path="$1"
  local key_path="$2"

  printf '    cert: |\n'
  sed 's/^/      /' "$cert_path"
  printf '    key: |\n'
  sed 's/^/      /' "$key_path"
}

create_self_signed() {
  local cn="$1"
  local cert_path="$2"
  local key_path="$3"

  openssl req \
    -x509 \
    -nodes \
    -newkey rsa:2048 \
    -keyout "$key_path" \
    -out "$cert_path" \
    -days 2 \
    -subj "/CN=${cn}" >/dev/null 2>&1
}

post_json() {
  local url="$1"
  local payload="$2"
  python3 - "$url" "$payload" <<'PY'
import json
import sys
import urllib.request

url = sys.argv[1]
payload = json.dumps(json.loads(sys.argv[2])).encode()
req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
with urllib.request.urlopen(req) as resp:
    print(resp.status)
PY
}

start_upstream() {
  mkdir -p "$TMP_DIR/upstream"
  printf 'upstream-ok\n' > "$TMP_DIR/upstream/index.html"
  python3 -m http.server "$UPSTREAM_PORT" --bind 127.0.0.1 --directory "$TMP_DIR/upstream" >/dev/null 2>&1 &
  UPSTREAM_PID="$!"
  wait_for_http "http://127.0.0.1:${UPSTREAM_PORT}/"
}

run_off_mode() {
  local exact_cert="$TMP_DIR/exact.crt"
  local exact_key="$TMP_DIR/exact.key"
  local wildcard_cert="$TMP_DIR/wildcard.crt"
  local wildcard_key="$TMP_DIR/wildcard.key"
  local declarative="$TMP_DIR/kong-off.yml"
  local conf="$TMP_DIR/kong-off.conf"
  local exact_cert_id="11111111-1111-1111-1111-111111111111"
  local wildcard_cert_id="22222222-2222-2222-2222-222222222222"

  create_self_signed "exact.example.test" "$exact_cert" "$exact_key"
  create_self_signed "*.tls.example.test" "$wildcard_cert" "$wildcard_key"

  {
    cat <<EOF
_format_version: "3.0"
services:
  - name: exact-service
    url: http://127.0.0.1:${UPSTREAM_PORT}
    routes:
      - name: exact-route
        protocols:
          - https
        hosts:
          - exact.example.test
  - name: wildcard-service
    url: http://127.0.0.1:${UPSTREAM_PORT}
    routes:
      - name: wildcard-route
        protocols:
          - https
        hosts:
          - edge.tls.example.test
certificates:
EOF
    printf '  - id: %s\n' "$exact_cert_id"
    write_pem_block "$exact_cert" "$exact_key"
    printf '  - id: %s\n' "$wildcard_cert_id"
    write_pem_block "$wildcard_cert" "$wildcard_key"
    cat <<EOF
snis:
  - id: 33333333-3333-3333-3333-333333333333
    name: exact.example.test
    certificate:
      id: $exact_cert_id
  - id: 44444444-4444-4444-4444-444444444444
    name: "*.tls.example.test"
    certificate:
      id: $wildcard_cert_id
EOF
  } > "$declarative"

  cat > "$conf" <<EOF
database = off
prefix = $OFF_PREFIX
declarative_config = $declarative
proxy_listen = 127.0.0.1:${OFF_PROXY_PORT} ssl
admin_listen = 127.0.0.1:${OFF_ADMIN_PORT}
status_listen = 127.0.0.1:${OFF_STATUS_PORT}
admin_gui_listen = off
nginx_conf = spec/fixtures/custom_nginx.template
anonymous_reports = off
EOF

  source_venv
  bin/kong start -p "$OFF_PREFIX" -c "$conf"

  assert_subject "$OFF_PROXY_PORT" "exact.example.test" "subject=CN=exact.example.test"
  assert_subject "$OFF_PROXY_PORT" "edge.tls.example.test" "subject=CN=*.tls.example.test"
  wait_for_https_body "exact.example.test" "$OFF_PROXY_PORT" "upstream-ok"
  wait_for_https_body "edge.tls.example.test" "$OFF_PROXY_PORT" "upstream-ok"
}

run_postgres_mode() {
  local exact_cert="$TMP_DIR/pg-exact.crt"
  local exact_key="$TMP_DIR/pg-exact.key"
  local wildcard_cert="$TMP_DIR/pg-wildcard.crt"
  local wildcard_key="$TMP_DIR/pg-wildcard.key"
  local conf="$TMP_DIR/kong-pg.conf"

  create_self_signed "exact.example.test" "$exact_cert" "$exact_key"
  create_self_signed "*.tls.example.test" "$wildcard_cert" "$wildcard_key"

  docker rm -f "$PG_CONTAINER" >/dev/null 2>&1 || true
  docker run -d \
    --name "$PG_CONTAINER" \
    -e POSTGRES_USER=kong \
    -e POSTGRES_PASSWORD=kong \
    -e POSTGRES_DB=kong \
    -p "${PG_PORT}:5432" \
    postgres:17 >/dev/null

  for _ in $(seq 1 60); do
    if docker exec "$PG_CONTAINER" pg_isready -U kong -d kong >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  cat > "$conf" <<EOF
database = postgres
prefix = $PG_PREFIX
pg_host = 127.0.0.1
pg_port = $PG_PORT
pg_user = kong
pg_password = kong
pg_database = kong
proxy_listen = 127.0.0.1:${PG_PROXY_PORT} ssl
admin_listen = 127.0.0.1:${PG_ADMIN_PORT}
status_listen = 127.0.0.1:${PG_STATUS_PORT}
admin_gui_listen = off
nginx_conf = spec/fixtures/custom_nginx.template
anonymous_reports = off
EOF

  source_venv
  bin/kong migrations bootstrap -p "$PG_PREFIX" -c "$conf"
  bin/kong start -p "$PG_PREFIX" -c "$conf"
  wait_for_http "http://127.0.0.1:${PG_ADMIN_PORT}/status"

  post_json "http://127.0.0.1:${PG_ADMIN_PORT}/services" \
    "{\"name\":\"exact-service\",\"url\":\"http://127.0.0.1:${UPSTREAM_PORT}\"}" >/dev/null
  post_json "http://127.0.0.1:${PG_ADMIN_PORT}/services/exact-service/routes" \
    "{\"protocols\":[\"https\"],\"hosts\":[\"exact.example.test\"]}" >/dev/null
  post_json "http://127.0.0.1:${PG_ADMIN_PORT}/services" \
    "{\"name\":\"wildcard-service\",\"url\":\"http://127.0.0.1:${UPSTREAM_PORT}\"}" >/dev/null
  post_json "http://127.0.0.1:${PG_ADMIN_PORT}/services/wildcard-service/routes" \
    "{\"protocols\":[\"https\"],\"hosts\":[\"edge.tls.example.test\"]}" >/dev/null

  python3 - "$PG_ADMIN_PORT" "$exact_cert" "$exact_key" "$wildcard_cert" "$wildcard_key" <<'PY'
import json
import pathlib
import sys
import urllib.request

port = sys.argv[1]

def post(path, payload):
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req) as resp:
        if resp.status not in (200, 201):
            raise SystemExit(resp.status)

def read(path):
    return pathlib.Path(path).read_text()

post("/certificates", {
    "cert": read(sys.argv[2]),
    "key": read(sys.argv[3]),
    "snis": ["exact.example.test"],
})
post("/certificates", {
    "cert": read(sys.argv[4]),
    "key": read(sys.argv[5]),
    "snis": ["*.tls.example.test"],
})
PY

  sleep 2
  assert_subject "$PG_PROXY_PORT" "exact.example.test" "subject=CN=exact.example.test"
  assert_subject "$PG_PROXY_PORT" "edge.tls.example.test" "subject=CN=*.tls.example.test"
  wait_for_https_body "exact.example.test" "$PG_PROXY_PORT" "upstream-ok"
  wait_for_https_body "edge.tls.example.test" "$PG_PROXY_PORT" "upstream-ok"
}

trap cleanup EXIT

cd "$ROOT_DIR"
start_upstream
run_off_mode
run_postgres_mode
echo "SSL yield regression smoke checks passed."
