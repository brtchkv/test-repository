#!/bin/bash

set -eo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/k8s-secret-util.sh"

HOST="unknown"
PORT="5432"
PASSWORD=""
USERNAME="unknown"
NAME="unknown"

echo "Starting mysql with secret $1"
k8s_import_secret "$1" "" HOST PORT PASSWORD USERNAME NAME

MYSQL_PWD="$PASSWORD" exec mysql -h "$HOST" -P "$PORT" -u "$USERNAME" "$NAME"