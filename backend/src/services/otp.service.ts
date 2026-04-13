import { v4 as uuidv4 } from "uuid";
import db from "../db/index";

const OTP_TTL_MINUTES = 10;
const MAX_ATTEMPTS = 5;

export function generateOtpCode(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

export function createOtp(
  userId: string,
  channel: "email" | "phone",
  purpose: "register" | "login"
): string {
  // Invalide les anciens OTPs non utilisés pour ce canal/purpose
  db.prepare(
    `DELETE FROM otps WHERE user_id = ? AND channel = ? AND purpose = ? AND used_at IS NULL`
  ).run(userId, channel, purpose);

  const code = generateOtpCode();
  const expiresAt = new Date(Date.now() + OTP_TTL_MINUTES * 60 * 1000).toISOString();

  db.prepare(
    `INSERT INTO otps (id, user_id, code, channel, purpose, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)`
  ).run(uuidv4(), userId, code, channel, purpose, expiresAt);

  return code;
}

export function verifyOtp(
  userId: string,
  code: string,
  channel: "email" | "phone",
  purpose: "register" | "login"
): boolean {
  const otp = db
    .prepare(
      `SELECT * FROM otps
       WHERE user_id = ? AND channel = ? AND purpose = ? AND used_at IS NULL
       ORDER BY expires_at DESC LIMIT 1`
    )
    .get(userId, channel, purpose) as
    | { id: string; code: string; expires_at: string; attempts: number }
    | undefined;

  if (!otp) return false;

  // OTP expiré
  if (new Date(otp.expires_at) < new Date()) return false;

  // Trop de tentatives
  if (otp.attempts >= MAX_ATTEMPTS) return false;

  // Incrémente les tentatives avant de vérifier
  db.prepare(`UPDATE otps SET attempts = attempts + 1 WHERE id = ?`).run(otp.id);

  if (otp.code !== code) return false;

  // Marque comme utilisé
  db.prepare(`UPDATE otps SET used_at = datetime('now') WHERE id = ?`).run(otp.id);

  return true;
}
