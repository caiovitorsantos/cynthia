import { timingSafeEqual } from "node:crypto";
import type { NextFunction, Request, Response } from "express";

export function requireInternalToken(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  const expected = process.env.INTERNAL_API_TOKEN ?? "";
  const provided = req.header("Authorization") ?? "";

  const expectedBuf = Buffer.from(expected);
  const providedBuf = Buffer.from(provided);

  const valid =
    expectedBuf.length > 0 &&
    expectedBuf.length === providedBuf.length &&
    timingSafeEqual(expectedBuf, providedBuf);

  if (!valid) {
    res.status(401).json({ error: "unauthorized" });
    return;
  }

  next();
}
