# syntax=docker/dockerfile:1
ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION} AS builder

ARG PGBOUNCER_VERSION=1.25.2
ARG PGBOUNCER_SHA256="924ad35113fd0a71c8e2dbe85b5d03445532e2b7b37a9f8a48983beea238b332"

RUN apk add --no-cache build-base curl ca-certificates libevent-dev openssl-dev c-ares-dev pkgconf

WORKDIR /build
RUN set -eux; \
    tag="pgbouncer_$(echo "$PGBOUNCER_VERSION" | tr '.' '_')"; \
    curl -fsSL -o pgbouncer.tar.gz \
      "https://github.com/pgbouncer/pgbouncer/releases/download/${tag}/pgbouncer-${PGBOUNCER_VERSION}.tar.gz"; \
    if [ -n "$PGBOUNCER_SHA256" ]; then echo "${PGBOUNCER_SHA256}  pgbouncer.tar.gz" | sha256sum -c -; fi; \
    tar -xzf pgbouncer.tar.gz; \
    cd "pgbouncer-${PGBOUNCER_VERSION}"; \
    ./configure --prefix=/usr/local --disable-debug; \
    make -j"$(nproc)" pgbouncer; \
    strip pgbouncer; \
    install -D -m 0755 pgbouncer /usr/local/bin/pgbouncer

ARG ALPINE_VERSION=3.22
FROM alpine:${ALPINE_VERSION}

ARG PGBOUNCER_VERSION=1.25.2
LABEL org.opencontainers.image.title="pgbouncer" \
      org.opencontainers.image.version="${PGBOUNCER_VERSION}" \
      org.opencontainers.image.description="PgBouncer DB proxy" \
      org.opencontainers.image.source="https://www.pgbouncer.org"

# Runtime libs only (no compilers). bash for the entrypoint; libevent/openssl/c-ares for
RUN apk add --no-cache libevent openssl c-ares ca-certificates bash \
 && addgroup -g 1001 pgbouncer \
 && adduser -D -H -u 1001 -G pgbouncer -s /sbin/nologin pgbouncer

COPY --from=builder /usr/local/bin/pgbouncer /usr/local/bin/pgbouncer
COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# Numeric USER so `runAsNonRoot: true` passes even when the injector sets no runAsUser.
USER 1001
EXPOSE 6432

# Defaults; the entrypoint renders the .ini from these. Override per injection.
ENV PGB_CONF_DIR=/etc/pgbouncer \
    PGB_LISTEN_ADDR=127.0.0.1 \
    PGB_LISTEN_PORT=6432 \
    PGB_POOL_MODE=transaction \
    PGB_MAX_CLIENT_CONN=100 \
    PGB_DEFAULT_POOL_SIZE=20 \
    PGB_AUTH_TYPE=scram-sha-256 \
    PGB_SERVER_TLS_SSLMODE=prefer

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["sh", "-c", "exec pgbouncer ${PGB_CONF_DIR}/pgbouncer.ini"]