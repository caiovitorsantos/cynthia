import { test } from "node:test";
import assert from "node:assert/strict";
import { sendLikeAHuman } from "./send";

function fakeSock() {
  const calls: string[] = [];
  const sock = {
    sendPresenceUpdate: async (type: string, jid: string) => void calls.push(`presence:${type}:${jid}`),
    sendMessage: async (jid: string, content: unknown) => {
      calls.push(`send:${jid}:${JSON.stringify(content)}`);
      return { key: { id: "MSG1" } };
    },
  };
  return { calls, sock: sock as unknown as Parameters<typeof sendLikeAHuman>[0] };
}

test("RF-18: digitando ~2 s, pausa, espera de 3 s (mínimo) e só então envia", async () => {
  const { calls, sock } = fakeSock();
  const sleep = async (ms: number) => void calls.push(`sleep:${ms}`);

  const id = await sendLikeAHuman(sock, "g1@g.us", "oi", undefined, sleep, () => 0);

  assert.equal(id, "MSG1");
  assert.deepEqual(calls, [
    "presence:composing:g1@g.us",
    "sleep:2000",
    "presence:paused:g1@g.us",
    "sleep:3000",
    'send:g1@g.us:{"text":"oi"}',
  ]);
});

test("RF-18: espera máxima de 12 s e menções vão junto", async () => {
  const { calls, sock } = fakeSock();
  const sleep = async (ms: number) => void calls.push(`sleep:${ms}`);

  await sendLikeAHuman(sock, "g1@g.us", "oi", ["1@lid"], sleep, () => 0.9999);

  assert.equal(calls[3], "sleep:12000");
  assert.equal(calls[4], 'send:g1@g.us:{"text":"oi","mentions":["1@lid"]}');
});

test("RF-18: a espera fica sempre entre 3 e 12 s, em segundos inteiros", async () => {
  const waits = new Set<number>();
  for (let i = 0; i < 200; i++) {
    const { sock } = fakeSock();
    let n = 0;
    await sendLikeAHuman(sock, "g", "m", undefined, async (ms) => void (n++ === 1 && waits.add(ms)), () => i / 200);
  }
  assert.deepEqual([...waits].sort((a, b) => a - b), [3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map((s) => s * 1_000));
});
