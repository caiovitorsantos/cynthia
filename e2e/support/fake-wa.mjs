// wa-service falso para o E2E (node:http, sem dependência). Mesmo contrato do wa-service real
// (token interno, 503 not_connected) e, de quebra, um /v1/messages falso da Anthropic para o chat
// e as menções: nada sai da máquina. Rotas /__* controlam e inspecionam o estado (só o teste usa).
import http from "node:http";

const TOKEN = process.env.INTERNAL_API_TOKEN ?? "";
// PNG 1x1 como "QR" (o painel só mostra a imagem).
const QR = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==";
const people = (from, n) => Array.from({ length: n }, (_, i) => ({
  jid: `55000000000${String(from + i).padStart(2, "0")}@s.whatsapp.net`,
  name: `e2e-Pessoa${from + i}`,
  admin: i === 0,
}));
const GROUPS = [
  { jid: "e2e-volei@g.us", name: "e2e-volei", participants: people(1, 6) },
  { jid: "e2e-futebol@g.us", name: "e2e-futebol", participants: people(7, 6) },
];

let state = "qr_pending";
let sent = [];
let left = [];
let anthropic = [];   // corpos recebidos em /v1/messages
let replies = [];     // respostas roteirizadas (fila); vazia = resposta de texto padrão

const json = (res, code, body) => { res.writeHead(code, { "content-type": "application/json" }); res.end(JSON.stringify(body)); };
const read = (req) => new Promise((resolve) => {
  let data = "";
  req.on("data", (c) => (data += c));
  req.on("end", () => { try { resolve(data ? JSON.parse(data) : {}); } catch { resolve({}); } });
});
const message = (content, stop_reason) => ({
  id: `msg_e2e_${anthropic.length}`, type: "message", role: "assistant", model: "claude-haiku-5-5",
  content, stop_reason, stop_sequence: null, usage: { input_tokens: 1, output_tokens: 1 },
});

http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://x");
  const body = req.method === "POST" ? await read(req) : {};

  // Controle do teste
  if (url.pathname === "/__state") { if (body.status) state = body.status; return json(res, 200, { status: state }); }
  if (url.pathname === "/__log") return json(res, 200, { sent, left, anthropic });
  if (url.pathname === "/__reset") { sent = []; left = []; anthropic = []; replies = []; return json(res, 200, {}); }
  if (url.pathname === "/__anthropic") { replies.push(...(body.replies ?? [])); return json(res, 200, { queued: replies.length }); }

  // Anthropic falsa (a chave e2e não vale em lugar nenhum)
  if (url.pathname === "/v1/messages") {
    anthropic.push({ ...body, at: Date.now() });
    const next = replies.shift();
    if (next?.error) return json(res, next.error, { type: "error", error: { type: "invalid_request_error", message: "e2e: erro da API" } });
    if (next?.tool_use) return json(res, 200, message([{ type: "tool_use", id: `toolu_e2e_${anthropic.length}`, name: next.tool_use.name, input: next.tool_use.input }], "tool_use"));
    return json(res, 200, message([{ type: "text", text: next?.text ?? "e2e: resposta da Cynth.ia" }], "end_turn"));
  }

  if (url.pathname === "/health") return json(res, 200, { status: state, connected: state === "connected" });
  if (req.headers.authorization !== TOKEN || !TOKEN) return json(res, 401, { error: "unauthorized" });

  if (url.pathname === "/qr") return state === "qr_pending" ? json(res, 200, { qr: QR }) : json(res, 404, { error: "no_qr_available" });
  if (url.pathname === "/logout") { state = "qr_pending"; return json(res, 200, { status: "logged_out" }); }
  if (state !== "connected") return json(res, 503, { error: "not_connected" });
  if (url.pathname === "/groups") {
    return json(res, 200, GROUPS.filter((g) => !left.some((l) => l.group_jid === g.jid)).map((g) => ({ ...g, participants_count: g.participants.length })));
  }
  if (url.pathname === "/send") {
    if (typeof body.group_jid !== "string" || typeof body.message !== "string") return json(res, 400, { error: "invalid_params" });
    sent.push({ ...body, at: Date.now() });
    return json(res, 200, { status: "sent", message_id: `e2e-msg-${Date.now()}-${sent.length}` }); // único entre resets
  }
  if (url.pathname === "/groups/leave") { left.push({ group_jid: body.group_jid, at: Date.now() }); return json(res, 200, { status: "left" }); }
  json(res, 404, { error: "not_found" });
}).listen(Number(process.env.PORT ?? 3001), () => console.log("fake-wa ouvindo"));
