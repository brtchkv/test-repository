#!/bin/bash
set -e
set -o pipefail
unique_path="$(date +%Y%m%d_%H%M%S)_$(uuidgen)"
script_dir=$(dirname "$0")

# Required env vars (same as mysql test style)
if [ -z "$BUCKET_NAME" ]; then
    echo "Error: BUCKET_NAME environment variable not set."
    exit 1
fi
if [ -z "$DB_URL" ]; then
    echo "Error: DB_URL environment variable not set."
    exit 1
fi
if [ -z "$ENDPOINT" ]; then
    echo "Error: S3 ENDPOINT environment variable not set."
    exit 1
fi
if [ -z "$AWS_ACCESS_KEY_ID" ]; then
    echo "Error: AWS_ACCESS_KEY_ID environment variable not set."
    exit 1
fi
if [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
    echo "Error: AWS_SECRET_ACCESS_KEY environment variable not set."
    exit 1
fi

# Parse DB URL for psql connection convenience (host, port, db, user) if needed
# But psql can connect via URL directly, so we primarily use $DB_URL.

run_query() {
  # Run a SQL query and output first column of first row
  if ! psql "$DB_URL" -At -c "$1"; then
    echo "Failed to run query: $1"
    exit 1
  fi
}

count_rows() {
  local table="$1"
  local expected="$2"
  local count
  count=$(run_query "SELECT count(*) FROM ${table};")
  if [ "$count" != "$expected" ]; then
    echo "Invalid '${table}' count (expected $expected, current $count)"
    exit 1
  fi
}

# Load initial schema/data
echo "Creating tables via dump.sql ..."
psql "$DB_URL" -v ON_ERROR_STOP=1 -f "$script_dir/dump.sql"
count_rows "employees" 3

# Create backup (checkpoint1)
echo "Creating checkpoint1..."
BACKUP_PREFIX="/testing/psql/${unique_path}/" BACKUP_NAME="checkpoint1" "$script_dir/../../psql/create.sh"

# Modify data to verify restore
run_query "DELETE FROM employees;"
count_rows "employees" 0

# Restore backup
echo "Restoring checkpoint1..."
BACKUP_PREFIX="/testing/psql/${unique_path}/" BACKUP_FILE="checkpoint1.pgdump.gz" "$script_dir/../../psql/restore.sh"

# Validate restored data
count_rows "employees" 3

echo "All tests passed"
