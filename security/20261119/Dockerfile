# kkong 3.10.1 runtime on distroless (Debian 13, glibc).
# Extra executables are limited to what Kong's CLI calls internally:
#   perl (resty launcher used by `kong`), dash as /bin/sh and coreutils ln/chmod/rm/cat/tr/env
#   (pl.utils.executeex and the entrypoint). All of them link only against glibc.
FROM debian:trixie-slim@sha256:a72b4433de1cf7d6bae0c4cee74d0547f58601a643b3375f070c51600d63b6b2 AS deps
RUN apt-get update && apt-get -y upgrade \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       perl-base libyaml-0-2 libcrypt1 \
    && rm -rf /var/lib/apt/lists/*
RUN set -eu; mkdir -p /out/usr/bin /out/bin /out/usr/lib/x86_64-linux-gnu /out/var/lib/dpkg/status.d; \
    dpkg -L perl-base | while read -r f; do [ -f "$f" ] && ! [ -L "$f" ] || continue; \
      case "$f" in /usr/share/doc/*|/usr/share/man/*|/usr/share/lintian/*) continue;; esac; \
      mkdir -p "/out$(dirname "$f")"; cp -a "$f" "/out$f"; done; \
    cp -aL /usr/lib/x86_64-linux-gnu/libyaml-0.so.2 /usr/lib/x86_64-linux-gnu/libcrypt.so.1 /out/usr/lib/x86_64-linux-gnu/; \
    cp -a /bin/dash /out/bin/dash; ln -s dash /out/bin/sh; \
    for a in ln chmod rm cat; do cp -a "/bin/$a" "/out/bin/$a"; done; \
    cp -a /usr/bin/tr /usr/bin/env /out/usr/bin/; \
    mkdir -p /out/empty-kong-prefix /out/etc; for p in perl-base libyaml-0-2 libcrypt1 dash coreutils; do \
      dpkg-query -s "$p" > "/out/var/lib/dpkg/status.d/$p"; done; \
    : passwd/group are built below from the distroless originals.
# Keep the distroless account files (root, nobody, nonroot, ...) and only append:
#   kong (10001) for the default unprivileged run, nogroup (65534) because this nginx
#   was configured with the Debian default group "nogroup" and needs it when started as root.
COPY --from=gcr.io/distroless/cc-debian13:nonroot@sha256:532c7a94f9e96ba9db75eb9388f4227751131c7cb0a411d1a8521af4096135de /etc/passwd /etc/group /dist/
RUN set -eu; cp /dist/passwd /out/passwd; cp /dist/group /out/group; \
    grep -q '^nobody:' /out/passwd; \
    echo 'kong:x:10001:10001:kong:/usr/local/kong:/sbin/nologin' >> /out/passwd; \
    grep -q '^nogroup:' /out/group || echo 'nogroup:x:65534:' >> /out/group; \
    echo 'kong:x:10001:' >> /out/group

FROM gcr.io/distroless/cc-debian13:nonroot@sha256:532c7a94f9e96ba9db75eb9388f4227751131c7cb0a411d1a8521af4096135de
COPY --from=deps /out/usr /usr
COPY --from=deps /out/bin /bin
COPY --from=deps /out/var/lib/dpkg/status.d /var/lib/dpkg/status.d
COPY --from=deps /out/passwd /etc/passwd
COPY --from=deps /out/group /etc/group
# Mozilla 2026-11-05 bundle (118 roots; emSign Root CA - C1/C3 removed upstream).
COPY security/20261119/mozilla-cacert-20261105.pem /etc/ssl/certs/ca-certificates.crt
COPY --chown=0:0 runtime/ /usr/local/
COPY bin/kong bin/kong-health /usr/local/bin/
COPY security/20261119/entrypoint.sh /entrypoint.sh
USER 0:0
# Only the prefix directory itself is writable by kong (sockets/logs); runtime files stay root-owned.
COPY --from=deps /bin/chown /tmp/chown
RUN ["/tmp/chown", "10001:10001", "/usr/local/kong"]
RUN ["/bin/rm", "/tmp/chown"]
# The base image's Debian OpenSSL is not used: Kong, nginx and luasec load the bundled
# OpenSSL 3.5.9 from /usr/local/kong/lib (RUNPATH). Remove it with its package record.
RUN ["/bin/rm", "-rf", "/usr/lib/x86_64-linux-gnu/libssl.so.3", "/usr/lib/x86_64-linux-gnu/libcrypto.so.3", \
     "/usr/share/doc/libssl3t64", "/usr/share/lintian/overrides/libssl3t64", \
     "/var/lib/dpkg/status.d/libssl3t64", "/var/lib/dpkg/status.d/libssl3t64.md5sums"]
USER 10001:10001
ENV PATH=/usr/local/openresty/luajit/bin:/usr/local/openresty/nginx/sbin:/usr/local/openresty/bin:/usr/local/bin:/usr/bin:/bin \
    KONG_DATABASE=off KONG_ADMIN_LISTEN=127.0.0.1:8001 KONG_NGINX_WORKER_PROCESSES=2 \
    KONG_ANONYMOUS_REPORTS=off KONG_ADMIN_GUI_LISTEN=off \
    KONG_LUA_SSL_TRUSTED_CERTIFICATE=system
EXPOSE 8000 8443 8001 8444
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s CMD ["/usr/local/bin/kong-health"]
ENTRYPOINT ["/bin/sh", "/entrypoint.sh"]
CMD ["kong", "docker-start"]
