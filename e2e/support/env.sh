#!/bin/sh
# Gera e2e/.env.e2e (fora do git) com segredos descartáveis. Rodar da raiz de app/.
set -eu
cd "$(dirname "$0")/.."
token=$(openssl rand -hex 32)
cat > .env.e2e <<ENV
DATABASE_URL=postgres://postgres:postgres@db:5432/whatsapp_scheduler_development
REDIS_URL=redis://redis:6379/0
WA_SERVICE_URL=http://wa:3001
INTERNAL_API_TOKEN=$token
ADMIN_USERNAME=e2e-admin
ADMIN_PASSWORD=$(openssl rand -hex 16)
# Anthropic falsa servida pelo fake-wa: a chave não vale fora daqui.
ANTHROPIC_API_KEY=e2e-test-key
ANTHROPIC_BASE_URL=http://wa:3001
ENV
chmod 600 .env.e2e
echo "e2e/.env.e2e gerado"
