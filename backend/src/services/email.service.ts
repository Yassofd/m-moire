import nodemailer from "nodemailer";

function buildTransporter() {
  if (!process.env.SMTP_HOST) {
    // Mode dev : transport null (log en console)
    return null;
  }
  return nodemailer.createTransport({
    host: process.env.SMTP_HOST,
    port: parseInt(process.env.SMTP_PORT || "587"),
    secure: process.env.SMTP_PORT === "465",
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });
}

export async function sendOtpEmail(
  to: string,
  code: string,
  purpose: "register" | "login"
): Promise<void> {
  const transporter = buildTransporter();

  if (!transporter) {
    console.log(
      `[EMAIL OTP] ─── To: ${to} | Code: ${code} | Purpose: ${purpose} ───`
    );
    return;
  }

  const subject =
    purpose === "register"
      ? "ChainBackup — Confirmez votre compte"
      : "ChainBackup — Code de vérification";

  await transporter.sendMail({
    from: `ChainBackup <${process.env.SMTP_FROM || "noreply@chainbackup.io"}>`,
    to,
    subject,
    html: `
      <div style="font-family: -apple-system, sans-serif; max-width: 420px; margin: 0 auto; padding: 32px;">
        <div style="display: flex; align-items: center; gap: 8px; margin-bottom: 32px;">
          <div style="width: 32px; height: 32px; background: #6366f1; border-radius: 8px;"></div>
          <span style="font-size: 20px; font-weight: 700; color: #111;">Chain<span style="color: #6366f1;">Backup</span></span>
        </div>
        <h2 style="color: #111; margin: 0 0 8px;">
          ${purpose === "register" ? "Vérifiez votre adresse email" : "Votre code de connexion"}
        </h2>
        <p style="color: #666; margin: 0 0 24px;">
          ${purpose === "register"
            ? "Pour activer votre compte ChainBackup, entrez le code ci-dessous."
            : "Entrez ce code pour finaliser votre connexion."}
        </p>
        <div style="background: #f4f4f5; border-radius: 12px; padding: 24px; text-align: center; margin-bottom: 24px;">
          <span style="font-size: 36px; font-weight: 800; letter-spacing: 12px; color: #6366f1;">${code}</span>
        </div>
        <p style="color: #999; font-size: 13px;">Valable 10 minutes. Ne partagez jamais ce code.</p>
      </div>
    `,
  });
}
