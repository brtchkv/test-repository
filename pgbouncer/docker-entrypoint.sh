#!/bin/bash
set -euo pipefail

CONF_DIR="${PGB_CONF_DIR:-/etc/pgbouncer}"
INI="${CONF_DIR}/pgbouncer.ini"
USERLIST="${CONF_DIR}/userlist.txt"

mkdir -p "$CONF_DIR"

# If a full config is mounted (ConfigMap/Secret), use it verbatim; otherwise render from env.
if [ ! -f "$INI" ]; then
  : "${PGB_DB_NAME:?PGB_DB_NAME required}"      # name the client connects to
  : "${PGB_DB_HOST:?PGB_DB_HOST required}"      # real Postgres host
  PGB_DB_PORT="${PGB_DB_PORT:-5432}"
  PGB_SERVER_DBNAME="${PGB_SERVER_DBNAME:-$PGB_DB_NAME}"

  cat > "$INI" <<EOF
[databases]
${PGB_DB_NAME} = host=${PGB_DB_HOST} port=${PGB_DB_PORT} dbname=${PGB_SERVER_DBNAME}

[pgbouncer]
listen_addr = ${PGB_LISTEN_ADDR:-127.0.0.1}
listen_port = ${PGB_LISTEN_PORT:-6432}
pool_mode = ${PGB_POOL_MODE:-transaction}
max_client_conn = ${PGB_MAX_CLIENT_CONN:-100}
default_pool_size = ${PGB_DEFAULT_POOL_SIZE:-20}
auth_type = ${PGB_AUTH_TYPE:-scram-sha-256}
auth_file = ${USERLIST}
${PGB_AUTH_USER:+auth_user = ${PGB_AUTH_USER}}
${PGB_AUTH_QUERY:+auth_query = ${PGB_AUTH_QUERY}}
server_tls_sslmode = ${PGB_SERVER_TLS_SSLMODE:-prefer}
ignore_startup_parameters = ${PGB_IGNORE_STARTUP:-extra_float_digits,options}
admin_users = ${PGB_ADMIN_USER:-pgbouncer}
# read-only-rootfs friendly: stderr logging, no pidfile, no unix socket
logfile =
pidfile =
unix_socket_dir =
EOF
fi

# Userlist: prefer a mounted secret file; otherwise synthesize from env.
if [ ! -f "$USERLIST" ]; then
  if [ -n "${PGB_AUTH_USER:-}" ] && [ -n "${PGB_AUTH_PASSWORD:-}" ]; then
    printf '"%s" "%s"\n' "$PGB_AUTH_USER" "$PGB_AUTH_PASSWORD" > "$USERLIST"
  else
    : > "$USERLIST"
  fi
  chmod 600 "$USERLIST" || true
fi

exec "$@"