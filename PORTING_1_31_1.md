# Kong 1.31.1 Porting Notes

This tree is a security-focused Kong source fork used to validate Kong on a
custom OpenResty runtime whose embedded nginx core was moved to the `1.31.x`
line. Its purpose is to carry security-related runtime porting work and verify
that Kong remains functional on patched upstream nginx/OpenResty combinations.

## What Changed

- Base OpenResty requirement moved from `1.27.1.2` to `1.29.2.5`.
- The OpenResty source fetch path is overridden to a locally repacked tarball:
  - `file:///docker/kong/tmp/openresty-1.29.2.5-nginx-1.31.1-as1292.tar.gz`
- Kong nginx dependency metadata was updated to `1.31.1.5`.
- This repack picks up the nginx `1.31.1` fix for `CVE-2026-9256`.
- The vendored OpenResty repack also restores the nginx `socket_cloexec` core
  patch required for `ngx.pipe` support on the `1.31.1` runtime.
- The `kong_manager` release fetch was pinned to a direct public release tarball.
- `lua_ssl_verify_depth` injection was guarded to avoid duplicate directive
  emission.
- The old `ngx_lua` invalid-hostname patch was removed because the newer upstream
  source already contains that fix.

## Critical Runtime Fix

The most important fixes in this tree are:

- `build/openresty/patches/nginx-1.27.1_12-ssl-lua-yield-retry.patch`
- vendored OpenResty repack with the nginx `socket_cloexec` core patch restored

Together they restore:

- nginx/OpenSSL handshake retry handling for OpenResty Lua SSL yield paths,
  specifically:

- `SSL_ERROR_WANT_X509_LOOKUP`
- `SSL_ERROR_PENDING_SESSION`
- `SSL_ERROR_WANT_CLIENT_HELLO_CB`
- `SSL_ERROR_WANT_RETRY_VERIFY`
- `ngx.pipe` runtime availability required by the upstream integration test
  harness

Without these changes, `ssl_certificate_by_lua` could enter but fail after
yield with TLS EOFs on the `1.31.x` runtime, and `ngx.pipe`-backed tests would
abort before execution.

## Verified Behavior

The following were validated against this port:

- Pure OpenResty `ssl_certificate_by_lua { ngx.sleep(...) }` handshake test
- Kong build and boot on the custom runtime
- DB-backed restore and migration against the production-style schema
- Representative direct proxy behavior
- Representative Caddy-fronted behavior
- Dynamic SNI certificate selection for:
  - exact host certificates
  - wildcard host certificates
  - multiple SNI mappings on the same runtime

## Generic Regression Coverage

This tree now contains a non-personal regression spec for the TLS certificate
yield path:

- `spec/02-integration/05-proxy/35-ssl-yield-regression_spec.lua`

It covers:

- exact SNI certificate lookup over direct Kong TLS
- wildcard SNI certificate lookup over direct Kong TLS
- end-to-end proxy routing after the TLS handshake
- both `postgres` and DB-less (`off`) strategies

The test only uses generic fixture material from `spec/fixtures/ssl.lua` and
generic hostnames:

- `exact.example.test`
- `edge.tls.example.test`
- `*.tls.example.test`

Run it with:

```bash
make dev
make test-custom test_spec=spec/02-integration/05-proxy/35-ssl-yield-regression_spec.lua
```

or:

```bash
./scripts/run-ssl-yield-regression.sh
```

The `busted` spec is the upstream-style regression entrypoint. The shell script
is the self-contained smoke path that generates its own self-signed
certificates, uses only generic `example.test` names, and validates both:

- DB-less declarative config TLS certificate selection
- PostgreSQL-backed Admin API TLS certificate selection

## Remaining Scope Note

Direct Kong TLS certificate coverage still depends on what certificate material
is provisioned into Kong. In the generic regression path in this repository,
coverage is validated with self-signed certificates and non-personal
`example.test` names only.
