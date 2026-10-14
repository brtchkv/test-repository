#!/bin/bash

set -eo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/k8s-secret-util.sh"

k8s_import_secret "$1" "${SECRET_PREFIX-}"
echo "Import environment variables from secret '$1': ${K8S_IMPORTED_VARS// /, }"

for VAR_NAME in $K8S_IMPORTED_VARS; do
  export "${VAR_NAME?}"
done
unset K8S_IMPORTED_VARS VAR_NAME SECRET_PREFIX

exec bash