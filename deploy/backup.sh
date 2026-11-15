#!/usr/bin/env bash
# Backup of what cannot be rebuilt: the Postgres data and the WhatsApp session (wa_auth).
# Run by cron on the host (see RUNBOOK.md). Keeps 14 days locally; if BACKUP_REMOTE is set (an rclone
# remote, ideally with `crypt`), also copies there. wa_auth holds WhatsApp credentials: protect the
# backups like secrets (this script writes them with mode 600 inside a 700 directory).
set -euo pipefail
cd "$(dirname "$0")"
set -a; [[ -f .env ]] && . ./.env; set +a

OUT="${BACKUP_DIR:-/var/backups/cynthia}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
umask 077
mkdir -p "$OUT"

docker compose -f docker-compose.prod.yml --env-file .env exec -T db pg_dump -U cynthia -Fc cynthia > "$OUT/db-$STAMP.dump"
# The archive is written as this user, mode 600 (it holds the WhatsApp credentials).
docker run --rm -e OWNER="$(id -u):$(id -g)" -e STAMP="$STAMP" -v "${COMPOSE_PROJECT_NAME:-cynthia}_wa_auth:/data:ro" -v "$OUT":/out alpine \
  sh -c 'umask 077 && tar czf "/out/wa_auth-$STAMP.tgz" -C /data . && chown "$OWNER" "/out/wa_auth-$STAMP.tgz"'

# A dump that is empty or that pg_restore cannot read is not a backup.
[[ -s "$OUT/db-$STAMP.dump" ]] || { echo "backup: empty database dump" >&2; exit 1; }
docker compose -f docker-compose.prod.yml --env-file .env exec -T db pg_restore --list < "$OUT/db-$STAMP.dump" >/dev/null

find "$OUT" -type f \( -name 'db-*.dump' -o -name 'wa_auth-*.tgz' \) -mtime +14 -delete

if [[ -n "${BACKUP_REMOTE:-}" ]]; then
  command -v rclone >/dev/null || { echo "backup: BACKUP_REMOTE is set but rclone is not installed" >&2; exit 1; }
  rclone copy "$OUT" "$BACKUP_REMOTE" --include 'db-*.dump' --include 'wa_auth-*.tgz'
fi
echo "backup: $STAMP ok"
