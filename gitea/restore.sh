#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status
set -e

# --- CONFIGURATION ---
DB_CONTAINER_NAME="gitea_db"
GITEA_CONTAINER_NAME="gitea"
DB_USER="gitea"
DB_NAME="gitea"
# The data volume usually takes the current folder name as a prefix
GITEA_DATA_VOLUME="${PWD##*/}_gitea_data" 

# --- ARGUMENT CHECK ---
if [ -z "$1" ]; then
    echo "Error: Missing backup file path."
    echo "Usage: ./restore.sh /path/to/backup-filename.zip"
    echo "Example: ./restore.sh ../downloads/gitea-dump-2026-06-09.zip"
    exit 1
fi

USER_PROVIDED_PATH="$1"

# --- VALIDATE BACKUP EXISTS ---
if [ ! -f "$USER_PROVIDED_PATH" ]; then
    echo "Error: Backup file not found at '$USER_PROVIDED_PATH'"
    exit 1
fi

# --- PATH RESOLUTION FOR DOCKER ---
# Docker requires absolute paths for bind mounts. This safely converts 
# relative paths (e.g., ./file.zip or ../file.zip) into absolute ones.
BACKUP_DIR=$(cd "$(dirname "$USER_PROVIDED_PATH")" && pwd)
BACKUP_FILE=$(basename "$USER_PROVIDED_PATH")

# --- SAFETY WARNING ---
echo "================================================================="
echo "WARNING: This script will OVERWRITE your existing Gitea data!"
echo "Target Backup: $BACKUP_DIR/$BACKUP_FILE"
echo "================================================================="
read -p "Are you absolutely sure you want to proceed? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Restore cancelled by user."
    exit 1
fi

# --- STEP 1: Stop the Gitea Application ---
echo "--> Stopping Gitea application container (keeping database alive)..."
docker compose stop gitea

# Ensure the database container is actually running
if [ "$(docker inspect -f '{{.State.Running}}' $DB_CONTAINER_NAME 2>/dev/null)" != "true" ]; then
    echo "--> Starting database container..."
    docker compose start db
    echo "Waiting for database to be healthy..."
    until [ "$(docker inspect --format='{{.State.Health.Status}}' $DB_CONTAINER_NAME)" = "healthy" ]; do
        sleep 1
    done
fi

# --- STEP 2: Extract & Process Backup Files ---
echo "--> Creating temporary workspace..."
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT # Ensures cleanup of temp files even if script fails

echo "--> Extracting backup file..."
# Mounts the dynamically resolved absolute directory to the container
docker run --rm \
  -v "$BACKUP_DIR:/backup:ro" \
  -v "$TEMP_DIR:/extract" \
  alpine:latest sh -c "apk add --no-cache unzip && unzip -q /backup/$BACKUP_FILE -d /extract"

if [ ! -f "$TEMP_DIR/gitea-db.sql" ]; then
    echo "Error: Backup file appears invalid (gitea-db.sql missing)."
    exit 1
fi

# --- STEP 3: Clear and Restore Database ---
echo "--> Wiping existing database schema..."
docker exec -i "$DB_CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" -c \
  "DROP SCHEMA public CASCADE; CREATE SCHEMA public; GRANT ALL ON SCHEMA public TO $DB_USER;"

echo "--> Importing backup SQL into database..."
docker exec -i "$DB_CONTAINER_NAME" psql -U "$DB_USER" -d "$DB_NAME" < "$TEMP_DIR/gitea-db.sql"

# --- STEP 4: Restore Data and Repositories ---
echo "--> Restoring file volumes..."
docker run --rm \
  -v "$GITEA_DATA_VOLUME:/live_data" \
  -v "$TEMP_DIR:/backup_data:ro" \
  alpine:latest sh -c "
    apk add --no-cache rsync &&
    mkdir -p /live_data/gitea/conf /live_data/git/repositories &&
    rsync -a --delete /backup_data/data/ /live_data/gitea/ &&
    rsync -a --delete /backup_data/repos/ /live_data/git/repositories/ &&
    cp /backup_data/app.ini /live_data/gitea/conf/app.ini &&
    chown -R 1000:1000 /live_data
  "

# --- STEP 5: Restart everything ---
echo "--> Restarting all Gitea services..."
docker compose down
docker compose up -d

echo "================================================================="
echo " SUCCESS: Gitea has been restored from: $BACKUP_FILE"
echo "================================================================="
