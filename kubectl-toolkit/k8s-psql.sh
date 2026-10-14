#!/bin/bash

set -eo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/k8s-secret-util.sh"

HOST="unknown"
PORT="5432"
PASSWORD=""
USERNAME="unknown"
NAME="unknown"

echo "Starting psql with secret $1"
k8s_import_secret "$1" "" HOST PORT PASSWORD USERNAME NAME

PGPASSWORD="$PASSWORD" exec psql -h "$HOST" -p "$PORT" -U "$USERNAME" "$NAME"