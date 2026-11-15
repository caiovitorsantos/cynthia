import type { WASocket } from "@whiskeysockets/baileys";

type Sock = Pick<WASocket, "sendPresenceUpdate" | "sendMessage">;
export type Sleep = (ms: number) => Promise<unknown>;

const realSleep: Sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

export const TYPING_MS = 2_000;
export const MIN_WAIT_S = 3;
export const MAX_WAIT_S = 12;

// RF-18: "digitando" por ~2 s e espera aleatória de 3 a 12 s antes de cada envio, para reduzir o risco de
// detecção de bot pelo WhatsApp. sleep e random são injetáveis para o teste não esperar de verdade.
export async function sendLikeAHuman(
  sock: Sock,
  jid: string,
  message: string,
  mentions?: string[],
  sleep: Sleep = realSleep,
  random: () => number = Math.random,
): Promise<string | undefined> {
  await sock.sendPresenceUpdate("composing", jid);
  await sleep(TYPING_MS);
  await sock.sendPresenceUpdate("paused", jid);

  await sleep((Math.floor(random() * (MAX_WAIT_S - MIN_WAIT_S + 1)) + MIN_WAIT_S) * 1_000);

  const content = mentions && mentions.length > 0 ? { text: message, mentions } : { text: message };
  const sent = await sock.sendMessage(jid, content);
  return sent?.key.id ?? undefined;
}
