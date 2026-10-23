# Reuse the previously built //build:kong payload; assert source image ID in build.sh.
FROM kkong:3.10.0-sec20261023b AS payload
FROM cgr.dev/chainguard/wolfi-base@sha256:f15fea2f49cb14dceaea491fcbde0d35e0c190126a744ac05a9838440d47d994
RUN apk upgrade --no-cache && apk add --no-cache glibc yaml zlib libstdc++ perl bash ca-certificates-bundle \
 && addgroup -g 10001 kong && adduser -D -u 10001 -G kong -h /usr/local/kong kong
COPY --from=payload /usr/local/ /usr/local/
COPY --from=payload /entrypoint.sh /entrypoint.sh
# Mozilla 2026-10-20 trust bundle; includes removal of emSign C1/C3.
COPY mozilla-cacert-20261020.pem /etc/ssl/certs/ca-certificates.crt
RUN mkdir -p /usr/local/kong /etc/kong && chown -R kong:kong /usr/local/kong
USER 10001:10001
ENV KONG_DATABASE=off KONG_ADMIN_LISTEN=127.0.0.1:8001 KONG_NGINX_WORKER_PROCESSES=2 \
 KONG_ANONYMOUS_REPORTS=off KONG_ADMIN_GUI_LISTEN=off
EXPOSE 8000 8443 8001 8444
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s CMD kong-health
ENTRYPOINT ["/entrypoint.sh"]
CMD ["kong", "docker-start"]
LABEL org.opencontainers.image.version="3.10.0-sec20261023c-wolfi"
