#!/bin/bash

set -eo pipefail


SECRET_DATA=$(kubectl $KUBECTL_OPTIONS get secret "$1" -o json | jq -r '.data')

SECRET_VAR_LIST=$(echo $SECRET_DATA | jq -r 'to_entries | map("\(env.SECRET_PREFIX|"")\(.key|ascii_upcase|gsub("[^a-zA-Z0-9]+"; "_"))") | .[]' | sort | awk 'ORS=", "')
echo "Import environment variables from secret '$1': ${SECRET_VAR_LIST%', '}"

eval $( echo $SECRET_DATA | jq -r 'to_entries | map("export \(env.SECRET_PREFIX|"")\(.key|ascii_upcase|gsub("[^a-zA-Z0-9]+"; "_"))=\(.value|@base64d|@sh)") | .[]')
unset SECRET_DATA

exec bash