import { readdir, rm } from "node:fs/promises";
import makeWASocket, {
  DisconnectReason,
  type WAMessage,
  useMultiFileAuthState,
  type WASocket,
  type Contact,
} from "@whiskeysockets/baileys";
import { Boom } from "@hapi/boom";
import pino from "pino";
import qrcodeTerminal from "qrcode-terminal";

export type ConnectionStatus = "disconnected" | "qr_pending" | "connected";

const logger = pino({ level: "info" });

let sock: WASocket | undefined;
let status: ConnectionStatus = "disconnected";
let lastQR: string | undefined;

const contactNames = new Map<string, string>();

function cacheContacts(contacts: Partial<Contact>[]): void {
  for (const contact of contacts) {
    const name = contact.name ?? contact.notify;
    if (contact.id && name) {
      contactNames.set(contact.id, name);
    }
  }
}

type InboundEvent = {
  kind: "reaction" | "reply" | "command" | "list" | "mention";
  group_jid: string;
  message_id: string;
  participant_jid: string;
  push_name: string | null;
  text: string;
  // S-07: o Rails só trata como o próprio número (admin) com from_me explícito, não por participante vazio.
  from_me: boolean;
};

// Eventos de sessão do tracking-plan (M4). Só código e números: sem JID nem nome.
type SessionEvent =
  | { kind: "session"; event: "sessao_conectada"; apos_queda_s: number | null }
  | { kind: "session"; event: "sessao_caiu"; codigo: number | null; logout: boolean };

// RNF-05b: ponto de injeção para o teste de reconexão usar um socket falso, sem WhatsApp nem ./auth.
type Deps = {
  makeSocket: typeof makeWASocket;
  authState: () => ReturnType<typeof useMultiFileAuthState>;
};

let deps: Deps = { makeSocket: makeWASocket, authState: () => useMultiFileAuthState("./auth") };
let droppedAt: number | undefined;

const NUMBERED_LINE = /^\s*\d+\s*[.)-]/;

// "5511999:12@s.whatsapp.net" e "5511999@s.whatsapp.net" são o mesmo usuário (sem o dispositivo).
const bareJid = (jid: string) => jid.replace(/:\d+(?=@)/, "");

// Marcaram o número conectado (a Cynth.ia) na mensagem?
function mentionsMe(msg: WAMessage): boolean {
  const own = [sock?.user?.id, sock?.user?.lid].filter(Boolean).map((jid) => bareJid(jid as string));
  const mentioned = msg.message?.extendedTextMessage?.contextInfo?.mentionedJid ?? [];
  return mentioned.some((jid) => own.includes(bareJid(jid)));
}

// Reações, respostas que citam uma mensagem, comandos ("!..."), listas numeradas coladas e
// menções à Cynth.ia, em grupos. O Rails decide o que fazer com cada um; o resto ele ignora.
export function toInboundEvent(msg: WAMessage): InboundEvent | undefined {
  const groupJid = msg.key.remoteJid;
  if (!groupJid?.endsWith("@g.us")) return undefined;

  const participantJid = msg.key.participant ?? "";
  // O Rails trata evento sem participante como o próprio número (admin): só o fromMe pode chegar assim (T18).
  if (!participantJid && !msg.key.fromMe) return undefined;
  const base = { group_jid: groupJid, participant_jid: participantJid, push_name: msg.pushName ?? null, from_me: Boolean(msg.key.fromMe) };
  const text = msg.message?.conversation ?? msg.message?.extendedTextMessage?.text ?? "";

  // Comandos valem também do próprio número conectado (o dono do bot digitando no celular).
  if (text.trim().startsWith("!")) {
    return { ...base, kind: "command", message_id: msg.key.id ?? "", text };
  }

  // Lista copiada e colada (2+ linhas "N. nome"): o Rails confere se é a lista da rodada.
  if (text.split("\n").filter((line) => NUMBERED_LINE.test(line)).length >= 2) {
    return { ...base, kind: "list", message_id: msg.key.id ?? "", text };
  }

  if (!participantJid || msg.key.fromMe) return undefined;

  if (mentionsMe(msg)) {
    return { ...base, kind: "mention", message_id: msg.key.id ?? "", text };
  }

  const reaction = msg.message?.reactionMessage;
  if (reaction?.key?.id) {
    return { ...base, kind: "reaction", message_id: reaction.key.id, text: reaction.text ?? "" };
  }

  const extended = msg.message?.extendedTextMessage;
  if (extended?.contextInfo?.stanzaId && extended.text) {
    return { ...base, kind: "reply", message_id: extended.contextInfo.stanzaId, text: extended.text };
  }

  return undefined;
}

async function forwardToRails(event: InboundEvent | SessionEvent): Promise<void> {
  const url = process.env.RAILS_WEBHOOK_URL;
  if (!url) return;

  try {
    const response = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: process.env.INTERNAL_API_TOKEN ?? "" },
      body: JSON.stringify(event),
    });
    if (!response.ok) logger.warn({ status: response.status }, "Webhook do Rails recusou o evento");
  } catch (err) {
    logger.warn({ err }, "Falha ao enviar evento ao Rails");
  }
}

async function connect(): Promise<void> {
  const { state, saveCreds } = await deps.authState();

  sock = deps.makeSocket({
    auth: state,
    logger: logger.child({ module: "baileys" }),
  });

  sock.ev.on("creds.update", saveCreds);
  sock.ev.on("contacts.upsert", cacheContacts);
  sock.ev.on("contacts.update", cacheContacts);
  // Dump inicial de contatos (sincronização de histórico). É por aqui que a
  // grande maioria dos contatos chega — contacts.upsert só cobre contatos
  // que aparecem depois da sincronização inicial.
  sock.ev.on("messaging-history.set", ({ contacts }) => {
    cacheContacts(contacts);
  });

  sock.ev.on("messages.upsert", ({ messages, type }) => {
    if (type !== "notify") return;

    for (const msg of messages) {
      const event = toInboundEvent(msg);
      if (event) void forwardToRails(event);
    }
  });

  sock.ev.on("connection.update", (update) => {
    const { connection, lastDisconnect, qr } = update;

    if (qr) {
      lastQR = qr;
      status = "qr_pending";
      qrcodeTerminal.generate(qr, { small: true });
    }

    if (connection === "open") {
      status = "connected";
      lastQR = undefined;
      logger.info("Conectado ao WhatsApp");
      const aposQuedaS = droppedAt === undefined ? null : Math.round((Date.now() - droppedAt) / 1_000);
      droppedAt = undefined;
      void forwardToRails({ kind: "session", event: "sessao_conectada", apos_queda_s: aposQuedaS });
    }

    if (connection === "close") {
      const statusCode = (lastDisconnect?.error as Boom | undefined)?.output
        ?.statusCode;
      const loggedOut = statusCode === DisconnectReason.loggedOut;

      status = "disconnected";
      droppedAt = Date.now();
      void forwardToRails({ kind: "session", event: "sessao_caiu", codigo: statusCode ?? null, logout: loggedOut });

      if (loggedOut) {
        // Sessão revogada (pelo celular ou pelo WhatsApp): a auth salva não serve mais, gera QR novo.
        logger.warn("Sessão encerrada (logout). Gerando novo QR Code.");
        resetSession().catch((err) => logger.error({ err }, "Falha ao gerar nova sessão"));
      } else {
        logger.warn({ statusCode }, "Conexão perdida, reconectando...");
        connect();
      }
    }
  });
}

export function init(overrides: Partial<Deps> = {}): Promise<void> {
  deps = { ...deps, ...overrides };
  return connect();
}

export function getSocket(): WASocket | undefined {
  return sock;
}

export function getStatus(): ConnectionStatus {
  return status;
}

export function getLastQR(): string | undefined {
  return lastQR;
}

export function getContactName(jid: string): string | undefined {
  return contactNames.get(jid);
}

export async function logout(): Promise<void> {
  // Sem isso o close do logout dispararia um segundo resetSession em paralelo.
  sock?.ev.removeAllListeners("connection.update");

  try {
    await sock?.logout();
  } catch (err) {
    logger.warn({ err }, "Erro ao encerrar sessão no WhatsApp, limpando estado local mesmo assim");
  }

  await resetSession();
}

async function resetSession(): Promise<void> {
  status = "disconnected";
  lastQR = undefined;
  sock = undefined;

  // ./auth é ponto de montagem de volume: apaga o conteúdo, não o diretório (rmdir dá EBUSY).
  const files = await readdir("./auth").catch(() => []);
  await Promise.all(files.map((file) => rm(`./auth/${file}`, { recursive: true, force: true })));

  await connect();
}
