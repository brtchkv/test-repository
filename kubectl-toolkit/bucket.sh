#!/bin/bash
set -o pipefail

# Function to load secrets from kubernetes
load_secret() {
    local secret_name=$1

    # Get secret data from kubectl
    secret_data=$(kubectl $KUBECTL_OPTIONS get secret "$secret_name" -o json)
    if [ $? -ne 0 ]; then
        echo "Error: Failed to get secret '$secret_name'" 1>&2
        return 1
    fi

    # Extract values from secret
    AWS_ACCESS_KEY_ID=$(echo "$secret_data" | jq -r '.data.AWS_ACCESS_KEY_ID' | base64 -d)
    AWS_SECRET_ACCESS_KEY=$(echo "$secret_data" | jq -r '.data.AWS_SECRET_ACCESS_KEY' | base64 -d)
    BUCKET_NAME=$(echo "$secret_data" | jq -r '.data."bucket-name"' | base64 -d)
    ENDPOINT=$(echo "$secret_data" | jq -r '.data.endpoint' | base64 -d)
    ENDPOINT="${ENDPOINT%/}"

    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$BUCKET_NAME" ] || [ -z "$ENDPOINT" ]; then
        echo "Error: One or more required values missing from secret" 1>&2
        return 1
    fi
    echo "/* Loaded secret '$secret_name' with access to bucket '$BUCKET_NAME' */" 1>&2

    echo "$ENDPOINT $BUCKET_NAME $AWS_ACCESS_KEY_ID $AWS_SECRET_ACCESS_KEY"
}

# Function to parse the bucket URL (s3://$secret/path)
parse_bucket_url() {
    local bucket_url=$1

    # Extract secret name and path
    if [[ $bucket_url =~ s3://([^/]+)(/.*)? ]]; then
        local secret=${BASH_REMATCH[1]}
        local path=${BASH_REMATCH[2]:-"/"}

        echo "$secret $path"
    else
        echo "Error: Invalid bucket URL format. Expected: s3://secret_name/path" 1>&2
        return 1
    fi
}


# Command: bucket ls s3://secret/path
bucket_ls() {
    local bucket_url=$1

    # Parse bucket URL
    if ! read -r secret path < <(parse_bucket_url "$bucket_url")
    then
        echo "$secret"  # Error message from parse_bucket_url
        return 1
    fi

    # Load secret
    if ! read -r endpoint bucket_name access_key secret_key < <(load_secret "$secret")
    then
        return 1
    fi

    # Execute s3cmd
    s3cmd --host="$endpoint" --access_key="$access_key" --secret_key="$secret_key" --host-bucket="" ls "s3://$bucket_name$path" \
    | sed "s|s3://$bucket_name/|/|g"
    return $?
}

bucket_lr() {
    local bucket_url=$1

    # Parse bucket URL
    if ! read -r secret path < <(parse_bucket_url "$bucket_url")
    then
        echo "$secret"  # Error message from parse_bucket_url
        return 1
    fi

    # Load secret
    if ! read -r endpoint bucket_name access_key secret_key < <(load_secret "$secret")
    then
        return 1
    fi

    # Execute s3cmd
    s3cmd --host="$endpoint" --recursive --access_key="$access_key" --secret_key="$secret_key" --host-bucket="" ls "s3://$bucket_name$path" \
    | sed "s|s3://$bucket_name/|/|g"
    return $?
}

# Command: bucket info s3://secret/path
bucket_info() {
    local bucket_url=$1

    # Parse bucket URL
    if ! read -r secret path < <(parse_bucket_url "$bucket_url")
    then
        echo "$secret"  # Error message from parse_bucket_url
        return 1
    fi

    # Load secret
    if ! read -r endpoint bucket_name access_key secret_key < <(load_secret "$secret")
    then
        return 1
    fi

    # Execute s3cmd
    s3cmd --host="$endpoint" --access_key="$access_key" --secret_key="$secret_key" --host-bucket="" info "s3://$bucket_name$path" \
    | sed "s|s3://$bucket_name/|/|g"
    return $?
}

# Command: bucket put /local/file s3://secret/path
bucket_put() {
    local local_file=$1
    local bucket_url=$2

    # Check if local file exists
    if [ ! -f "$local_file" ]; then
        echo "Error: Local file does not exist: $local_file" 1>&2
        return 1
    fi

    # Parse bucket URL
    if ! read -r secret path < <(parse_bucket_url "$bucket_url")
    then
        echo "$secret"  # Error message from parse_bucket_url
        return 1
    fi

    # Load secret
    if ! read -r endpoint bucket_name access_key secret_key < <(load_secret "$secret")
    then
        return 1
    fi

    local flags
    if [ "$local_file" != "-" ]; then
        flags="$flags --disable-multipart"
    fi

    # Execute s3cmd
    s3cmd --host="$endpoint" --access_key="$access_key" --secret_key="$secret_key" --host-bucket="" $flags --guess-mime-type put "$local_file" "s3://$bucket_name$path"
    return $?
}

# Command: bucket delete s3://secret/path
bucket_delete() {
    local bucket_url=$1

    # Parse bucket URL
    if ! read -r secret path < <(parse_bucket_url "$bucket_url")
    then
        echo "$secret"  # Error message from parse_bucket_url
        return 1
    fi

    # Load secret
    if ! read -r endpoint bucket_name access_key secret_key < <(load_secret "$secret")
    then
        return 1
    fi

    # Execute s3cmd
    s3cmd --host="$endpoint" --access_key="$access_key" --secret_key="$secret_key" --host-bucket="" del "s3://$bucket_name$path"
    return $?
}

# Command: bucket get s3://secret/path /local/file
bucket_get() {
    local bucket_url=$1
    local local_file=$2

    # Parse bucket URL
    if ! read -r secret path < <(parse_bucket_url "$bucket_url")
    then
        echo "$secret"  # Error message from parse_bucket_url
        return 1
    fi

    # Load secret
    if ! read -r endpoint bucket_name access_key secret_key < <(load_secret "$secret")
    then
        return 1
    fi

    if [ "$local_file" != "-" ]; then
        # Create directory for local file if it doesn't exist
        local_dir=$(dirname "$local_file")

        if ! mkdir -p "$local_dir"; then
            echo "Unable create directory for file" 1>&2
            return 1
        fi
    fi

    # s3cmd get s3://bucket/path /local/path
    s3cmd --host="$endpoint" --access_key="$access_key" --secret_key="$secret_key" --host-bucket="" get "s3://$bucket_name$path" "$local_file"
    return $?
}

bucket_truncate() {
  local bucket_url=$1

  # Parse bucket URL
  if ! read -r secret path < <(parse_bucket_url "$bucket_url")
  then
      echo "$secret"  # Error message from parse_bucket_url
      return 1
  fi

  # Prevent accidental full-bucket wipe: require non-root prefix
  if [ "$path" = "/" ] || [ -z "$path" ]; then
      echo "Error: Refusing to truncate whole bucket. Provide a non-empty prefix in URL (e.g., s3://secret/prefix)." 1>&2
      return 1
  fi

  # Load secret
  if ! read -r endpoint bucket_name access_key secret_key < <(load_secret "$secret")
  then
      return 1
  fi

  # Ask for explicit confirmation before recursive delete
  echo "WARNING: You are about to recursively delete all objects under prefix '$path' in bucket '$bucket_name' (endpoint: $endpoint)." 1>&2
  echo "This operation is destructive and cannot be undone." 1>&2
  printf "Type 'yes' to continue: " 1>&2
  read -r answer || answer=""
  if [ "$answer" != "yes" ]; then
      echo "Aborted. Answer was not 'yes'." 1>&2
      return 1
  fi

  # List objects under the prefix and delete them one by one
  # We use recursive listing and extract object keys, then delete each.
  local objects
  # s3cmd ls output lines look like:
  # 2023-01-01 00:00   1234  s3://bucket/prefix/file
  # We cut the 4th column and strip the s3://bucket/ prefix back to path
  objects=$(s3cmd --host="$endpoint" \
                 --recursive \
                 --access_key="$access_key" \
                 --secret_key="$secret_key" \
                 --host-bucket="" \
                 ls "s3://$bucket_name$path" \
            | awk '{print $4}' )

  if [ -z "$objects" ]; then
      echo "No objects found under prefix '$path' in bucket '$bucket_name'. Nothing to delete." 1>&2
      return 0
  fi

  local total=0
  local ok=0
  local fail=0
  local obj

  # Because variables updated in a subshell won't persist, recompute counts using a safer approach
  # Re-run deletion with explicit loop without pipe to keep counts in current shell
  total=0; ok=0; fail=0
  for obj in $objects; do
      [ -z "$obj" ] && continue
      total=$((total+1))
      echo "deleting $obj"
      if s3cmd --host="$endpoint" \
               --access_key="$access_key" \
               --secret_key="$secret_key" \
               --host-bucket="" \
               del "$obj" >/dev/null; then
          ok=$((ok+1))
      else
          echo "Failed to delete: $obj" 1>&2
          fail=$((fail+1))
      fi
  done

  echo "Deletion finished: total=$total, deleted=$ok, failed=$fail" 1>&2

  if [ "$fail" -gt 0 ]; then
      return 1
  fi
  return 0
}

# Command: bucket copy s3://secret1/path s3://secret2/path
bucket_copy() {
    local source_url=$1
    local dest_url=$2

    # Parse bucket1 URL
    if ! read -r secret1 path1 < <(parse_bucket_url "$source_url")
    then
        echo "$secret1"  # Error message from parse_bucket_url
        return 1
    fi

    # Load secret1
    if ! read -r endpoint1 bucket_name1 access_key1 secret_key1 < <(load_secret "$secret1")
    then
        return 1
    fi

    # Parse bucket2 URL
    if ! read -r secret2 path2 < <(parse_bucket_url "$dest_url")
    then
        echo "$secret2"  # Error message from parse_bucket_url
        return 1
    fi

    if [ "$secret1" = "$secret2" ]; then
      endpoint2="$endpoint1"
      bucket_name2="$bucket_name1"
      access_key2="$access_key1"
      secret_key2="$secret_key1"
    else
      # Load secret2
      if ! read -r endpoint2 bucket_name2 access_key2 secret_key2 < <(load_secret "$secret2")
      then
          return 1
      fi
    fi

    s3cmd --host="$endpoint1" --access_key="$access_key1" --secret_key="$secret_key1" --host-bucket="" get "s3://$bucket_name1$path1" - \
    | s3cmd --host="$endpoint2" --access_key="$access_key2" --secret_key="$secret_key2" --host-bucket="" put - "s3://$bucket_name2$path2"
    return $?
}

# Main command dispatcher
case "$1" in
    ls)
        if [ $# -ne 2 ]; then
            echo "Usage: $0 ls s3://secret/path" 1>&2
            exit 1
        fi
        bucket_ls "$2"
        ;;
    lr)
        if [ $# -ne 2 ]; then
            echo "Usage: $0 lr s3://secret/path" 1>&2
            exit 1
        fi
        bucket_lr "$2"
        ;;
    info)
        if [ $# -ne 2 ]; then
            echo "Usage: $0 info s3://secret/path" 1>&2
            exit 1
        fi
        bucket_info "$2"
        ;;
    put)
        if [ $# -ne 3 ]; then
            echo "Usage: $0 put /local/file s3://secret/path" 1>&2
            echo "       $0 put - s3://secret/path" 1>&2
            exit 1
        fi
        bucket_put "$2" "$3"
        ;;
    rm|delete)
        if [ $# -ne 2 ]; then
            echo "Usage: $0 delete s3://secret/path" 1>&2
            exit 1
        fi
        bucket_delete "$2"
        ;;
    get)
        if [ $# -ne 3 ]; then
            echo "Usage: $0 get s3://secret/path /local/file" 1>&2
            echo "       $0 get s3://secret/path -" 1>&2
            exit 1
        fi
        bucket_get "$2" "$3"
        ;;
    copy)
        if [ $# -ne 3 ]; then
            echo "Usage: $0 copy s3://secret1/path s3://secret2/path" 1>&2
            exit 1
        fi
        bucket_copy "$2" "$3"
        ;;
    truncate)
        if [ $# -ne 2 ]; then
            echo "Usage: $0 truncate s3://secret/prefix" 1>&2
            exit 1
        fi
        bucket_truncate "$2"
        ;;
    *)
        echo "Usage: $0 <command> [arguments]"
        echo ""
        echo "Commands:"
        echo "  ls s3://secret/path                            - List objects in bucket"
        echo "  lr s3://secret/path                            - Recursive list of objects in basket"
        echo "  info s3://secret/path                          - Print information about object"
        echo "  put /local/file s3://secret/path               - Upload file to bucket"
        echo "  put - s3://secret/path                         - Upload data from stdin to bucket"
        echo "  delete s3://secret/path                        - Delete file from bucket"
        echo "  get s3://secret/path /local/file               - Download file from bucket"
        echo "  get s3://secret/path -                         - Print file from bucket to stdout"
        echo "  copy s3://secret1/path s3://secret2/path       - Copy file between buckets (doesn't use temporary files)"
        echo "  truncate s3://secret/prefix                    - Delete all objects with the given prefix"
        echo ""
        echo "For other operations use k8s-secret + s3cmd commands"
        exit 1
        ;;
esac

exit $?