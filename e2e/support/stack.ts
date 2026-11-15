import { execFileSync } from "node:child_process";

// Comandos na stack E2E isolada (projeto compose próprio). Nunca toca outro projeto.
const PROJECT = process.env.E2E_PROJECT ?? "cynthia-e2e";

// Devolve a última linha do que o código imprimiu (o Sidekiq loga a conexão no stdout).
export function rails(code: string): string {
  const out = execFileSync("docker", ["compose", "-p", PROJECT, "exec", "-T", "rails", "bin/rails", "runner", code], { encoding: "utf8" });
  return out.trim().split("\n").at(-1)!.trim();
}

// Libera a janela de 20 s do SendGuard entre passos que enviam (os 20 s em si são cobertos por send_guard_spec).
export function clearThrottle() {
  execFileSync("docker", ["compose", "-p", PROJECT, "exec", "-T", "redis", "redis-cli", "DEL", "wa_scheduler:send_throttle"]);
}

// Recria a massa e2e- (perfil basico ou referencia) dentro do contêiner rails.
export function seed(profile = "basico"): string {
  execFileSync("docker", ["compose", "-p", PROJECT, "cp", new URL("./seed.rb", import.meta.url).pathname, "rails:/tmp/seed.rb"]);
  return execFileSync("docker", ["compose", "-p", PROJECT, "exec", "-T", "rails", "bin/rails", "runner", "/tmp/seed.rb", profile], { encoding: "utf8" }).trim();
}

// O rate limit do login fica no cache em memória do Puma (dev): reiniciar o rails zera.
export async function restartRails(baseURL: string) {
  execFileSync("docker", ["compose", "-p", PROJECT, "restart", "rails"]);
  for (let i = 0; i < 60; i++) {
    try { if ((await fetch(`${baseURL}/up`)).ok) return; } catch {}
    await new Promise((r) => setTimeout(r, 1000));
  }
  throw new Error("rails não voltou em 60 s");
}

// Para/sobe o wa falso (RF-03: wa-service inacessível).
export async function wa(action: "stop" | "start") {
  execFileSync("docker", ["compose", "-p", PROJECT, action, "wa"]);
  if (action === "stop") return;
  for (let i = 0; i < 30; i++) {
    try { if ((await fetch(`http://127.0.0.1:${process.env.E2E_WA_PORT ?? 3556}/health`)).ok) return; } catch {}
    await new Promise((r) => setTimeout(r, 500));
  }
}

// Zera os tetos da Cynth.ia (cynthia:*, inclusive o diário de 15) e a janela do SendGuard entre execuções.
export function resetCounters() {
  execFileSync("docker", ["compose", "-p", PROJECT, "exec", "-T", "redis", "sh", "-c",
    "redis-cli --scan --pattern 'cynthia:*' | xargs -r redis-cli del >/dev/null; redis-cli del wa_scheduler:send_throttle >/dev/null"]);
}
