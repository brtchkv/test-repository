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

RESTORE_OWNER=$(getvar RESTORE_OWNER)
RESTORE_OWNER="${RESTORE_OWNER:-false}"
# Load DB URL from environment variable

DB_URL=$(getvar DB_URL)
if [ -z "$DB_URL" ]; then
    echo "Error: DB_URL environment variable not set."
    exit 1
fi

# Parse DB URL to extract database name
DB_NAME=$(echo "$DB_URL" | sed -E 's|.*/([^/?]+)(\?.*)?$|\1|')
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
    echo "Error: (bucket) ENDPOINT environment variable not set."
    exit 1
fi
ENDPOINT="${ENDPOINT%/}"
# Check for BACKUP_FILE or BACKUP_PREFIX
BACKUP_FILE=$(getvar BACKUP_FILE)
BACKUP_FILE_PROVIDED="$BACKUP_FILE"
BACKUP_PREFIX="${BACKUP_PREFIX#"${BACKUP_PREFIX%%[!\/]*}"}"

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
        "s3://${BUCKET_NAME}/${BACKUP_PREFIX}" | grep "\.pgdump\.gz$" | sort -k1,2 -r | head -n 1 | awk '{print $4}')

    if [ -z "$BACKUP_FILE" ]; then
        echo "Error: No backup files with .pgdump.gz extension found with prefix '${BACKUP_PREFIX}' in bucket '${BUCKET_NAME}'."
        exit 1
    fi

    # Extract the key part from the full s3 URL
    BACKUP_FILE=${BACKUP_FILE#s3://${BUCKET_NAME}/}

    echo "Found most recent backup file: $BACKUP_FILE"
fi

if [ -n "$BACKUP_FILE_PROVIDED" ]; then
    BACKUP_FILE="${BACKUP_PREFIX}${BACKUP_FILE#"${BACKUP_FILE%%[!\/]*}"}"
fi
# Extract just the filename without path
BACKUP_FILENAME=$(basename "$BACKUP_FILE")

echo "Starting restore process for database: $DB_NAME"
echo "Backup file to restore: $BACKUP_FILENAME"

# Download from S3
echo ""
echo "Downloading backup from S3: s3://${BUCKET_NAME}/${BACKUP_FILE}"
if ! s3cmd --force --host="$ENDPOINT" --access_key="$AWS_ACCESS_KEY_ID" --secret_key="$AWS_SECRET_ACCESS_KEY" --host-bucket="" \
  get "s3://${BUCKET_NAME}/${BACKUP_FILE}" "/tmp/${BACKUP_FILENAME}"; then
  echo "Error: unable to upload dump from bucket ${BUCKET_NAME} to /tmp/${BACKUP_FILENAME}"
  exit 1
fi

echo "Backup downloaded successfully to /tmp/${BACKUP_FILENAME}"

# Extract if it's a gzipped file
if [[ "$BACKUP_FILENAME" == *.gz ]]; then
    echo "Extracting gzipped backup file..."
    if ! gunzip -f "/tmp/${BACKUP_FILENAME}"; then
      echo "Error: unable to unzip dump-file /tmp/${BACKUP_FILENAME}"
      exit 1
    fi
    BACKUP_FILENAME="${BACKUP_FILENAME%.gz}"
    echo "Extracted to: /tmp/${BACKUP_FILENAME}"
fi

echo ""
echo "Backup ${BACKUP_FILENAME} contains:"
if ! pg_restore -l "/tmp/${BACKUP_FILENAME}" > /tmp/pg_toc.list; then
  echo "Error: unable analyze dump-file /tmp/${BACKUP_FILENAME} (is it binary pgdump format?)"
  exit 1
fi
cat /tmp/pg_toc.list

# Filter out Cloud SQL system objects (extensions and ACLs owned by cloudsqladmin)
grep -v -E 'google_vacuum|google_db_advisor|hypopg|cloudsqladmin' /tmp/pg_toc.list > /tmp/pg_toc_filtered.list

echo ""
echo "Restore ${DB_NAME} database:"

# Restore the database using pg_restore with filtered TOC
if [ "$RESTORE_OWNER" = "true" ]; then
    echo "Restoring database using pg_restore with permissions..."
    pg_restore -v               --clean --if-exists -L /tmp/pg_toc_filtered.list -d "$DB_URL" "/tmp/${BACKUP_FILENAME}"
else
    echo "Restoring database using pg_restore without permissions..."
    pg_restore -v -x --no-owner --clean --if-exists -L /tmp/pg_toc_filtered.list -d "$DB_URL" "/tmp/${BACKUP_FILENAME}"
fi

# Check the exit status, but don't fail script on non-zero exit from pg_restore
# as it may return non-zero even for successful restores with warnings
PG_RESTORE_EXIT=$?
if [ $PG_RESTORE_EXIT -ne 0 ]; then
    echo "Warning: pg_restore completed with exit code $PG_RESTORE_EXIT"
    echo "Some errors or warnings may have occurred during restore."
    echo "Please check the output above for details."
else
    echo "Database ${DB_NAME} restored successfully from s3://${BUCKET_NAME}/${BACKUP_FILE} (endpoint $ENDPOINT)"
fi


echo "Restore process completed."