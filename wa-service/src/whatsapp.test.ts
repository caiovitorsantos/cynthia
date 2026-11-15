import { test } from "node:test";
import assert from "node:assert/strict";
import type { WAMessage } from "@whiskeysockets/baileys";
import { toInboundEvent } from "./whatsapp";

const command = (key: Partial<WAMessage["key"]>) =>
  ({ key: { remoteJid: "g1@g.us", id: "m1", ...key }, message: { conversation: "!set pix x" } }) as WAMessage;

test("comando sem participante e de outra pessoa não vira evento (seria tratado como admin)", () => {
  assert.equal(toInboundEvent(command({ fromMe: false })), undefined);
});

test("comando do próprio número sem participante continua valendo", () => {
  assert.equal(toInboundEvent(command({ fromMe: true }))?.kind, "command");
});

test("comando de participante leva o JID dele", () => {
  assert.equal(toInboundEvent(command({ participant: "2@lid" }))?.participant_jid, "2@lid");
});

test("S-07: evento leva from_me explícito", () => {
  assert.equal(toInboundEvent(command({ fromMe: true }))?.from_me, true);
  assert.equal(toInboundEvent(command({ participant: "2@lid" }))?.from_me, false);
});

test("RNF-05b/TT-11/TT-12: queda sem logout reconecta na hora (≤ 60 s), sem apagar a sessão, e avisa o Rails", async () => {
  const { EventEmitter } = await import("node:events");
  const whatsapp = await import("./whatsapp");
  const sockets: { ev: InstanceType<typeof EventEmitter>; logoutCalls: number }[] = [];
  const makeSocket = () => {
    const fake = { ev: new EventEmitter(), logoutCalls: 0, logout: async () => void fake.logoutCalls++, user: undefined };
    sockets.push(fake);
    return fake;
  };
  let authLoads = 0;
  const authState = async () => {
    authLoads++;
    return { state: {}, saveCreds: async () => {} };
  };
  const posted: unknown[] = [];
  const originalFetch = globalThis.fetch;
  process.env.RAILS_WEBHOOK_URL = "http://rails.test/webhooks/whatsapp";
  globalThis.fetch = (async (_url: string, init: { body: string }) => {
    posted.push(JSON.parse(init.body));
    return new Response(null, { status: 204 });
  }) as unknown as typeof fetch;
  const tick = () => new Promise((resolve) => setImmediate(resolve));

  try {
    await whatsapp.init({ makeSocket: makeSocket as never, authState: authState as never });
    sockets[0]!.ev.emit("connection.update", { connection: "open" });
    assert.equal(whatsapp.getStatus(), "connected");

    const droppedAt = Date.now();
    sockets[0]!.ev.emit("connection.update", { connection: "close", lastDisconnect: { error: { output: { statusCode: 428 } } } });
    assert.equal(whatsapp.getStatus(), "disconnected");
    await tick();

    assert.equal(sockets.length, 2, "abriu um socket novo");
    sockets[1]!.ev.emit("connection.update", { connection: "open" });
    assert.equal(whatsapp.getStatus(), "connected");
    assert.ok(Date.now() - droppedAt <= 60_000);
    assert.equal(sockets[0]!.logoutCalls, 0, "não fez logout");
    assert.equal(authLoads, 2, "reaproveitou a sessão salva (sem resetSession)");
    assert.deepEqual(posted, [
      { kind: "session", event: "sessao_conectada", apos_queda_s: null },
      { kind: "session", event: "sessao_caiu", codigo: 428, logout: false },
      { kind: "session", event: "sessao_conectada", apos_queda_s: 0 },
    ]);
  } finally {
    globalThis.fetch = originalFetch;
    delete process.env.RAILS_WEBHOOK_URL;
  }
});
