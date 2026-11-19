#!/usr/bin/env bash
set -euo pipefail
image=${1:?image}
result=$(docker run --rm --entrypoint resty "$image" --http-conf 'lua_ssl_trusted_certificate /etc/ssl/certs/ca-certificates.crt;' --http-conf 'lua_ssl_verify_depth 5;' -e 'local h=require("resty.http").new(); h:set_timeout(15000); local r,e=h:request_uri("https://example.com",{ssl_verify=true}); assert(r,e); assert(r.status==200,r.status); print("PASS system CA TLS: ",r.status)' 2>&1)
printf '%s\n' "$result"
# resty may return zero even if its Lua callback fails; assert the success marker.
[[ "$result" == *'PASS system CA TLS: 200'* ]]
