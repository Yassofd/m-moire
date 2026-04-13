import { Router, Request, Response } from "express";
import { z } from "zod";
import bcrypt from "bcrypt";
import jwt from "jsonwebtoken";
import { v4 as uuidv4 } from "uuid";
import db from "../db/index";
import { createOtp, verifyOtp } from "../services/otp.service";
import { sendOtpEmail } from "../services/email.service";
import { sendOtpSms } from "../services/sms.service";

const router = Router();

function jwtSecret(): string {
  return process.env.JWT_SECRET || "dev-secret-change-in-prod";
}

// ─── Schémas de validation ─────────────────────────────────────────────────

const RegisterSchema = z.object({
  firstName: z.string().min(2, "Prénom trop court").max(50),
  lastName: z.string().min(2, "Nom trop court").max(50),
  email: z.string().email("Email invalide"),
  recoveryEmail: z.string().email("Email de récupération invalide"),
  phone: z
    .string()
    .regex(/^\+?[1-9]\d{7,14}$/, "Numéro de téléphone invalide (ex: +33612345678)"),
  password: z
    .string()
    .min(8, "Minimum 8 caractères")
    .regex(/[A-Z]/, "Doit contenir au moins une majuscule")
    .regex(/[0-9]/, "Doit contenir au moins un chiffre"),
});

const LoginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

const VerifyOtpSchema = z.object({
  userId: z.string().uuid(),
  emailOtp: z.string().length(6),
  phoneOtp: z.string().length(6),
});

// ─── POST /api/auth/register ───────────────────────────────────────────────

router.post("/register", async (req: Request, res: Response) => {
  const result = RegisterSchema.safeParse(req.body);
  if (!result.success) {
    return res.status(400).json({
      error: "Données invalides",
      details: result.error.flatten().fieldErrors,
    });
  }

  const { firstName, lastName, email, recoveryEmail, phone, password } = result.data;

  const existing = db.prepare("SELECT id FROM users WHERE email = ?").get(email);
  if (existing) {
    return res.status(409).json({ error: "Cet email est déjà utilisé" });
  }

  const passwordHash = await bcrypt.hash(password, 12);
  const userId = uuidv4();

  db.prepare(
    `INSERT INTO users (id, first_name, last_name, email, recovery_email, phone, password_hash)
     VALUES (?, ?, ?, ?, ?, ?, ?)`
  ).run(userId, firstName, lastName, email, recoveryEmail, phone, passwordHash);

  const emailCode = createOtp(userId, "email", "register");
  const phoneCode = createOtp(userId, "phone", "register");

  await sendOtpEmail(email, emailCode, "register");
  await sendOtpSms(phone, phoneCode);

  return res.status(201).json({
    message: "Vérification requise. Codes OTP envoyés par email et SMS.",
    userId,
  });
});

// ─── POST /api/auth/verify-register ───────────────────────────────────────

router.post("/verify-register", (req: Request, res: Response) => {
  const result = VerifyOtpSchema.safeParse(req.body);
  if (!result.success) {
    return res.status(400).json({ error: "Champs manquants ou invalides" });
  }

  const { userId, emailOtp, phoneOtp } = result.data;

  const user = db.prepare("SELECT * FROM users WHERE id = ?").get(userId) as
    | { id: string; first_name: string; last_name: string; email: string; is_active: number }
    | undefined;

  if (!user) {
    return res.status(404).json({ error: "Utilisateur introuvable" });
  }

  const emailOk = verifyOtp(userId, emailOtp, "email", "register");
  const phoneOk = verifyOtp(userId, phoneOtp, "phone", "register");

  if (!emailOk || !phoneOk) {
    return res.status(400).json({
      error: "Code OTP invalide ou expiré",
      fields: {
        emailOtp: emailOk ? "ok" : "invalid",
        phoneOtp: phoneOk ? "ok" : "invalid",
      },
    });
  }

  db.prepare("UPDATE users SET is_active = 1 WHERE id = ?").run(userId);

  const token = jwt.sign({ userId, email: user.email }, jwtSecret(), { expiresIn: "7d" });

  return res.json({
    message: "Compte activé avec succès",
    token,
    user: {
      id: user.id,
      firstName: user.first_name,
      lastName: user.last_name,
      email: user.email,
    },
  });
});

// ─── POST /api/auth/login ──────────────────────────────────────────────────

router.post("/login", async (req: Request, res: Response) => {
  const result = LoginSchema.safeParse(req.body);
  if (!result.success) {
    return res.status(400).json({ error: "Email et mot de passe requis" });
  }

  const { email, password } = result.data;

  const user = db.prepare("SELECT * FROM users WHERE email = ?").get(email) as
    | { id: string; password_hash: string; phone: string; is_active: number }
    | undefined;

  // Même message d'erreur volontaire pour email introuvable ou mdp incorrect (sécurité)
  if (!user) {
    return res.status(401).json({ error: "Identifiants incorrects" });
  }

  if (!user.is_active) {
    return res.status(403).json({
      error: "Compte non vérifié",
      userId: user.id,
      action: "verify-register",
    });
  }

  const passwordOk = await bcrypt.compare(password, user.password_hash);
  if (!passwordOk) {
    return res.status(401).json({ error: "Identifiants incorrects" });
  }

  const emailCode = createOtp(user.id, "email", "login");
  const phoneCode = createOtp(user.id, "phone", "login");

  await sendOtpEmail(email, emailCode, "login");
  await sendOtpSms(user.phone, phoneCode);

  return res.json({
    message: "Vérification requise. Codes OTP envoyés par email et SMS.",
    userId: user.id,
  });
});

// ─── POST /api/auth/verify-login ──────────────────────────────────────────

router.post("/verify-login", (req: Request, res: Response) => {
  const result = VerifyOtpSchema.safeParse(req.body);
  if (!result.success) {
    return res.status(400).json({ error: "Champs manquants ou invalides" });
  }

  const { userId, emailOtp, phoneOtp } = result.data;

  const user = db.prepare("SELECT * FROM users WHERE id = ?").get(userId) as
    | { id: string; first_name: string; last_name: string; email: string }
    | undefined;

  if (!user) {
    return res.status(404).json({ error: "Utilisateur introuvable" });
  }

  const emailOk = verifyOtp(userId, emailOtp, "email", "login");
  const phoneOk = verifyOtp(userId, phoneOtp, "phone", "login");

  if (!emailOk || !phoneOk) {
    return res.status(400).json({
      error: "Code OTP invalide ou expiré",
      fields: {
        emailOtp: emailOk ? "ok" : "invalid",
        phoneOtp: phoneOk ? "ok" : "invalid",
      },
    });
  }

  const token = jwt.sign({ userId, email: user.email }, jwtSecret(), { expiresIn: "7d" });

  return res.json({
    token,
    user: {
      id: user.id,
      firstName: user.first_name,
      lastName: user.last_name,
      email: user.email,
    },
  });
});

// ─── POST /api/auth/resend-otp ─────────────────────────────────────────────

router.post("/resend-otp", async (req: Request, res: Response) => {
  const { userId, purpose } = req.body as {
    userId?: string;
    purpose?: "register" | "login";
  };

  if (!userId || !purpose) {
    return res.status(400).json({ error: "userId et purpose requis" });
  }

  const user = db.prepare("SELECT * FROM users WHERE id = ?").get(userId) as
    | { id: string; email: string; phone: string }
    | undefined;

  if (!user) {
    return res.status(404).json({ error: "Utilisateur introuvable" });
  }

  const emailCode = createOtp(userId, "email", purpose);
  const phoneCode = createOtp(userId, "phone", purpose);

  await sendOtpEmail(user.email, emailCode, purpose);
  await sendOtpSms(user.phone, phoneCode);

  return res.json({ message: "Nouveaux codes OTP envoyés" });
});

export default router;
