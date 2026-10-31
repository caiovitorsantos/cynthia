#!/usr/bin/env bash
# Server-side rollout. Usage: ./deploy.sh <image-tag>
# Pulls the images of <tag>, brings the stack up, waits for it to be healthy and, if it does not
# become healthy, goes back to the previous tag. Rolling back is the same command with the old tag:
#   ./deploy.sh "$(cat .deploy/previous)"
# Database migrations run on boot (db:prepare) and are NOT undone by a rollback: write them so the
# previous version still works (add first, remove only in a later deploy).
set -euo pipefail
cd "$(dirname "$0")"

TAG="${1:?usage: deploy.sh <image-tag>}"
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
  export TAG="$1"
  if [[ "${SKIP_PULL:-0}" != 1 ]]; then compose pull rails sidekiq wa || return 1; fi
  compose up -d --remove-orphans || return 1
  wait_healthy
}

echo "deploy: $TAG (previous: ${PREVIOUS:-none})"
if rollout "$TAG"; then
  echo "$TAG" > "$STATE/current"
  [[ -n "$PREVIOUS" && "$PREVIOUS" != "$TAG" ]] && echo "$PREVIOUS" > "$STATE/previous"
  docker image prune -f >/dev/null
  echo "deploy: $TAG is healthy"
  exit 0
fi

echo "deploy: $TAG did not become healthy" >&2
compose logs --tail 40 rails wa >&2 || true
if [[ -n "$PREVIOUS" && "$PREVIOUS" != "$TAG" ]]; then
  echo "deploy: rolling back to $PREVIOUS" >&2
  SKIP_PULL=1 rollout "$PREVIOUS" && echo "deploy: back on $PREVIOUS" >&2 || echo "deploy: ROLLBACK FAILED, check the server" >&2
fi
exit 1
