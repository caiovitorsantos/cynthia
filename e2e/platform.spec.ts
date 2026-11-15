// RNF-06 (TN-06), RNF-07 (TN-07) e RNF-08 (TN-08).
import { test, expect } from "@playwright/test";
import { readFileSync, readdirSync } from "node:fs";
import { rails } from "./support/stack";

test("TN-06 (RNF-06): toda rota GET do painel sem sessão vai para /login", async ({ request }) => {
  const paths = rails(`print Rails.application.routes.routes.select { |r| r.verb.include?("GET") }.map { |r| r.path.spec.to_s.sub("(.:format)", "") }.uniq.join(" ")`)
    .split(" ").filter((p) => !p.startsWith("/rails/") && !p.includes("historical_location") && !["/", "/login", "/up"].includes(p));
  const ids = rails(`g = WhatsappGroup.where("jid LIKE 'e2e-%'").order(:id).first; print [g.id, g.templates.first.id, g.flows.first.id].join(" ")`).split(" ");
  expect(paths.length).toBeGreaterThan(8);
  const open: string[] = [];
  for (const path of paths) {
    const url = path.replace(":group_id", ids[0]).replace(/\/templates\/:id/, `/templates/${ids[1]}`).replace(/\/flows\/:id/, `/flows/${ids[2]}`).replace(":id", ids[0]);
    const res = await request.get(url, { maxRedirects: 0 });
    if (!(res.status() === 302 && (res.headers().location ?? "").endsWith("/login"))) open.push(`${url} ${res.status()}`);
  }
  expect(open, "rotas abertas sem sessão").toEqual([]);
});

test("TN-08 (RNF-08): navegador antigo recebe 406", async ({ request }) => {
  const res = await request.get("/login", { headers: { "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Trident/7.0; rv:11.0) like Gecko" } });
  expect(res.status()).toBe(406);
});

test("TN-07 (RNF-07): limites do SendGuard são constantes, sem parâmetro, ENV nem campo na interface", () => {
  const app = new URL("../rails-app/app/", import.meta.url).pathname;
  const files = (dir: string): string[] => readdirSync(dir, { withFileTypes: true }).flatMap((e) => e.isDirectory() ? files(`${dir}${e.name}/`) : [`${dir}${e.name}`]);
  const guard = readFileSync(`${app}services/send_guard.rb`, "utf8");
  expect(guard).toMatch(/MAX_DAILY_SENDS = 50$/m);
  expect(guard).toMatch(/THROTTLE_WINDOW = 20 /m);
  expect(guard).toMatch(/DUPLICATE_WINDOW = 6\.hours$/m);
  expect(guard).not.toMatch(/ENV|Setting|params/);
  const writers = files(app).filter((f) => !f.endsWith("send_guard.rb"))
    // só leitura é permitida (ex.: Flow espaça por THROTTLE_WINDOW): nada atribui, redefine nem recebe por parâmetro
    .filter((f) => /(MAX_DAILY_SENDS|THROTTLE_WINDOW|DUPLICATE_WINDOW)\s*=[^=]|const_set|remove_const|permit\([^)]*(daily|throttle|duplicate)/.test(readFileSync(f, "utf8")));
  expect(writers).toEqual([]);
});
