#!/usr/bin/env bash
# TN-02 (RNF-02) na imagem de produção: Caddy + Puma do deploy/docker-compose.prod.yml, como na VPS, só sem TLS
# (o Lighthouse não confia na CA local do Caddy). Massa `referencia`, login e2e-admin, segredos descartáveis.
# Uso (da raiz de app/, com `npm ci` feito em e2e/): e2e/support/rnf02-prod.sh <imagem-rails>
#   ex.: docker build -t cynthia-rails:rnf02 rails-app && e2e/support/rnf02-prod.sh cynthia-rails:rnf02
# Projeto compose próprio (cynthia-rnf02), porta 18080 (RNF02_PORT); derruba tudo ao sair. Nada sai da máquina.
set -euo pipefail
cd "$(dirname "$0")/../.."
APP=$PWD
IMAGE="${1:?uso: rnf02-prod.sh <imagem-rails>}"
PORT="${RNF02_PORT:-18080}"

e2e/support/env.sh >/dev/null
W="$(mktemp -d)"
cp deploy/docker-compose.prod.yml deploy/Caddyfile "$W"/
c=(docker compose -p cynthia-rnf02 --project-directory "$W" -f "$W/docker-compose.prod.yml" --env-file "$W/.env")
trap '"${c[@]}" down -v >/dev/null 2>&1 || true; rm -rf "$W"' EXIT

umask 077
{
  echo DOMAIN=http://localhost
  echo "CADDY_HTTP_PORT=$PORT"; echo CADDY_HTTPS_PORT=0
  echo "IMAGE_RAILS=$IMAGE"; echo IMAGE_WA=unused   # o wa não sobe: o Caddy só depende do rails
  echo FORCE_SSL=false; echo ASSUME_SSL=false
  echo "POSTGRES_PASSWORD=$(openssl rand -hex 12)"; echo "SECRET_KEY_BASE=$(openssl rand -hex 64)"
  echo "INTERNAL_API_TOKEN=$(openssl rand -hex 32)"
  grep -E '^ADMIN_(USERNAME|PASSWORD)=' e2e/.env.e2e
} > "$W/.env"

"${c[@]}" up -d --wait rails
"${c[@]}" up -d caddy
curl -fsS --retry 30 --retry-delay 2 --retry-all-errors -o /dev/null "http://localhost:$PORT/up"
# A seed recusa production; o grupo test do Gemfile está na imagem, então ela roda com RAILS_ENV=test no mesmo banco.
"${c[@]}" cp e2e/support/seed.rb rails:/tmp/seed.rb
"${c[@]}" exec -T -e RAILS_ENV=test rails bin/rails runner /tmp/seed.rb referencia

cd "$APP/e2e"
BASE_URL="http://localhost:$PORT" node support/lighthouse.mjs
