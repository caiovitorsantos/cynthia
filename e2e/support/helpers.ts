import { readFileSync } from "node:fs";
import { expect, type Page, type APIRequestContext } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const file = new URL("../.env.e2e", import.meta.url);
export const env: Record<string, string> = Object.fromEntries(
  readFileSync(file, "utf8").split("\n").filter((l) => /^\w+=/.test(l)).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]),
);
export const WA = `http://127.0.0.1:${process.env.E2E_WA_PORT ?? 3556}`;

export async function waState(request: APIRequestContext, status: "qr_pending" | "connected" | "disconnected") {
  await request.post(`${WA}/__state`, { data: { status } });
}
export async function waLog(request: APIRequestContext) {
  return (await request.get(`${WA}/__log`)).json() as Promise<{ sent: any[]; left: { group_jid: string; at: number }[]; anthropic: any[] }>;
}
export async function waReset(request: APIRequestContext) {
  await request.post(`${WA}/__reset`);
}

export async function login(page: Page) {
  await page.goto("/login");
  await page.getByLabel(/usu[aá]rio|user/i).fill(env.ADMIN_USERNAME);
  await page.getByLabel(/senha|password|contrase/i).fill(env.ADMIN_PASSWORD);
  await page.getByRole("button", { name: /entrar|sign in|iniciar/i }).click();
  await expect(page).toHaveURL(/\/groups/);
}

export async function webhook(request: APIRequestContext, data: Record<string, unknown>, token = env.INTERNAL_API_TOKEN) {
  return request.post("/webhooks/whatsapp", { data, headers: { Authorization: token } });
}

// RNF-04: zero violações serious/critical nas tags WCAG 2.1 A/AA.
export async function axe(page: Page, label: string, include?: string) {
  const builder = new AxeBuilder({ page });
  if (include) builder.include(include);
  const { violations } = await builder.withTags(["wcag2a", "wcag2aa", "wcag21a", "wcag21aa"]).analyze();
  const bad = violations.filter((v) => v.impact === "serious" || v.impact === "critical");
  const summary = bad.map((v) => `${v.id} (${v.impact}): ${v.nodes.slice(0, 3).map((n) => n.target.join(" ")).join(" | ")}`);
  expect.soft(summary, `axe em ${label}`).toEqual([]);
}

export async function noHorizontalScroll(page: Page, label: string) {
  const [scroll, width] = await page.evaluate(() => [document.documentElement.scrollWidth, window.innerWidth]);
  expect.soft(scroll, `rolagem horizontal em ${label} (scrollWidth ${scroll} > ${width})`).toBeLessThanOrEqual(width);
}

export async function groupId(page: Page, name: string) {
  await page.goto("/groups");
  const href = await page.getByRole("link", { name, exact: true }).first().getAttribute("href");
  return Number(href!.split("/").pop());
}

export async function anthropicQueue(request: APIRequestContext, replies: unknown[]) {
  await request.post(`${WA}/__anthropic`, { data: { replies } });
}

// RF-29/TM-01: nada de telefone (DDD 00 da massa), JID de participante nem valor de variável no que vai à Anthropic.
export function piiIn(bodies: unknown[]): string[] {
  const text = JSON.stringify(bodies);
  return [/5500000000\d{3}/g, /@s\.whatsapp\.net/g, /e2e-pix@example\.invalid/g].flatMap((re) => text.match(re) ?? []);
}
