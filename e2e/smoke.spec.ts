// Smoke de launch: BASE_URL=https://<painel> SMOKE_USER=... SMOKE_PASSWORD=... npx playwright test smoke.spec.ts
// Só leitura: /up, login, status do WhatsApp no modal e logout. Sem BASE_URL roda contra a stack E2E (sanidade).
import { test, expect } from "@playwright/test";
import { env } from "./support/helpers";

test("smoke: /up, login, status do WhatsApp e logout", async ({ page, request }) => {
  expect((await request.get("/up")).status()).toBe(200);
  await page.goto("/login");
  await page.getByLabel(/usuário|user/i).fill(process.env.SMOKE_USER ?? env.ADMIN_USERNAME);
  await page.getByLabel(/senha|password|contrase/i).fill(process.env.SMOKE_PASSWORD ?? env.ADMIN_PASSWORD);
  await page.getByRole("button", { name: /entrar|sign in|iniciar/i }).click();
  await expect(page).toHaveURL(/\/groups/);
  await page.locator("header button[aria-haspopup=dialog]").click();
  await expect(page.locator("dialog[open] #connection_status")).toBeVisible();
  await page.locator("dialog[open] form[action='/logout'] button").click();
  await expect(page).toHaveURL(/\/login/);
});
