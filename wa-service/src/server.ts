import "dotenv/config";
import express from "express";
import QRCode from "qrcode";
import pino from "pino";
import { requireInternalToken } from "./middleware/auth";
import * as whatsapp from "./whatsapp";

const logger = pino({ level: "info" });
const app = express();
app.use(express.json());

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

  await sock.sendMessage(group_jid, { text: message });
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
