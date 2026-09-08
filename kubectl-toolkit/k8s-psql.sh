#!/bin/bash

set -eo pipefail

HOST="unknown"
PORT="5432"
PASSWORD=""
USERNAME="unknown"
NAME="unknown"

echo "Starting psql with secret $1"
SECRET_DATA=$(kubectl $KUBECTL_OPTIONS get secret "$1" -o json | jq -r '.data')

eval $( echo $SECRET_DATA | jq -r 'to_entries | map("\(.key|ascii_upcase|gsub("[^a-zA-Z0-9]+"; "_"))=\(.value|@base64d|@sh)") | .[]')
unset SECRET_DATA

PGPASSWORD="$PASSWORD" exec psql -h "$HOST" -p "$PORT" -U "$USERNAME" "$NAME"