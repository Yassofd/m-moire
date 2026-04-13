import express from "express";
import cors from "cors";
import dotenv from "dotenv";
import authRouter from "./routes/auth";

dotenv.config();

const app = express();
const PORT = process.env.PORT || 3001;

app.use(
  cors({
    origin: process.env.FRONTEND_URL || "http://localhost:5173",
    credentials: true,
  })
);
app.use(express.json());

// ─── Routes ────────────────────────────────────────────────────────────────
app.use("/api/auth", authRouter);

// Health check
app.get("/health", (_req, res) => {
  res.json({ status: "ok", timestamp: new Date().toISOString() });
});

// ─── 404 catch-all ─────────────────────────────────────────────────────────
app.use((_req, res) => {
  res.status(404).json({ error: "Route introuvable" });
});

app.listen(PORT, () => {
  console.log(`\n  ╔══════════════════════════════════════╗`);
  console.log(`  ║   ChainBackup API — port ${PORT}        ║`);
  console.log(`  ║   http://localhost:${PORT}/health      ║`);
  console.log(`  ╚══════════════════════════════════════╝\n`);
  if (!process.env.SMTP_HOST) {
    console.log("  [INFO] SMTP non configuré — OTP email loggés en console");
  }
  if (!process.env.TWILIO_ACCOUNT_SID) {
    console.log("  [INFO] Twilio non configuré — OTP SMS loggés en console\n");
  }
});
