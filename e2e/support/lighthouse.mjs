// TN-02 (RNF-02): Lighthouse CI logado, perfil mobile, nas páginas do RNF-01.
// node support/lighthouse.mjs   (stack E2E de pé; CHROME_PATH opcional, padrão: Chromium do Playwright)
// INP não existe em navegação de laboratório: o Lighthouse mede TBT, usado como proxy (meta 200 ms).
import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { chromium } from "@playwright/test";

const base = process.env.BASE_URL ?? `http://127.0.0.1:${process.env.E2E_PORT ?? 3555}`;
const env = Object.fromEntries(readFileSync(new URL("../.env.e2e", import.meta.url), "utf8").split("\n").filter((l) => l.includes("=")).map((l) => [l.slice(0, l.indexOf("=")), l.slice(l.indexOf("=") + 1)]));

// Login pelo formulário num navegador do Playwright só para obter o cookie de sessão.
const browser = await chromium.launch();
const page = await browser.newPage();
await page.goto(`${base}/login`);
await page.fill("#username", env.ADMIN_USERNAME);
await page.fill("#password", env.ADMIN_PASSWORD);
await Promise.all([page.waitForURL(/\/groups/), page.click("input[type=submit]")]);
const cookie = (await page.context().cookies()).map((c) => `${c.name}=${c.value}`).join("; ");
const group = (await page.getAttribute('a[href^="/groups/"]', "href")).split("/").pop();
await browser.close();

const urls = ["/groups", `/groups/${group}`, "/logs", `/groups/${group}/flows/new?trigger=schedule`, `/groups/${group}/templates/new`].map((p) => base + p);
const chrome = process.env.CHROME_PATH ?? chromium.executablePath();
const run = (args) => execFileSync("npx", ["-y", "@lhci/cli@0.15.1", ...args], { stdio: "inherit", env: { ...process.env, CHROME_PATH: chrome } });
run(["collect", ...urls.map((u) => `--url=${u}`), `--settings.extraHeaders=${JSON.stringify({ Cookie: cookie })}`, "--settings.chromeFlags=--headless=new --no-sandbox"]);
run(["assert"]);
