# Kong 1.31.0 Porting Notes

This tree is a Kong source fork used to validate Kong on a custom OpenResty
runtime whose embedded nginx core was moved to the `1.31.x` line.

## What Changed

- Base OpenResty requirement moved from `1.27.1.2` to `1.29.2.3`.
- The OpenResty source fetch path is overridden to a locally repacked tarball:
  - `file:///docker/kong/tmp/openresty-1.29.2.3-nginx-1.31.0-as1292.tar.gz`
- Kong nginx dependency metadata was updated to `1.31.0.3`.
- The `kong_manager` release fetch was pinned to a direct public release tarball.
- `lua_ssl_verify_depth` injection was guarded to avoid duplicate directive
  emission.
- The old `ngx_lua` invalid-hostname patch was removed because the newer upstream
  source already contains that fix.

## Critical Runtime Fix

The most important fix in this tree is:

- `build/openresty/patches/nginx-1.27.1_12-ssl-lua-yield-retry.patch`

This restores nginx/OpenSSL handshake retry handling for OpenResty Lua SSL
yield paths, specifically:

- `SSL_ERROR_WANT_X509_LOOKUP`
- `SSL_ERROR_PENDING_SESSION`
- `SSL_ERROR_WANT_CLIENT_HELLO_CB`
- `SSL_ERROR_WANT_RETRY_VERIFY`

Without that patch, `ssl_certificate_by_lua` could enter but fail after yield
with TLS EOFs on the `1.31.x` runtime.

## Verified Behavior

The following were validated against this port:

- Pure OpenResty `ssl_certificate_by_lua { ngx.sleep(...) }` handshake test
- Kong build and boot on the custom runtime
- DB-backed restore and migration against the production-style schema
- Representative direct proxy behavior
- Representative Caddy-fronted behavior
- Dynamic SNI certificate selection for:
  - `aiotanzania.org`
  - `www.aiotanzania.org`
  - current `*.local.jioh.net` host set

## Remaining Scope Note

Direct Kong TLS certificate coverage still depends on what real certificates
exist in the Caddy storage. At validation time, direct coverage was confirmed
for `aiotanzania.org`, `www.aiotanzania.org`, `local.jioh.net`, and the current
`*.local.jioh.net` route family. Other route families need matching cert assets
before they can be considered covered for direct Kong TLS.
