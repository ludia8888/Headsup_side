import { createAPI } from "./api.js";
import { providers } from "./providers.js";
import type { Config } from "./types.js";

const config: Config = {
  registrationCode: process.env.REGISTRATION_CODE ?? "",
  dataFile: process.env.DATA_FILE ?? "./data/state.json",
  openaiApiKey: process.env.OPENAI_API_KEY ?? "",
  liveModel: "gpt-live-1",
  backendModel: process.env.OPENAI_LIVE_BACKEND_MODEL ?? "gpt-6-luna",
  automaticApproved: process.env.AUTO_CALL_APPROVED === "true",
  appleApprovalReference: process.env.APPLE_APPROVAL_REFERENCE ?? "",
  apns: { keyPath: process.env.APNS_KEY_PATH ?? "", keyId: process.env.APNS_KEY_ID ?? "", teamId: process.env.APNS_TEAM_ID ?? "",
    bundleId: process.env.APNS_BUNDLE_ID ?? "com.jimin.mvp", environment: process.env.APNS_ENVIRONMENT === "production" ? "production" : "sandbox" }
};
if (config.registrationCode.length < 16 || config.registrationCode.startsWith("replace-")) {
  console.error("Set REGISTRATION_CODE to a random value of at least 16 characters before starting."); process.exit(1);
}
if (config.automaticApproved && config.appleApprovalReference.trim().length <= 4) {
  console.error("Automatic calls require a recorded Apple approval reference. Leave AUTO_CALL_APPROVED=false."); process.exit(1);
}
const { server } = createAPI(config, providers(config));
const port = Number(process.env.PORT ?? 8787); const host = process.env.HOST ?? "127.0.0.1";
server.listen(port, host, () => console.log(`Jimin server listening on ${host}:${port}. Voice ${config.openaiApiKey ? "configured" : "not configured"}; automatic calls ${config.automaticApproved ? "approval gate enabled" : "disabled"}.`));
for (const signal of ["SIGINT", "SIGTERM"] as const) process.on(signal, () => server.close(() => process.exit(0)));
