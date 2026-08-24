import { rm } from "node:fs/promises";
import makeWASocket, {
  DisconnectReason,
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

async function connect(): Promise<void> {
  const { state, saveCreds } = await useMultiFileAuthState("./auth");

  sock = makeWASocket({
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
    }

    if (connection === "close") {
      const statusCode = (lastDisconnect?.error as Boom | undefined)?.output
        ?.statusCode;
      const loggedOut = statusCode === DisconnectReason.loggedOut;

      status = "disconnected";

      if (loggedOut) {
        logger.warn("Sessão encerrada (logout). É necessário novo QR Code.");
      } else {
        logger.warn({ statusCode }, "Conexão perdida, reconectando...");
        connect();
      }
    }
  });
}

export function init(): void {
  connect();
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
  try {
    await sock?.logout();
  } catch (err) {
    logger.warn({ err }, "Erro ao encerrar sessão no WhatsApp, limpando estado local mesmo assim");
  }

  status = "disconnected";
  lastQR = undefined;
  sock = undefined;

  await rm("./auth", { recursive: true, force: true });

  await connect();
}
