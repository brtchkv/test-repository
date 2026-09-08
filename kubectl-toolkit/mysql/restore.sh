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

# Load DB URL from environment variable
DB_URL=$(getvar DB_URL)
if [ -z "$DB_URL" ]; then
    echo "Error: DB_URL environment variable not set."
    exit 1
fi

# Parse DB URL to extract database name and connection details
# Expected format: mysql://user:password@host:port/dbname
DB_NAME=$(echo "$DB_URL" | sed -E 's|mysql://.*@.*:[0-9]+/([^/?]+)(\?.*)?$|\1|')
if [ -z "$DB_NAME" ]; then
    echo "Error: Could not extract database name from DB_URL."
    exit 1
fi

# Extract other connection parameters from DB_URL
DB_USER=$(echo $DB_URL | sed -E 's|mysql://([^:]+):.*@.*|\1|')
DB_PASS=$(echo $DB_URL | sed -E 's|mysql://[^:]+:([^@]+)@.*|\1|')
DB_HOST=$(echo $DB_URL | sed -E 's|mysql://.*@([^:]+):.*|\1|')
DB_PORT=$(echo $DB_URL | sed -E 's|mysql://.*@.*:([0-9]+)/.*|\1|')

# S3 configuration
BUCKET_NAME=$(getvar BUCKET_NAME)
if [ -z "$BUCKET_NAME" ]; then
    echo "Error: BUCKET_NAME environment variable not set."
    exit 1
fi
ENDPOINT=$(getvar ENDPOINT)
if [ -z "$ENDPOINT" ]; then
    echo "Error: (bucket) ENDPOINT environment variable not set."
    exit 1
fi
ENDPOINT="${ENDPOINT%/}"

# Check for BACKUP_FILE or BACKUP_PREFIX
BACKUP_FILE=$(getvar BACKUP_FILE)
BACKUP_PREFIX=$(getvar BACKUP_PREFIX)
BACKUP_PREFIX="${BACKUP_PREFIX#"${BACKUP_PREFIX%%[!\/]*}"}" # trim left slashes

if [ -z "$BACKUP_FILE" ] && [ -z "$BACKUP_PREFIX" ]; then
    echo "Error: Either BACKUP_FILE or BACKUP_PREFIX environment variable must be set."
    exit 1
fi

# If BACKUP_FILE is not provided but BACKUP_PREFIX is, find the most recent file with that prefix
if [ -z "$BACKUP_FILE" ] && [ -n "$BACKUP_PREFIX" ]; then
    echo "BACKUP_FILE not provided. Using BACKUP_PREFIX to find the most recent backup: $BACKUP_PREFIX"

    # List objects in the bucket with the specified prefix, sort by last modified date (newest first)
    # and select the first one (most recent)
    BACKUP_FILE=$(s3cmd ls -r --host="$ENDPOINT" --access_key="$AWS_ACCESS_KEY_ID" --secret_key="$AWS_SECRET_ACCESS_KEY" --host-bucket="" \
        "s3://${BUCKET_NAME}/${BACKUP_PREFIX}" | grep "\.sql\.gz$" | sort -k1,2 -r | head -n 1 | awk '{print $4}')

    if [ -z "$BACKUP_FILE" ]; then
        echo "Error: No backup files with .sql.gz extension found with prefix '${BACKUP_PREFIX}' in bucket '${BUCKET_NAME}'."
        exit 1
    fi

    # Extract the key part from the full s3 URL
    BACKUP_FILE=${BACKUP_FILE#s3://${BUCKET_NAME}/}

    echo "Found most recent backup file: $BACKUP_FILE"
fi

BACKUP_FILE="${BACKUP_PREFIX}${BACKUP_FILE#"${BACKUP_FILE%%[!\/]*}"}" # remove slashes from left

# Extract just the filename without path
BACKUP_FILENAME=$(basename "$BACKUP_FILE")

echo "Starting restore process for database: $DB_NAME"
echo "Backup file to restore: $BACKUP_FILENAME"

# Download from S3
echo ""
echo "Downloading backup from S3: s3://${BUCKET_NAME}/${BACKUP_FILE}"
if ! s3cmd --force --host="$ENDPOINT" --access_key="$AWS_ACCESS_KEY_ID" --secret_key="$AWS_SECRET_ACCESS_KEY" --host-bucket="" \
  get "s3://${BUCKET_NAME}/${BACKUP_FILE}" "/tmp/${BACKUP_FILENAME}"; then
    echo "Error: unable to download backup, please check the credentials"
    exit 1
fi

echo "Backup downloaded successfully to /tmp/${BACKUP_FILENAME}"

# Extract if it's a gzipped file
if [[ "$BACKUP_FILENAME" == *.gz ]]; then
  echo "Extracting gzipped backup file..."
  if ! gunzip -f "/tmp/${BACKUP_FILENAME}"; then
    echo "Error: unable to ungzip /tmp/${BACKUP_FILENAME}"
  fi
  BACKUP_FILENAME="${BACKUP_FILENAME%.gz}"
  echo "Extracted to: /tmp/${BACKUP_FILENAME}"
fi

echo ""
echo "Restore ${DB_NAME} database:"

# Restore the database using mysql client
echo "Restoring database from backup..."
if ! MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" < "/tmp/${BACKUP_FILENAME}"; then
  echo echo "Error: MySQL restore failed with exit code $?"
  exit 1
fi

echo "Database ${DB_NAME} restored successfully from s3://${BUCKET_NAME}/${BACKUP_FILE} (endpoint $ENDPOINT)"
echo "Restore process completed."