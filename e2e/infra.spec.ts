// Checagens estáticas de infra (sem navegador): RNF-05a, TM-10, TM-14, TM-16 a TM-20, TM-24.
// Lê o compose resolvido (docker compose config) e os arquivos versionados; não sobe nada.
import { test, expect } from "@playwright/test";
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";

const root = new URL("../", import.meta.url).pathname;
const read = (path: string) => readFileSync(root + path, "utf8");
const compose = (args: string[], env: Record<string, string> = {}) =>
  JSON.parse(execFileSync("docker", ["compose", ...args, "config", "--no-env-resolution", "--format", "json"], {
    cwd: root, encoding: "utf8", env: { PATH: process.env.PATH!, HOME: process.env.HOME!, ...env },
  }));

// Dev: interpolação pelo env do E2E (nunca o app/.env real).
const dev = () => compose(["--env-file", "e2e/.env.e2e", "-f", "docker-compose.yml"]).services;
// Produção com valores fictícios e2e- (o .env de produção não existe no repositório).
const prodEnv = { DOMAIN: "e2e.example.invalid", IMAGE_RAILS: "e2e/rails", IMAGE_WA: "e2e/wa", TAG: "e2e", POSTGRES_PASSWORD: "e2e-senha", INTERNAL_API_TOKEN: "e2e-token" };
const prod = () => compose(["--project-directory", "deploy", "-f", "deploy/docker-compose.prod.yml"], prodEnv).services;
const usesPinned = (yml: string) => [...yml.matchAll(/uses:\s*([^\s#]+)/g)].map((m) => m[1]).filter((u) => !/@[0-9a-f]{40}$/.test(u));

test("TN-05a (RNF-05a): todo serviço de longa duração do compose de dev com restart unless-stopped", () => {
  const services = dev();
  const wrong = Object.entries(services).filter(([, s]: any) => s.restart !== "unless-stopped").map(([n]) => n);
  expect(wrong).toEqual([]);
  expect(Object.keys(services).sort()).toEqual(["db", "rails", "redis", "sidekiq", "wa"]);
});

test("TM-14/TM-10: wa de dev sem porta publicada e só com INTERNAL_API_TOKEN e RAILS_WEBHOOK_URL", () => {
  const { wa } = dev();
  expect(wa.ports ?? []).toEqual([]);
  expect(wa.env_file ?? []).toEqual([]);
  expect(Object.keys(wa.environment ?? {}).sort()).toEqual(["INTERNAL_API_TOKEN", "RAILS_WEBHOOK_URL"]);
});

test("TM-17 (residual de dev): porta do rails de dev só no loopback", () => {
  const { rails } = dev();
  expect(rails.ports.map((p: any) => p.host_ip)).toEqual(["127.0.0.1"]);
});

test("TM-16/TM-17/TM-10: compose de produção válido, só o caddy publica portas, wa isolado, HSTS e force_ssl", () => {
  const services = prod(); // sai com código 0 ou lança
  const withPorts = Object.entries(services).filter(([, s]: any) => (s.ports ?? []).length).map(([n]) => n);
  expect(withPorts).toEqual(["caddy"]);
  expect(services.wa.env_file ?? []).toEqual([]);
  // Config do tracer do Datadog (ADR-012) não é segredo; a chave da API não pode chegar ao wa.
  const tracer = ["DD_AGENT_HOST", "DD_ENV", "DD_SERVICE", "DD_TRACE_ENABLED", "DD_VERSION", "NODE_OPTIONS"];
  const waEnv = Object.keys(services.wa.environment).filter((k) => !tracer.includes(k)).sort();
  expect(waEnv).toEqual(["INTERNAL_API_TOKEN", "RAILS_WEBHOOK_URL"]);
  const caddy = read("deploy/Caddyfile");
  expect([...caddy.matchAll(/reverse_proxy\s+(\S+)/g)].map((m) => m[1])).toEqual(["rails:80"]);
  expect(caddy).toMatch(/Strict-Transport-Security\s+"max-age=\d+/);
  const prodRb = read("rails-app/config/environments/production.rb");
  expect(prodRb).toMatch(/config\.assume_ssl = ENV\.fetch\("ASSUME_SSL", "true"\)/);
  expect(prodRb).toMatch(/config\.force_ssl = ENV\.fetch\("FORCE_SSL", "true"\)/);
});

test("TM-18: imagens de produção sem root e sem modo dev", () => {
  const wa = read("wa-service/Dockerfile.prod");
  expect(wa).toMatch(/^USER node$/m);
  expect(wa).toMatch(/^CMD \["node", "dist\/server\.js"\]$/m);
  expect(wa).not.toMatch(/tsx watch/);
  expect(read(".github/workflows/deploy.yml")).toMatch(/context: wa-service\s+file: wa-service\/Dockerfile\.prod/);
  expect(read("rails-app/Dockerfile")).toMatch(/^USER 1000:1000$/m);
});

test("TM-19/TM-24: deploy.yml só por Run workflow a partir da main, com CI verde no commit", () => {
  const yml = read(".github/workflows/deploy.yml");
  expect(yml).toMatch(/^permissions: \{\}$/m);
  // ADR-010 (revisão 2026-11-15): sem gatilho automático; o clique do dono é a aprovação.
  expect(yml).not.toMatch(/^\s*workflow_run:/m);
  const build = yml.slice(yml.indexOf("  build:"), yml.indexOf("  deploy:"));
  expect(build).toContain("gh run list -R \"$GITHUB_REPOSITORY\" -w CI -c \"$SHA\" -e push");
  const deploy = yml.slice(yml.indexOf("  deploy:"));
  expect(deploy).toMatch(/needs: build/);
  expect(deploy).toMatch(/needs\.build\.result == 'success'/);
  expect(deploy).toMatch(/needs\.build\.result == 'skipped' && github\.event_name == 'workflow_dispatch'/);
  // TM-24: cada condição com workflow_dispatch exige a main
  const dispatchConds = [...yml.matchAll(/github\.event_name == 'workflow_dispatch'[^)]*\)/g)].map((m) => m[0]);
  expect(dispatchConds.length).toBe(2);
  for (const c of dispatchConds) expect(c).toContain("github.ref == 'refs/heads/main'");
  expect(usesPinned(yml)).toEqual([]);
});

test("TM-20: ci.yml com permissões mínimas e actions fixadas por SHA", () => {
  const yml = read(".github/workflows/ci.yml");
  expect(yml).toMatch(/^permissions: \{\}$/m);
  const jobs = yml.slice(yml.indexOf("\njobs:")).split(/\n  (?=[a-z_]+:\n)/).slice(1);
  expect(jobs.length).toBeGreaterThan(0);
  for (const job of jobs) expect(job, `job sem permissions: ${job.split("\n")[0]}`).toMatch(/\n    permissions:\n      contents: read/);
  expect(usesPinned(yml)).toEqual([]);
});
