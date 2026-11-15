// Chat da Cynth.ia no painel contra a Anthropic falsa do fake-wa (RF-23, RF-24, RF-29, TM-01, TM-22, A22-A24).
import { test, expect } from "@playwright/test";
import { login, groupId, waReset, waLog, anthropicQueue, piiIn, axe } from "./support/helpers";
import { rails } from "./support/stack";

test("chat do painel: pergunta, proposta confirmada, erro da API e nova conversa", async ({ page, request }) => {
  const alerts: string[] = [];
  page.on("dialog", (d) => { if (d.type() === "alert") alerts.push(d.message()); d.accept(); });
  await waReset(request);
  await login(page);
  const id = await groupId(page, "e2e-volei");
  await page.goto(`/groups/${id}`);

  const launcher = page.getByRole("button", { name: "Falar com a Cynth.ia" });
  const panel = page.getByRole("dialog", { name: /Cynth\.ia/ });
  const input = page.getByRole("textbox", { name: /mensagem/i });
  await launcher.click();

  await test.step("pergunta com get_group e proposta: cartão pendente, nada salvo (RF-23, RF-24)", async () => {
    await anthropicQueue(request, [
      { tool_use: { name: "get_group", input: { group_id: id } } },
      { tool_use: { name: "propose_variable", input: { group_id: id, name: "e2e_var", value: "e2e-valor" } } },
      { text: "Propus a variável. <script>window.__xss=1</script><img src=x onerror=\"window.__xss=2\">" },
    ]);
    await input.fill("Cria a variável e2e_var. Meu número é 5500000000099 e o pix {{pix}}");
    await input.press("Enter");
    await expect(panel.getByText("Propus a variável.", { exact: false }).first()).toBeVisible({ timeout: 20_000 });
    // TM-22: resposta do modelo aparece escapada, sem executar
    await expect(panel).toContainText("<script>window.__xss=1</script>");
    expect(await page.evaluate(() => (window as any).__xss)).toBeUndefined();
    // A22: a região viva anuncia a resposta
    await expect(page.locator("[data-assistant-target=status]")).toContainText("Propus a variável");
    await expect(panel.getByRole("button", { name: "Confirmar" })).toBeVisible();
    expect(rails(`print WhatsappGroup.find(${id}).variables.key?("e2e_var")`)).toBe("false");
    expect(rails(`print AssistantMessage.count`)).not.toBe("0"); // turno gravado
    await axe(page, "chat com proposta pendente", "#assistant-panel");
  });

  await test.step("a conversa persiste entre páginas (RF-23)", async () => {
    await page.goto("/logs");
    await page.getByRole("button", { name: "Falar com a Cynth.ia" }).click();
    await expect(page.locator("#assistant_conversation")).toContainText("Cria a variável e2e_var");
    await expect(page.locator("#assistant-panel header p")).not.toContainText("e2e-volei"); // sem grupo aberto, cabeçalho sem grupo
    await page.goto(`/groups/${id}`);
    await launcher.click();
  });

  await test.step("o que foi à Anthropic: idioma do painel, contexto do grupo e sem PII (RF-23, RF-29, TM-01)", async () => {
    const { anthropic } = await waLog(request);
    expect(anthropic.length).toBe(3); // 3 rodadas, abaixo do teto de 6
    expect(JSON.stringify(anthropic[0].system)).toContain("Brazilian Portuguese");
    expect(JSON.stringify(anthropic[0].messages)).toContain(`[page: group #${id}`);
    expect(JSON.stringify(anthropic[1].messages)).toContain("variable_names"); // resultado do get_group voltou
    expect(piiIn(anthropic), "PII no payload da Anthropic").toEqual([]);
  });

  await test.step("Confirmar salva com as validações do painel e o foco vai ao desfecho (RF-24, A24)", async () => {
    await panel.getByRole("button", { name: "Confirmar" }).click();
    const outcome = panel.locator("[data-assistant-target=outcome]").last();
    await expect(outcome).toBeVisible();
    await expect(outcome).toBeFocused();
    expect(rails(`print WhatsappGroup.find(${id}).variables["e2e_var"]`)).toBe("e2e-valor");
    expect(rails(`print AssistantAction.last.status`)).toBe("done");
  });

  await test.step("erro da API vira mensagem no chat, sem 500 (RF-23)", async () => {
    await anthropicQueue(request, [{ error: 400 }]);
    await input.fill("outra pergunta");
    const [res] = await Promise.all([page.waitForResponse((r) => r.url().endsWith("/assistant") && r.request().method() === "POST"), input.press("Enter")]);
    expect(res.status()).toBeLessThan(500);
    await expect(panel.getByText(/e2e: erro da API/).first()).toBeVisible();
  });

  await test.step("Nova conversa apaga o histórico e cancela propostas pendentes (RF-23)", async () => {
    await anthropicQueue(request, [{ tool_use: { name: "propose_variable", input: { group_id: id, name: "e2e_outra", value: "x" } } }, { text: "Mais uma proposta." }]);
    await input.fill("propõe outra");
    await input.press("Enter");
    await expect(panel.getByText("Mais uma proposta.").first()).toBeVisible({ timeout: 20_000 });
    await panel.getByRole("button", { name: "Nova conversa" }).click();
    await expect.poll(() => rails(`print AssistantMessage.count`)).toBe("0");
    expect(rails(`print AssistantAction.order(:id).last.status`)).toBe("cancelled");
  });

  await test.step("cada pergunta faz no máximo 6 rodadas de ferramentas (RF-23)", async () => {
    await waReset(request);
    await anthropicQueue(request, Array.from({ length: 8 }, () => ({ tool_use: { name: "get_group", input: { group_id: id } } })));
    await input.fill("e2e laço");
    await input.press("Enter");
    await expect.poll(async () => (await waLog(request)).anthropic.length, { timeout: 20_000 }).toBe(6);
    await page.waitForTimeout(2000);
    expect((await waLog(request)).anthropic.length).toBe(6);
    await waReset(request); // descarta o que sobrou na fila
  });

  expect(alerts, "nenhum alert executado (XSS)").toEqual([]);
});
