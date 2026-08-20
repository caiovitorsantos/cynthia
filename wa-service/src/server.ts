import "dotenv/config";
import express from "express";
import QRCode from "qrcode";
import pino from "pino";
import type { WASocket } from "@whiskeysockets/baileys";
import { requireInternalToken } from "./middleware/auth";
import * as whatsapp from "./whatsapp";

const logger = pino({ level: "info" });
const app = express();
app.use(express.json());

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

function randomSeconds(min: number, max: number): number {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

// Delay aleatório + simulação de "digitando" antes de cada envio, para reduzir
// o risco de detecção de bot pelo WhatsApp.
async function sendLikeAHuman(sock: WASocket, jid: string, message: string): Promise<void> {
  await sock.sendPresenceUpdate("composing", jid);
  await sleep(2_000);
  await sock.sendPresenceUpdate("paused", jid);

  await sleep(randomSeconds(3, 12) * 1_000);

  await sock.sendMessage(jid, { text: message });
}

app.get("/health", (_req, res) => {
  res.json({ status: whatsapp.getStatus(), connected: whatsapp.getStatus() === "connected" });
});

app.use(requireInternalToken);

app.get("/qr", async (_req, res) => {
  const qr = whatsapp.getLastQR();

  if (!qr) {
    res.status(404).json({ error: "no_qr_available" });
    return;
  }

  const dataUrl = await QRCode.toDataURL(qr);
  res.json({ qr: dataUrl });
});

app.get("/groups", async (_req, res) => {
  const sock = whatsapp.getSocket();

  if (whatsapp.getStatus() !== "connected" || !sock) {
    res.status(503).json({ error: "not_connected" });
    return;
  }

  const groups = await sock.groupFetchAllParticipating();
  const list = Object.values(groups).map((group) => ({
    jid: group.id,
    name: group.subject,
    participants_count: group.participants.length,
  }));

  res.json(list);
});

app.post("/send", async (req, res) => {
  const sock = whatsapp.getSocket();

  if (whatsapp.getStatus() !== "connected" || !sock) {
    res.status(503).json({ error: "not_connected" });
    return;
  }

  const { group_jid, message } = req.body ?? {};

  if (typeof group_jid !== "string" || typeof message !== "string") {
    res.status(400).json({ error: "invalid_params" });
    return;
  }

  await sendLikeAHuman(sock, group_jid, message);
  res.json({ status: "sent" });
});

app.post("/logout", async (_req, res) => {
  await whatsapp.logout();
  res.json({ status: "logged_out" });
});

const port = process.env.PORT ? Number(process.env.PORT) : 3001;

app.listen(port, () => {
  logger.info({ port }, "wa-service ouvindo");
  whatsapp.init();
});
