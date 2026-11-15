// wa-service real (imagem de wa-service/Dockerfile), sem rede (--network none): nunca fala com o WhatsApp.
// RF-22 do lado do wa-service: token interno obrigatório e /send desconectado = 503 not_connected (TC-22, TM-15).
import { test, expect } from "@playwright/test";
import { execFileSync } from "node:child_process";

const NAME = "cynthia-e2e-wa-real";
const docker = (...args: string[]) => execFileSync("docker", args, { encoding: "utf8" }).trim();
const call = (path: string, token: string | null, body?: object) => docker("exec", NAME, "node", "-e",
  `fetch("http://localhost:3001${path}", { method: ${body ? '"POST"' : '"GET"'}, headers: { "content-type": "application/json"${token === null ? "" : `, Authorization: ${JSON.stringify(token)}`} }${body ? `, body: ${JSON.stringify(JSON.stringify(body))}` : ""} })` +
  `.then(async (r) => console.log(r.status, await r.text()))`);

test.beforeAll(() => {
  test.setTimeout(300_000);
  docker("build", "-q", "-t", NAME, new URL("../wa-service", import.meta.url).pathname);
  try { docker("rm", "-f", NAME); } catch {}
  docker("run", "-d", "--name", NAME, "--network", "none", "-e", "INTERNAL_API_TOKEN=e2e-token-wa", "-e", "RAILS_WEBHOOK_URL=http://127.0.0.1:9/x", NAME);
});
test.afterAll(() => { docker("rm", "-f", NAME); });

test("RF-22: wa-service real recusa sem token e responde 503 not_connected no /send desconectado", async () => {
  await expect.poll(() => { try { return call("/health", null); } catch { return ""; } }, { timeout: 60_000, intervals: [1000] }).toMatch(/^200 /);
  expect(call("/health", null)).not.toMatch(/"connected":true/);
  expect(call("/groups", null)).toMatch(/^401 /);
  expect(call("/send", "e2e-token-errado", { group_jid: "e2e@g.us", message: "x" })).toMatch(/^401 /);
  expect(call("/send", "e2e-token-wa", { group_jid: "e2e@g.us", message: "x" })).toBe('503 {"error":"not_connected"}');
});
