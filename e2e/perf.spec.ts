// TN-01 (RNF-01): p95 com a massa de referência (30 grupos, 1.500 participantes, 60 fluxos, 2.000 logs).
// Medido no ambiente de referência do PRD (Docker Compose local, Rails em development). 50 requisições por rota.
import { test, expect } from "@playwright/test";
import { login, groupId, webhook } from "./support/helpers";
import { seed, restartRails } from "./support/stack";

const p95 = (xs: number[]) => [...xs].sort((a, b) => a - b)[Math.ceil(xs.length * 0.95) - 1];

test.describe.configure({ mode: "serial" });
test.afterAll(async ({ baseURL }) => {
  seed("basico");
  await restartRails(baseURL!); // os specs seguintes partem da massa básica e do rate limit zerado
});

test("RNF-01: p95 < 500 ms no painel e < 200 ms no webhook", async ({ page, baseURL }) => {
  test.setTimeout(300_000);
  console.log(seed("referencia"));
  await login(page);
  const id = await groupId(page, "e2e-volei");
  const routes = ["/groups", `/groups/${id}`, "/logs", `/groups/${id}/flows/new?trigger=schedule`, `/groups/${id}/templates/new`];
  const results: Record<string, number> = {};
  for (const route of routes) {
    await page.request.get(route); // aquece
    const times: number[] = [];
    for (let i = 0; i < 50; i++) {
      const t = performance.now();
      const res = await page.request.get(route);
      times.push(performance.now() - t);
      expect(res.status()).toBe(200);
    }
    results[route] = Math.round(p95(times));
  }
  const hook: number[] = [];
  for (let i = 0; i < 50; i++) {
    const t = performance.now();
    const res = await webhook(page.request, { group_jid: "e2e-volei@g.us", kind: "command", message_id: `e2e-perf-${i}`, participant_jid: "5500000000001@s.whatsapp.net", text: "!e2e-inexistente" });
    hook.push(performance.now() - t);
    expect(res.status()).toBe(204);
  }
  results["POST /webhooks/whatsapp"] = Math.round(p95(hook));
  console.log("p95 (ms):", JSON.stringify(results));
  test.info().annotations.push({ type: "p95 ms", description: JSON.stringify(results) });
  for (const route of routes) expect.soft(results[route], `p95 de ${route}`).toBeLessThan(500);
  expect.soft(results["POST /webhooks/whatsapp"], "p95 do webhook").toBeLessThan(200);
});
