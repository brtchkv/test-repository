#!/bin/bash

# usage: k8s-secret SECRET_NAME VAR_PREFIX
# env KUBECTL_OPTIONS - custom options for kubectl

. "$(dirname "${BASH_SOURCE[0]}")/k8s-secret-util.sh"

k8s_import_secret "$1" "${2-}"
echo "Import environment variables from secret '$1': ${K8S_IMPORTED_VARS// /, }"

# this script is meant to be sourced - do not leak the helpers into the user's shell
unset -f k8s_import_secret
unset K8S_IMPORTED_VARS
