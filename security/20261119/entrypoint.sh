#!/bin/sh
# POSIX (busybox) port of build/dockerfiles/entrypoint.sh for the distroless image.
set -eu

# file_env VAR: fill VAR from the file named in VAR_FILE (Docker secrets).
file_env() {
  var=$1; fvar="${var}_FILE"
  eval "fval=\${$fvar:-}"; [ -n "$fval" ] || return 0
  eval "cur=\${$var:-}"
  if [ -n "$cur" ]; then echo "error: both $var and $fvar are set (but are exclusive)" >&2; exit 1; fi
  val=$(cat "$fval")
  export "$var=$val"
  unset "$fvar"
}

export KONG_NGINX_DAEMON="${KONG_NGINX_DAEMON:-off}"

if [ "${1:-}" = kong ]; then
  defaults=/usr/local/share/lua/5.1/kong/templates/kong_defaults.lua
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in *=*) ;; *) continue ;; esac
    opt=${line%%=*}; opt=$(printf '%s' "$opt" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
    case "$opt" in ''|*[!A-Z0-9_]*) continue ;; esac
    file_env "KONG_$opt"
  done < "$defaults"
  file_env KONG_PASSWORD
  PREFIX="${KONG_PREFIX:-/usr/local/kong}"
  export KONG_PREFIX="$PREFIX"

  if [ "${2:-}" = docker-start ]; then
    kong prepare -p "$PREFIX" "$@"
    warned=0
    for f in "$PREFIX"/sockets/*; do
      if [ -S "$f" ]; then
        if [ "$warned" = 0 ]; then
          echo "WARN: found dangling unix sockets in $PREFIX/sockets while preparing to start Kong; Kong may have been shut down uncleanly." >&2
          warned=1
        fi
        rm -f "$f"
      fi
    done
    ln -sfn /dev/stdout "$PREFIX/logs/access.log"
    ln -sfn /dev/stdout "$PREFIX/logs/admin_access.log"
    ln -sfn /dev/stderr "$PREFIX/logs/error.log"
    exec /usr/local/openresty/nginx/sbin/nginx -p "$PREFIX" -c nginx.conf
  fi
fi

exec "$@"
