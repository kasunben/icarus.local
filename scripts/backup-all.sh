#!/usr/bin/env bash
# Full backup: all named volumes + Postgres and MariaDB dumps.
# Run manually or via cron. Output goes to ./backups/.
# Cron example: 0 3 * * * cd /path/to/icarus.local && ./scripts/backup-all.sh

set -euo pipefail

BACKUP_DIR="$(cd "$(dirname "$0")/.." && pwd)/backups"
TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

VOLUMES=(
  icarus-postgres-data
  icarus-redis-data
  icarus-nextcloud-db-data
  icarus-nextcloud-data
  icarus-nextcloud-html
  icarus-n8n-data
  icarus-garage-meta
  icarus-garage-data
  icarus-searxng-cache
  icarus-open-webui-data
  icarus-openhands-data
  icarus-changedetection-data
  icarus-pihole-data
  icarus-pihole-dnsmasq
  icarus-coding-sandbox-claude
)

echo "==> Starting backup at $TS"
echo "==> Output: $BACKUP_DIR"
echo ""

# Volume archives
for VOL in "${VOLUMES[@]}"; do
  if docker volume inspect "$VOL" &>/dev/null; then
    echo "  Backing up volume: $VOL"
    docker run --rm \
      -v "${VOL}:/data:ro" \
      -v "${BACKUP_DIR}:/backups" \
      alpine tar czf "/backups/${VOL}_${TS}.tar.gz" -C /data .
  else
    echo "  Skipping $VOL (volume does not exist)"
  fi
done

echo ""

# Postgres dumps (one per database)
if docker ps --format '{{.Names}}' | grep -q '^icarus-postgres$'; then
  for DB in icarus n8n; do
    echo "  Dumping Postgres DB: $DB"
    docker exec icarus-postgres pg_dump -U icarus "$DB" \
      | gzip > "${BACKUP_DIR}/${DB}_${TS}.sql.gz"
  done
else
  echo "  Skipping Postgres dumps (container not running)"
fi

# Nextcloud MariaDB dump
if docker ps --format '{{.Names}}' | grep -q '^icarus-nextcloud-db$'; then
  echo "  Dumping MariaDB: nextcloud"
  docker exec icarus-nextcloud-db \
    sh -c 'mysqldump -u nextcloud -p"$MYSQL_PASSWORD" nextcloud' \
    | gzip > "${BACKUP_DIR}/nextcloud_mariadb_${TS}.sql.gz"
else
  echo "  Skipping MariaDB dump (container not running)"
fi

echo ""
echo "==> Backup complete."
echo "==> Files in $BACKUP_DIR:"
ls -lh "$BACKUP_DIR"/*_"${TS}".* 2>/dev/null || true
