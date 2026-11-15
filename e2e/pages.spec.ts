// TC-21 + TN-04 (RNF-04, RF-21): axe WCAG 2.1 AA em 1280 e 390 px, sem rolagem horizontal em 390 px,
// foco visível no Tab, Esc fecha modal e chat. Um login por largura.
import { test, expect, type Page } from "@playwright/test";
import { login, axe, noHorizontalScroll, groupId, waState } from "./support/helpers";

// Foco visível: o primeiro alvo de Tab muda outline ou box-shadow em relação ao estado sem foco.
async function focusIsVisible(page: Page, label: string) {
  await page.locator("body").click({ position: { x: 1, y: 1 } });
  const results: string[] = [];
  for (let i = 0; i < 6; i++) {
    await page.keyboard.press("Tab");
    const r = await page.evaluate(() => {
      const el = document.activeElement as HTMLElement | null;
      if (!el || el === document.body) return null;
      const focused = getComputedStyle(el);
      const f = `${focused.outlineStyle} ${focused.outlineWidth} ${focused.boxShadow}`;
      const visible = (focused.outlineStyle !== "none" && parseFloat(focused.outlineWidth) > 0) || focused.boxShadow !== "none";
      return { tag: `${el.tagName.toLowerCase()} ${(el.textContent ?? "").trim().slice(0, 30)}`, visible, f };
    });
    if (r && !r.visible) results.push(`${r.tag} [${r.f}]`);
  }
  expect.soft(results, `foco sem contorno visível em ${label}`).toEqual([]);
}

for (const width of [1280, 390]) {
  test(`páginas em ${width}px: axe, rolagem e teclado`, async ({ page, request }) => {
    await page.setViewportSize({ width, height: 900 });
    await waState(request, "connected");

    for (const path of ["/", "/login"]) {
      await page.goto(path);
      await axe(page, `${path} @${width}`);
      if (width === 390) await noHorizontalScroll(page, `${path} @390`);
    }
    await login(page);
    const id = await groupId(page, "e2e-volei");

    await axe(page, `/groups @${width}`);
    await focusIsVisible(page, `/groups @${width}`);
    if (width === 390) await noHorizontalScroll(page, "/groups @390");

    // Modal da conta: abre por teclado (Enter), axe, Esc fecha.
    await page.getByRole("button", { name: /e2e-admin/ }).focus();
    await page.keyboard.press("Enter");
    await expect(page.locator("dialog[open]")).toBeVisible();
    await expect(page.locator("dialog[open]").getByText("conectado", { exact: true })).toBeVisible();
    await axe(page, `modal da conta @${width}`);
    await page.keyboard.press("Escape");
    await expect(page.locator("dialog[open]")).toHaveCount(0);

    await page.goto(`/groups/${id}`);
    await expect(page.getByText(/Aviso de IA:/)).toBeVisible(); // selo RF-28
    for (const tab of ["Membros e listas", "Fluxos", "Templates", "Variáveis", "Regras"]) {
      await page.getByRole("tab", { name: tab }).click();
      await axe(page, `/groups/:id aba ${tab} @${width}`);
      if (width === 390) await noHorizontalScroll(page, `/groups/:id aba ${tab} @390`);
    }
    await focusIsVisible(page, `/groups/:id @${width}`);

    for (const trigger of ["schedule", "command"]) {
      await page.goto(`/groups/${id}/flows/new?trigger=${trigger}`);
      await axe(page, `formulário de fluxo (${trigger}) @${width}`);
      if (width === 390) await noHorizontalScroll(page, `formulário de fluxo (${trigger}) @390`);
    }
    await page.goto(`/groups/${id}/templates/new`);
    await axe(page, `formulário de template @${width}`);
    if (width === 390) await noHorizontalScroll(page, "formulário de template @390");

    await page.goto("/logs");
    await axe(page, `/logs @${width}`);
    await focusIsVisible(page, `/logs @${width}`);
    if (width === 390) {
      await noHorizontalScroll(page, "/logs @390");
      // tabela vira cartões: cabeçalho escondido e células com rótulo (data-label)
      await expect(page.locator("table.table-cards thead")).toBeHidden();
    }

    // Chat da Cynth.ia (A21-A23): botão com aria-expanded, Enter abre e foca o campo rotulado, Esc fecha e devolve o foco.
    await page.goto(`/groups/${id}`);
    const launcher = page.getByRole("button", { name: "Falar com a Cynth.ia" });
    await expect(launcher).toHaveAttribute("aria-expanded", "false");
    await launcher.focus();
    await page.keyboard.press("Enter");
    const panel = page.getByRole("dialog", { name: /Cynth\.ia/ });
    await expect(panel).toBeVisible();
    await expect(launcher).toHaveAttribute("aria-expanded", "true");
    await expect(page.getByRole("textbox", { name: /mensagem|message/i })).toBeFocused();
    await expect(panel).toContainText("e2e-volei"); // cabeçalho mostra o grupo aberto (RF-23)
    await axe(page, `chat aberto @${width}`);
    if (width === 390) await noHorizontalScroll(page, "chat aberto @390");
    await page.keyboard.press("Escape");
    await expect(panel).toBeHidden();
    await expect(launcher).toBeFocused();
  });
}
