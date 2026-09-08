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

# Parse DB URL to extract all parameter
# Expected format: mysql://user:password@host:port/dbname
DB_NAME=$(echo $DB_URL | sed -E 's|mysql://.*@.*:[0-9]+/([^/?]+)(\?.*)?$|\1|')
DB_USER=$(echo $DB_URL | sed -E 's|mysql://([^:]+):.*@.*|\1|')
DB_PASS=$(echo $DB_URL | sed -E 's|mysql://[^:]+:([^@]+)@.*|\1|')
DB_HOST=$(echo $DB_URL | sed -E 's|mysql://.*@([^:]+):.*|\1|')
DB_PORT=$(echo $DB_URL | sed -E 's|mysql://.*@.*:([0-9]+)/.*|\1|')

if [ -z "$DB_NAME" ]; then
    echo "Error: Could not extract database name from DB_URL."
    exit 1
fi
if [ -z "$DB_USER" ]; then
  echo "Error: no user found in DB_URL."
  exit 1
fi
if [ -z "$DB_PASS" ]; then
  echo "Error: no password (empty password forbidden) found in DB_URL."
  exit 1
fi
if [ -z "$DB_HOST" ]; then
  echo "Error: no host found in DB_URL."
  exit 1
fi
if [ -z "$DB_PORT" ]; then
  echo "No port found in DB_URL. Using 3306."
  DB_PORT="3306"
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

detect_dump_version() {
    local version_output=""

    if command -v mysqldump >/dev/null 2>&1; then
        version_output=$(mysqldump --version 2>/dev/null)
        if echo "$version_output" | grep -qi mariadb; then
            echo "mariadb"
        else
            echo "mysql"
        fi
    else
        echo "unknown"
    fi
}

DUMP_TYPE=$(detect_dump_version)

BACKUP_PREFIX=$(getvar BACKUP_PREFIX)
BACKUP_PREFIX="${BACKUP_PREFIX#"${BACKUP_PREFIX%%[!\/]*}"}" # trim left slashes

# Create timestamp for backup file
BACKUP_NAME=$(getvar BACKUP_NAME)
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${DB_NAME}_${TIMESTAMP}.sql.gz"
if [ -n "$BACKUP_NAME" ]; then
  BACKUP_FILE="${BACKUP_NAME}.sql.gz"
fi

echo "Starting MySQL backup for database: $DB_NAME"
echo "Backup filename: $BACKUP_FILE"

echo "Detected dump type: $DUMP_TYPE"

if [ "$DUMP_TYPE" = "mariadb" ]; then
    # MariaDB doesn't support --set-gtid-purged и --no-tablespaces
    DUMP_PARAMS="--single-transaction --no-tablespaces --default-character-set=utf8mb4"
else
    # With MySQL version use standard flags
    DUMP_PARAMS="--set-gtid-purged=OFF --no-tablespaces --single-transaction --default-character-set=utf8mb4"
fi
# Perform mysqldump
echo "Running mysqldump..."
if ! MYSQL_PWD="$DB_PASS" mysqldump -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" $DUMP_PARAMS "$DB_NAME" | \
 gzip >"/tmp/$BACKUP_FILE"; then
  echo "Error: unable to create dump and gzip for $DB_NAME to /tmp/$BACKUP_FILE"
  exit 1
fi
echo "Backup created successfully: /tmp/$BACKUP_FILE"

# Upload to S3
echo "Uploading backup to S3 bucket: $BUCKET_NAME (endpoint $ENDPOINT)"
if ! s3cmd --host="$ENDPOINT" --host-bucket="" --disable-multipart \
 put "/tmp/$BACKUP_FILE" "s3://${BUCKET_NAME}/${BACKUP_PREFIX}${BACKUP_FILE}"; then
  echo "Error: unable to upload dump file to bucket ${BUCKET_NAME}"
  exit 1
fi

echo "Backup of ${DB_NAME} uploaded successfully to s3://${BUCKET_NAME}/${BACKUP_PREFIX}${BACKUP_FILE} (endpoint $ENDPOINT)"
echo "Backup process completed."