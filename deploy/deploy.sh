#!/usr/bin/env bash
# Server-side rollout. Usage: ./deploy.sh <rails-image@sha256:...> <wa-image@sha256:...>
# Images go by digest only (G10): the exact bytes the trivy scanned in the pipeline, never a tag that can move.
# Pulls the release, brings the stack up, waits for it to be healthy and, if it does not become healthy,
# goes back to the previous release. Rolling back is the same command with the old release:
#   ./deploy.sh $(cat .deploy/previous)
# Database migrations run on boot (db:prepare) and are NOT undone by a rollback: write them so the
# previous version still works (add first, remove only in a later deploy).
set -euo pipefail
cd "$(dirname "$0")"

usage="usage: deploy.sh <rails-image@sha256:...> <wa-image@sha256:...>"
RAILS_REF="${1:?$usage}"
WA_REF="${2:?$usage}"
for ref in "$RAILS_REF" "$WA_REF"; do
  [[ "$ref" =~ ^[a-z0-9._/:-]+@sha256:[0-9a-f]{64}$ ]] || { echo "deploy: '$ref' is not an image pinned by digest" >&2; exit 1; }
done
RELEASE="$RAILS_REF $WA_REF"
STATE=.deploy
mkdir -p "$STATE"
PREVIOUS="$(cat "$STATE/current" 2>/dev/null || true)"

compose() { docker compose -f docker-compose.prod.yml --env-file .env "$@"; }

wait_healthy() {
  local deadline=$((SECONDS + ${HEALTH_TIMEOUT:-180}))
  until compose exec -T rails curl -fsS http://localhost:80/up >/dev/null 2>&1 \
     && compose exec -T wa curl -fsS http://localhost:3001/health >/dev/null 2>&1; do
    (( SECONDS < deadline )) || return 1
    sleep 3
  done
}

# Called inside `if`, where `set -e` does not apply: every step has to fail the function by itself.
rollout() {
  export IMAGE_RAILS="$1" IMAGE_WA="$2"
  # A digest never changes, so an image already on disk is the right one: no pull, no registry login needed (A-09:
  # the GHCR token of the deploy job expires with the job, and the packages are private).
  if [[ "${SKIP_PULL:-0}" != 1 ]] && ! docker image inspect "$1" "$2" >/dev/null 2>&1; then
    compose pull rails sidekiq wa || return 1
  fi
  compose up -d --remove-orphans || return 1
  wait_healthy
}

echo "deploy: $RELEASE (previous: ${PREVIOUS:-none})"
# Migrations run on boot and some only touch data (e.g. 20261031140000 deletes the chat history): the rollback
# cannot bring that back, the backup taken here can. Skipped on the first deploy (no database yet).
if [[ -n "$PREVIOUS" && "$PREVIOUS" != "$RELEASE" && "${SKIP_BACKUP:-0}" != 1 ]]; then
  ./backup.sh || { echo "deploy: pre-deploy backup failed, nothing changed" >&2; exit 1; }
fi
if rollout "$RAILS_REF" "$WA_REF"; then
  echo "$RELEASE" > "$STATE/current"
  [[ -n "$PREVIOUS" && "$PREVIOUS" != "$RELEASE" ]] && echo "$PREVIOUS" > "$STATE/previous"
  # Images pulled by digest have no tag, so `image prune` sees them as dangling and deleted the previous release,
  # breaking `./deploy.sh $(cat .deploy/previous)` (A-09). A local tag (never used to deploy) keeps both releases.
  read -r -a cur <<< "$RELEASE"
  docker tag "${cur[0]}" cynthia-keep:current-rails && docker tag "${cur[1]}" cynthia-keep:current-wa
  if [[ -n "$PREVIOUS" && "$PREVIOUS" != "$RELEASE" ]]; then
    read -r -a prev <<< "$PREVIOUS"
    docker tag "${prev[0]}" cynthia-keep:previous-rails && docker tag "${prev[1]}" cynthia-keep:previous-wa \
      || echo "deploy: previous release is not on disk; rolling back to it will pull it (needs: docker login ghcr.io)" >&2
  fi
  docker image prune -f >/dev/null
  # History for the runbook (G1/G10): when, how long, which release. Who approved is in GitHub > Deployments.
  echo "$(date -u +%FT%TZ) healthy ${SECONDS}s $RELEASE" >> "$STATE/history"
  echo "deploy: $RELEASE is healthy (${SECONDS}s)"
  exit 0
fi

echo "deploy: $RELEASE did not become healthy" >&2
compose logs --tail 40 rails wa >&2 || true
if [[ -n "$PREVIOUS" && "$PREVIOUS" != "$RELEASE" ]]; then
  echo "deploy: rolling back to $PREVIOUS" >&2
  read -r -a prev <<< "$PREVIOUS"
  if SKIP_PULL=1 rollout "${prev[0]}" "${prev[1]}"; then
    echo "$(date -u +%FT%TZ) rolled-back ${SECONDS}s $PREVIOUS (failed: $RELEASE)" >> "$STATE/history"
    echo "deploy: back on $PREVIOUS (${SECONDS}s)" >&2
  else
    echo "$(date -u +%FT%TZ) ROLLBACK-FAILED ${SECONDS}s $RELEASE" >> "$STATE/history"
    echo "deploy: ROLLBACK FAILED, check the server" >&2
  fi
fi
exit 1
