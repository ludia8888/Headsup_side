import { connect } from "node:http2";
import { createPrivateKey, createSign, createHash } from "node:crypto";
import { readFileSync } from "node:fs";
import type { Config, Device, Call, Profile, Providers } from "./types.js";
import { sessionConfig } from "./prompt.js";

export class ProviderError extends Error {
  constructor(public readonly code: string) { super(code); }
}
export function providers(config: Config, request: typeof fetch = fetch): Providers {
  let jwt: { token: string; madeAt: number } | undefined;
  const authorization = () => {
    const now = Math.floor(Date.now() / 1000);
    if (jwt && now - jwt.madeAt < 50 * 60) return jwt.token;
    const a = config.apns;
    if (!a.keyPath || !a.teamId || !a.keyId) throw new ProviderError("apns_not_configured");
    const header = Buffer.from(JSON.stringify({ alg: "ES256", kid: a.keyId })).toString("base64url");
    const payload = Buffer.from(JSON.stringify({ iss: a.teamId, iat: now })).toString("base64url");
    const unsigned = `${header}.${payload}`;
    const key = createPrivateKey(readFileSync(a.keyPath));
    const sign = createSign("SHA256"); sign.update(unsigned); sign.end();
    const signature = sign.sign({ key, dsaEncoding: "ieee-p1363" }).toString("base64url");
    jwt = { token: `${unsigned}.${signature}`, madeAt: now }; return jwt.token;
  };
  const openai = async (path: string, init: RequestInit) => {
    if (!config.openaiApiKey) throw new ProviderError("openai_not_configured");
    let response: Response;
    try {
      response = await request(`https://api.openai.com/v1/${path}`, {
        ...init, headers: { ...init.headers, Authorization: `Bearer ${config.openaiApiKey}` },
        signal: AbortSignal.timeout(25_000)
      });
    } catch { throw new ProviderError("openai_connection_failed"); }
    if (!response.ok) {
      // Never log upstream request bodies, user memories or authorization headers.
      await response.arrayBuffer(); throw new ProviderError(`openai_http_${response.status}`);
    }
    return response;
  };
  return {
    async push(device: Device, call: Call) {
      if (!device.voipToken || device.pushEnvironment !== config.apns.environment) throw new ProviderError("voip_device_not_registered");
      const bearer = authorization();
      const host = config.apns.environment === "sandbox" ? "https://api.sandbox.push.apple.com" : "https://api.push.apple.com";
      await new Promise<void>((resolve, reject) => {
        const client = connect(host);
        let settled = false;
        const finish = (error?: Error) => {
          if (settled) return; settled = true; clearTimeout(timer); client.close();
          error ? reject(error) : resolve();
        };
        const timer = setTimeout(() => { client.destroy(); finish(new ProviderError("apns_timeout")); }, 10_000);
        client.on("error", () => finish(new ProviderError("apns_connection_failed")));
        const request = client.request({
          ":method": "POST", ":path": `/3/device/${device.voipToken}`,
          authorization: `bearer ${bearer}`, "apns-topic": `${config.apns.bundleId}.voip`,
          "apns-push-type": "voip", "apns-priority": "10", "apns-id": call.id,
          "apns-expiration": String(Math.floor(new Date(call.expiresAt).getTime() / 1000))
        });
        let status = 0;
        request.on("response", h => { status = Number(h[":status"]); });
        request.on("data", () => {});
        request.on("error", () => finish(new ProviderError("apns_request_failed")));
        request.on("end", () => finish(status === 200 ? undefined : new ProviderError(`apns_http_${status}`)));
        request.end(JSON.stringify({ aps: { "content-available": 1 }, call: {
          id: call.id, displayName: call.profile?.character.name ?? "지민",
          createdAt: call.requestedAt, expiresAt: call.expiresAt
        } }));
      });
    },
    async session(offer, profile, deviceId, conversation) {
      const response = await openai("live/sessions", { method: "POST",
        headers: { "Content-Type": "application/json", "OpenAI-Safety-Identifier": createHash("sha256").update(deviceId).digest("hex") },
        body: JSON.stringify({ session: sessionConfig(profile, config.liveModel, config.backendModel, conversation),
          transport: { type: "webrtc", sdp: offer } }) });
      let result: { session?: { id?: unknown }; transport?: { type?: unknown; sdp?: unknown } };
      try { result = await response.json() as typeof result; }
      catch { throw new ProviderError("openai_invalid_session"); }
      const sessionId = result.session?.id;
      const sdp = result.transport?.sdp;
      if (typeof sessionId !== "string" || !/^[A-Za-z0-9_-]{4,128}$/.test(sessionId) ||
          result.transport?.type !== "webrtc" || typeof sdp !== "string" || !sdp.startsWith("v=0")) {
        if (typeof sessionId === "string" && /^[A-Za-z0-9_-]{4,128}$/.test(sessionId)) {
          await openai(`live/sessions/${encodeURIComponent(sessionId)}/hangup`, { method: "POST" }).catch(() => {});
        }
        throw new ProviderError("openai_invalid_session");
      }
      return { sdp, sessionId };
    },
    async hangup(sessionId: string) { await openai(`live/sessions/${encodeURIComponent(sessionId)}/hangup`, { method: "POST" }); },
    async preview(profile: Profile) {
      const samples = { playful: `${profile.character.nickname}, 우리 집에 손바닥만 한 용이 들어오면 이름부터 지을까, 숨길 곳부터 찾을까?`,
        gentle: "오늘을 아이스크림 맛으로 표현하면 무슨 맛이야? 네가 고르는 맛이 궁금해.",
        direct: "갑자기 궁금해졌는데, 짝 잃은 양말은 자유로운 영혼일까, 그냥 길치일까?" };
      // This is a clearly labeled sample synthesized by TTS, not a GPT-Live call.
      const response = await openai("audio/speech", { method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ model: "gpt-4o-mini-tts", voice: profile.character.voice,
          input: samples[profile.character.persona], response_format: "mp3",
          instructions: `한국어로 말한다. ${profile.character.persona === "playful" ? "다정하고 장난스럽게" : profile.character.persona === "gentle" ? "차분하고 다정하게" : "직설적이고 장난스럽게"} 읽는다.` }) });
      return new Uint8Array(await response.arrayBuffer());
    }
  };
}
