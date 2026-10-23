FROM ubuntu:26.04@sha256:c098726dd9b9733f3e885f8de0ef375206a311b0a317eadc40d347b1115fb944
# The base's unowned Pebble service manager is unused by Kong and embeds old Go code.
RUN rm -f /usr/bin/pebble \
    && apt-get update && apt-get -y upgrade \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
       ca-certificates perl libyaml-0-2 zlib1g libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 kong \
    && useradd --uid 10001 --gid 10001 --home-dir /usr/local/kong kong
COPY runtime/ /usr/local/
RUN mkdir -p /usr/local/kong /etc/kong \
    && chown -R kong:kong /usr/local/kong \
    && ln -s /usr/local/openresty/luajit/bin/luajit /usr/local/bin/luajit \
    && ln -s /usr/local/openresty/nginx/sbin/nginx /usr/local/bin/nginx \
    && ln -s /usr/local/openresty/bin/resty /usr/local/bin/resty
COPY bin/kong bin/kong-health /usr/local/bin/
COPY build/dockerfiles/entrypoint.sh /entrypoint.sh
USER kong
ENV KONG_DATABASE=off KONG_ADMIN_LISTEN=127.0.0.1:8001 KONG_NGINX_WORKER_PROCESSES=2 \
    KONG_ANONYMOUS_REPORTS=off KONG_ADMIN_GUI_LISTEN=off
EXPOSE 8000 8443 8001 8444
STOPSIGNAL SIGQUIT
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s CMD kong-health
ENTRYPOINT ["/entrypoint.sh"]
CMD ["kong", "docker-start"]
