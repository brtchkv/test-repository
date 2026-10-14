#!/bin/bash

# Shared helper for the k8s-* scripts. Not meant to be executed, only sourced:
#   . "$(dirname "${BASH_SOURCE[0]}")/k8s-secret-util.sh"

# usage: k8s_import_secret SECRET_NAME VAR_PREFIX [ALLOWED_KEY...]
# env KUBECTL_OPTIONS - custom options for kubectl
#
# Fetches the secret with kubectl and assigns every entry to a shell variable named
# VAR_PREFIX + KEY (key upper-cased, runs of non-alphanumerics replaced with "_").
# If ALLOWED_KEYs are given, all other keys are ignored. Either a non-empty
# VAR_PREFIX or an allowlist is required, so a secret can never define arbitrary
# unprefixed variables. Values are assigned one by one with printf -v instead of
# eval - they must never reach the shell parser.
# As defense in depth, names that would change shell behaviour (PATH, LD_*, IFS, ...)
# and readonly names (UID, EUID, ...) are still skipped: the prefix comes from the
# caller and may itself be hostile (e.g. prefix "LD_" + key "preload").
# Sets K8S_IMPORTED_VARS to the sorted, space-separated list of assigned names.
# Local names are lower-cased so printf -v cannot collide with them: keys are always
# upper-cased, so the assignments land in the caller's scope

k8s_import_secret() {
  local _secret_name=$1 _prefix _data _allowed _key _value_b64 _value _var_name _imported
  # k8s secret names are DNS subdomains - reject anything else before it reaches kubectl as an option
  if ! [[ "$_secret_name" =~ ^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$ ]]; then
    echo "ERROR: invalid secret name '$_secret_name'" >&2
    return 1
  fi
  # the prefix becomes part of a variable name - fail instead of silently mangling it
  if ! [[ "${2-}" =~ ^([a-zA-Z_][a-zA-Z0-9_]*)?$ ]]; then
    echo "ERROR: invalid variable prefix '${2-}', allowed: [a-zA-Z_][a-zA-Z0-9_]*" >&2
    return 1
  fi
  _prefix="${2-}"
  _allowed=" ${*:3} "
  # without a prefix or an allowlist, a secret could define any variable it likes
  if [[ -z "$_prefix" && $# -le 2 ]]; then
    echo "ERROR: a VAR_PREFIX or a list of allowed keys is required" >&2
    return 1
  fi

  _data=$(kubectl $KUBECTL_OPTIONS get secret -o json -- "$_secret_name" | jq -r '.data')

  _imported=""
  while read -r _key _value_b64; do
    [[ $# -le 2 || "$_allowed" == *" $_key "* ]] || continue
    _var_name="${_prefix}${_key}"
    [[ "$_var_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || continue
    # never let a secret rewire the shell or the import itself
    [[ "$_var_name" =~ ^(PATH|LD_.*|BASH_.*|ENV|PROMPT_COMMAND|PS[0-4]|IFS|HOME|SHELLOPTS|BASHOPTS|CDPATH|K8S_IMPORTED_VARS)$ ]] && continue
    # assigning a readonly name like UID is a fatal shell error - probe it in a subshell first
    (printf -v "$_var_name" '%s' '') 2>/dev/null || continue
    _value=$(printf '%s' "$_value_b64" | base64 -d; printf x)
    printf -v "$_var_name" '%s' "${_value%x}"
    _imported+="${_imported:+ }$_var_name"
  done < <(printf '%s' "$_data" | jq -r 'to_entries[] | "\(.key|ascii_upcase|gsub("[^a-zA-Z0-9]+"; "_")) \(.value)"' | sort)
  # set the result only after the loop, so a secret key named K8S_IMPORTED_VARS cannot hijack it
  K8S_IMPORTED_VARS="$_imported"
}
