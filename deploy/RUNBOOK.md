# Deploy do Cynthia: runbook

Uma VPS com Docker Compose. Caddy na frente (TLS automático), Rails, Sidekiq, serviço do WhatsApp,
Postgres e Redis na rede interna. Decisão e alternativas: `docs/adr/010-deploy-vps-compose-operado.md`.

```
Run workflow na main (só o dono: é a aprovação) ─ CI verde no commit ─▶ build + trivy ─▶ GHCR (digest)
        ─▶ SSH na VPS: deploy.sh <rails@sha256> <wa@sha256> ─▶ saúde ok? sim: fica · não: volta para a anterior ─▶ smoke https://DOMINIO/up
```

## 1. A máquina

- Ubuntu 24.04 LTS, **2 vCPU, 4 GB de RAM, 40 GB de SSD** (Rails + Sidekiq + Postgres + Redis + Node cabem com folga).
- Região próxima do Brasil, porque o número de WhatsApp conecta a partir dela. Ative o snapshot semanal do provedor.
- Um domínio com registro `A` apontando para o IP da VPS.

## 2. Preparar o servidor (uma vez)

```bash
# como root, no primeiro acesso
adduser --disabled-password --gecos "" deploy
mkdir -p /home/deploy/.ssh && cp ~/.ssh/authorized_keys /home/deploy/.ssh/ && chown -R deploy:deploy /home/deploy/.ssh
# desligue o login por senha e o login do root: PasswordAuthentication no / PermitRootLogin no (em /etc/ssh/sshd_config)

ufw allow 22 && ufw allow 80 && ufw allow 443 && ufw --force enable
curl -fsSL https://get.docker.com | sh && usermod -aG docker deploy
apt-get install -y unattended-upgrades
```

O grupo `docker` equivale a root na máquina: use um usuário só para o deploy e uma chave SSH só para isso.

Como `deploy`, crie a pasta e o `.env` (veja `.env.production.example`; `chmod 600`):

```bash
mkdir -p ~/cynthia && cd ~/cynthia
cp .env.production.example .env   # depois do primeiro deploy (os arquivos chegam pelo pipeline), ou crie o .env à mão
```

## 3. Configurar o GitHub (uma vez)

1. Gere a chave do deploy: `ssh-keygen -t ed25519 -f deploy_key -C cynthia-deploy`. A pública vai para `~deploy/.ssh/authorized_keys` na VPS.
2. `ssh-keyscan -t ed25519 IP_DA_VPS` gera o `known_hosts`: confira a impressão digital com a do painel do provedor.
3. A aprovação é o próprio **Run workflow**: o deploy não tem gatilho automático e só quem tem escrita no repositório (o dono) pode dispará-lo (ADR-010, revisão 2026-11-15). Num repositório privado do GitHub Free não há revisor obrigatório em environment; o environment `production` fica só como registro (GitHub → Deployments).
4. Crie os **secrets de repositório** (Settings → Secrets and variables → Actions) `DEPLOY_HOST`, `DEPLOY_USER` (`deploy`), `DEPLOY_SSH_KEY` (a privada) e `DEPLOY_KNOWN_HOSTS`, e a **variable** `DOMAIN`. De repositório porque segredo de environment em repositório privado exige GitHub Pro ou superior. Não dê escrita no repositório a mais ninguém sem rever isso: quem tem escrita pode implantar.
5. Em **Settings → Actions → General**: workflows com permissão de leitura por padrão.
6. Apague a chave privada local depois de cadastrar.

## 4. Deploy normal

Merge na `main` → espere o **CI** ficar verde → **Actions → Deploy → Run workflow** (branch `main`, digests vazios): confere que o CI daquele commit passou, constrói e varre as imagens, faz o rollout → testa `https://DOMINIO/up`. Merge sozinho não implanta nada.
Antes de trocar as imagens, o `deploy.sh` roda o `backup.sh` (as migrations rodam no boot, pelo `db:prepare`, e algumas só mexem em dados: a `20261031140000` apaga o histórico do chat). Se o backup falhar, nada muda e o deploy para; por isso `/var/backups/cynthia` (seção 7) precisa existir antes do primeiro deploy com versão anterior. Pular o backup só com `SKIP_BACKUP=1`, conscientemente.
Se a versão nova não ficar saudável em 3 minutos (`/up` do Rails e `/health` do wa), o `deploy.sh` volta sozinho para a anterior e o workflow falha.

## 5. Rollback

- Pelo GitHub: **Actions → Deploy → Run workflow** com os digests antigos em `rails_digest` e `wa_digest` (`sha256:...`; estão no resumo do run de build que os publicou e em `~/cynthia/.deploy/current` e `previous`). Tag não serve: o deploy só aceita digest.
- Pela VPS: `cd ~/cynthia && ./deploy.sh $(cat .deploy/previous)` (sem aspas: o arquivo tem as duas referências). Não precisa de login no GHCR: o `deploy.sh` guarda a release atual e a anterior no disco (tags locais `cynthia-keep:*`) e só puxa o que não está lá. Uma release mais antiga que a anterior precisa de `docker login ghcr.io` com um token `read:packages`, ou do caminho pelo GitHub.
- Rails, Sidekiq e wa são **uma release** (par de digests) e voltam juntos (S-07: o Rails novo espera o `from_me` do wa novo). Nunca troque a imagem de um só serviço à mão.
- Ensaio local em 2026-11-15 (registro local, por digest): wa quebrado de propósito → rollback automático, os três serviços de volta na release anterior; rollback manual por `.deploy/previous` → saudável.
- **As migrations não voltam.** Dado apagado ou alterado por migration volta só pelo backup tirado no início do deploy (seção 7). Escreva-as para a versão anterior continuar funcionando (adicionar coluna agora, remover só num deploy seguinte).

## 6. WhatsApp

Depois do primeiro deploy, abra `https://DOMINIO/connection` e leia o QR com o celular. A sessão fica no volume `wa_auth` (e no backup). Se o volume se perder, o número precisa ser pareado de novo.

## 7. Backup e restauração

Agende `backup.sh` (Postgres + sessão do WhatsApp) no cron do usuário `deploy`:

```
0 3 * * *  cd /home/deploy/cynthia && ./backup.sh >> /home/deploy/cynthia/backup.log 2>&1
*/5 * * * *  HC_MONITOR_URL=https://hc-ping.com/SEU-UUID bash /home/deploy/cynthia/monitor.sh >/dev/null 2>&1
```

A segunda linha é o monitor (`monitor.sh`, precisa de `jq` no host): WhatsApp desconectado, contêiner parado, taxa de 5xx, p99, fila do Sidekiq, disco e backup sem sucesso há 26 h, avisando pelo Healthchecks.io. O backup só conta como feito quando grava `last-ok`; o monitor alerta sem ele. Detalhes, limiares e ações: `docs/runbook.md` do projeto.

Guarda 14 dias em `/var/backups/cynthia` (crie a pasta com dono `deploy`). Para copiar para fora da máquina, instale o `rclone`, configure um remoto com `crypt` e ponha `BACKUP_REMOTE=nome:pasta` no `.env`. **Backup só na própria VPS não é backup.**

Restaurar o banco (num banco novo, para conferir antes de trocar):

```bash
docker compose -f docker-compose.prod.yml --env-file .env exec -T db createdb -U cynthia restauracao
docker compose -f docker-compose.prod.yml --env-file .env exec -T db pg_restore -U cynthia -d restauracao --no-owner < db-AAAAMMDDTHHMMSSZ.dump
```

Restaurar a sessão do WhatsApp: pare o serviço `wa`, extraia o `.tgz` no volume (`docker run --rm -v cynthia_wa_auth:/data -v $PWD:/in alpine tar xzf /in/wa_auth-....tgz -C /data`) e suba de novo.
**Teste a restauração a cada trimestre** e anote a data aqui.

## 8. Monitoramento e logs

- Alerta externo: um monitor (UptimeRobot, Better Stack ou Healthchecks.io) chamando `https://DOMINIO/up` a cada minuto, avisando por e-mail.
- Logs: `docker compose -f docker-compose.prod.yml --env-file .env logs -f rails wa` (rotação de 10 MB × 5 arquivos por serviço).
- Estado: `docker compose ... ps`.

## 9. Manutenção

- Atualizações de segurança do sistema: automáticas (`unattended-upgrades`); reinicie a VPS quando o aviso de reboot aparecer.
- Imagens base (`postgres:16`, `redis:7`, `caddy:2`): fixadas por digest no `docker-compose.prod.yml`; o Dependabot abre o PR com o digest novo (só minor/patch) e o deploy seguinte aplica. Major (ex.: Postgres 17) é migração planejada (dump/restore), não PR.
- Rotação de segredos: edite o `.env` e rode `./deploy.sh $(cat .deploy/current)`.

## Limites conhecidos

- Uma única máquina: se ela cair, o serviço cai até o restore ou a recriação. É aceitável para um painel de admin único; metas de disponibilidade (RNF-05) ainda não foram definidas.
- O WhatsApp exige instância única do serviço `wa`: não escale horizontalmente.
