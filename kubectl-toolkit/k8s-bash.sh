#!/bin/bash

# usage: k8s-bash SECRET_NAME VAR_PREFIX
# env SECRET_PREFIX   - the prefix, when it cannot be passed as an argument
# env KUBECTL_OPTIONS - custom options for kubectl

set -eo pipefail

. "$(dirname "${BASH_SOURCE[0]}")/k8s-secret-util.sh"

k8s_import_secret "$1" "${2-${SECRET_PREFIX-}}"
echo "Import environment variables from secret '$1': ${K8S_IMPORTED_VARS// /, }"

for VAR_NAME in $K8S_IMPORTED_VARS; do
  export "${VAR_NAME?}"
done
unset K8S_IMPORTED_VARS VAR_NAME SECRET_PREFIX

exec bash