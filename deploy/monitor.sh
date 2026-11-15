#!/usr/bin/env bash
# What the external /up monitor cannot see, checked on the VPS every 5 min (cron, docs/runbook.md) and reported to
# Healthchecks.io: a success ping when all is well, a /fail ping with the reasons otherwise. If the VPS, Docker or
# cron stops, the ping stops too and Healthchecks alerts by itself (dead man's switch).
#   cron:   */5 * * * *  HC_MONITOR_URL=https://hc-ping.com/<uuid> bash /home/deploy/cynthia/monitor.sh >/dev/null 2>&1
#   manual: bash monitor.sh          (prints the problems, exit 1 if any; nothing is sent without HC_MONITOR_URL)
# Needs jq on the host. Thresholds below can be overridden by environment variables.
# ponytail: shell + Healthchecks.io, no metrics stack. Upgrade path: Datadog/Grafana when someone needs graphs.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

# 15 min of Caddy access log (JSON lines) -> "<requests> <5xx> <p99 ms>". Health probes and fingerprinted assets
# are left out: they are fast and would hide a slow app.
stats() {
  jq -rRs '[split("\n")[] | fromjson? | select((.logger? // "") | startswith("http.log.access"))
            | select(.request.uri != "/up" and (.request.uri | startswith("/assets/") | not))]
           | (map(.duration) | sort) as $d
           | "\(length) \(map(select(.status >= 500)) | length) \(if length > 0 then ($d[((length * 0.99) | ceil) - 1] * 1000 | floor) else 0 end)"'
}

if [[ "${1:-}" == selftest ]]; then
  line() { printf '{"logger":"http.log.access.log0","request":{"uri":"%s"},"duration":%s,"status":%s}\n' "$@"; }
  out="$( { for _ in $(seq 1 98); do line /groups 0.1 200; done; line /logs 3.5 500; line /logs 3.0 502
            line /up 9 500; line /assets/a.css 9 200; echo '{"logger":"http","msg":"not access"}'; echo 'not json'; } | stats)"
  [[ "$out" == "100 2 3000" ]] || { echo "selftest: expected '100 2 3000', got '$out'" >&2; exit 1; }
  [[ "$(true | stats)" == "0 0 0" ]] || { echo "selftest: empty log" >&2; exit 1; }
  echo "selftest: ok"; exit 0
fi

compose() { docker compose -f docker-compose.prod.yml --env-file .env "$@"; }
problems=()

# Containers: anything stopped, restarting or unhealthy (db and redis have no other signal here).
bad="$(compose ps --all --format '{{.Service}} {{.State}} {{.Health}}' 2>&1 | awk '$2 != "running" || $3 == "unhealthy"')"
[[ -z "$bad" ]] || problems+=("containers: $(tr '\n' ';' <<< "$bad")")

# WhatsApp session. A dropped connection comes back alone within 60 s (RNF-05b), so look again before alerting.
wa_status() { compose exec -T wa curl -fsS -m 5 http://localhost:3001/health 2>/dev/null | jq -r .status 2>/dev/null; }
wa="$(wa_status)"
[[ "$wa" == connected ]] || { sleep "${WA_RECHECK_SECONDS:-75}"; wa="$(wa_status)"; }
[[ "$wa" == connected ]] || problems+=("whatsapp: ${wa:-no answer} (qr_pending = pair again at /connection)")

# Error rate and p99 (symptoms, from what users got through Caddy).
read -r total errors p99 < <(compose logs caddy --since 15m --no-log-prefix 2>/dev/null | stats)
total="${total:-0}" errors="${errors:-0}" p99="${p99:-0}"
if (( errors >= ${MIN_ERRORS:-5} && errors * 100 >= total * ${MAX_ERROR_PCT:-5} )); then
  problems+=("5xx: $errors of $total requests in 15 min")
fi
if (( total >= ${MIN_REQUESTS_P99:-20} && p99 > ${MAX_P99_MS:-2000} )); then
  problems+=("p99: $p99 ms over $total requests in 15 min")
fi

# Saturation of the job queue: routines must leave within 90 s (RNF-03). Sidekiq pushes left, works from the right.
oldest="$(compose exec -T redis redis-cli LINDEX queue:default -1 2>/dev/null)"
if [[ -n "$oldest" ]]; then
  enq="$(jq -r '.enqueued_at | if . > 100000000000 then . / 1000 else . end | floor' <<< "$oldest" 2>/dev/null || echo 0)"
  lag=$(( $(date +%s) - ${enq:-0} ))
  (( enq == 0 || lag <= ${MAX_QUEUE_LAG_SECONDS:-120} )) || problems+=("sidekiq: oldest job waiting ${lag}s")
fi

# Disk (Docker data, logs and local backups all live on /).
disk="$(df --output=pcent / | tail -1 | tr -dc 0-9)"
(( disk < ${MAX_DISK_PCT:-85} )) || problems+=("disk: ${disk}% used")

# Backup: backup.sh touches last-ok only when the dump, the WhatsApp archive and the remote copy all worked.
backup_ok="${BACKUP_DIR:-/var/backups/cynthia}/last-ok"
[[ -n "$(find "$backup_ok" -mmin -$((26 * 60)) 2>/dev/null)" ]] || problems+=("backup: no successful backup in 26 h ($backup_ok)")

if (( ${#problems[@]} == 0 )); then
  msg="ok: wa connected, $total req, $errors 5xx, p99 ${p99}ms, disk ${disk}%"
  echo "$msg"
  [[ -z "${HC_MONITOR_URL:-}" ]] || curl -fsS -m 10 --retry 3 --data-raw "$msg" "$HC_MONITOR_URL" >/dev/null
  exit 0
fi
msg="$(printf '%s\n' "${problems[@]}")"
echo "$msg" >&2
[[ -z "${HC_MONITOR_URL:-}" ]] || curl -fsS -m 10 --retry 3 --data-raw "$msg" "$HC_MONITOR_URL/fail" >/dev/null
exit 1
