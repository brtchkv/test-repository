#!/bin/bash
set -o pipefail

function getvar() {
    local base_name="$1"

    local name_upper=$(echo "$base_name" | tr '[:lower:]' '[:upper:]')
    local name_lower=$(echo "$base_name" | tr '[:upper:]' '[:lower:]')

    if [ -n "${!name_upper}" ]; then
        echo "${!name_upper}"
    elif [ -n "${!name_lower}" ]; then
        echo "${!name_lower}"
    else
        echo ""
    fi
}

DB_URL=$(getvar DB_URL)
# Load DB URL from environment variable
if [ -z "$DB_URL" ]; then
    echo "Error: DB_URL environment variable not set."
    exit 1
fi

# Parse DB URL to extract database name
DB_NAME=$(echo $DB_URL | sed -E 's|.*/([^/?]+)(\?.*)?$|\1|')
if [ -z "$DB_NAME" ]; then
    echo "Error: Could not extract database name from DB_URL."
    exit 1
fi

# S3 configuration
BUCKET_NAME=$(getvar BUCKET_NAME)
if [ -z "$BUCKET_NAME" ]; then
    echo "Error: BUCKET_NAME environment variable not set."
    exit 1
fi
ENDPOINT=$(getvar ENDPOINT)
if [ -z "$ENDPOINT" ]; then
    echo "Error: S3 ENDPOINT environment variable not set."
    exit 1
fi
ENDPOINT="${ENDPOINT%/}"
AWS_ACCESS_KEY_ID=$(getvar AWS_ACCESS_KEY_ID)
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo "Error: AWS_ACCESS_KEY_ID environment variable not set."
    exit 1
fi
AWS_SECRET_ACCESS_KEY=$(getvar AWS_SECRET_ACCESS_KEY)
if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Error: AWS_SECRET_ACCESS_KEY environment variable not set."
    exit 1
fi

BACKUP_PREFIX=$(getvar BACKUP_PREFIX)
BACKUP_PREFIX="${BACKUP_PREFIX#"${BACKUP_PREFIX%%[!\/]*}"}" # trim left slashes

# Create timestamp for backup file
BACKUP_NAME=$(getvar BACKUP_NAME)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${DB_NAME}_${TIMESTAMP}.pgdump.gz"
if [ -n "$BACKUP_NAME" ]; then
  BACKUP_FILE="${BACKUP_NAME}.pgdump.gz"
fi

echo "Starting PostgreSQL backup for database: $DB_NAME"
echo "Backup filename: $BACKUP_FILE"

# Perform pg_dump
echo "Running pg_dump..."
if ! pg_dump -Fc -v --exclude-schema='google_vacuum*' --exclude-schema='google_db_advisor' "$DB_URL" | gzip >"/tmp/$BACKUP_FILE"; then
  echo "Error: failed to dump and gzip the data"
  exit 1
fi
echo "Backup created successfully: /tmp/$BACKUP_FILE"

# Upload to S3
echo "Uploading backup to S3 bucket: $BUCKET_NAME (endpoint $ENDPOINT)"
if ! s3cmd --host="$ENDPOINT" --host-bucket="" \
  put "/tmp/$BACKUP_FILE" "s3://${BUCKET_NAME}/${BACKUP_PREFIX}${BACKUP_FILE}"; then
  echo "Retrying with multipart disabled..."
  if ! s3cmd --host="$ENDPOINT" --host-bucket="" --disable-multipart \
    put "/tmp/$BACKUP_FILE" "s3://${BUCKET_NAME}/${BACKUP_PREFIX}${BACKUP_FILE}"; then
    echo "Error: failed to upload /tmp/$BACKUP_FILE to bucket ${BUCKET_NAME}"
    exit 1
  fi
fi

echo "Backup of ${DB_NAME} uploaded successfully to s3://${BUCKET_NAME}/${BACKUP_PREFIX}${BACKUP_FILE} (endpoint $ENDPOINT)"
echo "Backup process completed."