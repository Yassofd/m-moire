export async function sendOtpSms(to: string, code: string): Promise<void> {
  if (!process.env.TWILIO_ACCOUNT_SID || !process.env.TWILIO_AUTH_TOKEN) {
    console.log(`[SMS OTP]   ─── To: ${to} | Code: ${code} ───`);
    return;
  }

  // eslint-disable-next-line @typescript-eslint/no-require-imports
  const twilio = require("twilio")(
    process.env.TWILIO_ACCOUNT_SID,
    process.env.TWILIO_AUTH_TOKEN
  );

  await twilio.messages.create({
    body: `ChainBackup : votre code de vérification est ${code}. Valable 10 minutes.`,
    from: process.env.TWILIO_FROM_NUMBER,
    to,
  });
}
