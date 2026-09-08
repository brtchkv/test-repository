#!/bin/bash
set -e
set -o pipefail
unique_path="$(date +%Y%m%d_%H%M%S)_$(uuidgen)"
script_dir=$(dirname "$0")
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

count_rows() {
  count=$(run_query "SELECT count(*) FROM $1")
  if [ "$count" != "$2" ]; then
    echo "Invalid '$1' count (expected $2, current $count)"
    exit 1
  fi
}

run_query() {
   if ! MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" -N -e "$1"; then
     echo "Failed to run query $1"
     exit 1
   fi
}

DB_NAME=$(echo $DB_URL | sed -E 's|mysql://.*@.*:[0-9]+/([^/?]+)(\?.*)?$|\1|')
DB_USER=$(echo $DB_URL | sed -E 's|mysql://([^:]+):.*@.*|\1|')
DB_PASS=$(echo $DB_URL | sed -E 's|mysql://[^:]+:([^@]+)@.*|\1|')
DB_HOST=$(echo $DB_URL | sed -E 's|mysql://.*@([^:]+):.*|\1|')
DB_PORT=$(echo $DB_URL | sed -E 's|mysql://.*@.*:([0-9]+)/.*|\1|')

echo "Creating tables in $DB_USER@$DB_HOST:$DB_PORT/$DB_NAME ..."
MYSQL_PWD="$DB_PASS" mysql -h "$DB_HOST" -P "$DB_PORT" -u "$DB_USER" "$DB_NAME" < "$script_dir/dump.sql"
count_rows "employees" 3

# Testing

echo "Creating checkpoint1..."
BACKUP_PREFIX="/testing/mysql/$unique_path/" BACKUP_NAME="checkpoint1" $script_dir/../../mysql/create.sh

run_query "DELETE FROM employees"

count_rows "employees" 0

echo "Restoring checkpoint1"
BACKUP_PREFIX="/testing/mysql/$unique_path/" BACKUP_FILE="checkpoint1.sql.gz" $script_dir/../../mysql/restore.sh

count_rows "employees" 3

echo "All tests passed"


