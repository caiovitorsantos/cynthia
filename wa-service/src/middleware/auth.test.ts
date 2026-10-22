import { test } from "node:test";
import assert from "node:assert/strict";
import type { NextFunction, Request, Response } from "express";
import { requireInternalToken } from "./auth";

function chamar(header: string | undefined, token: string | undefined) {
  if (token === undefined) delete process.env.INTERNAL_API_TOKEN;
  else process.env.INTERNAL_API_TOKEN = token;
  let status = 0;
  let seguiu = false;
  const req = { header: () => header } as unknown as Request;
  const res = {
    status(code: number) { status = code; return this; },
    json() { return this; },
  } as unknown as Response;
  requireInternalToken(req, res, (() => { seguiu = true; }) as NextFunction);
  return { status, seguiu };
}

test("aceita o token certo", () => {
  assert.deepEqual(chamar("segredo", "segredo"), { status: 0, seguiu: true });
});

test("recusa token errado, ausente ou de outro tamanho", () => {
  assert.equal(chamar("errado!", "segredo").status, 401);
  assert.equal(chamar(undefined, "segredo").status, 401);
  assert.equal(chamar("seg", "segredo").status, 401);
});

test("recusa tudo quando INTERNAL_API_TOKEN não está definido", () => {
  assert.equal(chamar("", undefined).status, 401);
  assert.equal(chamar("", "").status, 401);
});
