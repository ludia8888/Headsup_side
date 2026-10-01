import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { randomUUID, randomBytes, createHash, timingSafeEqual } from "node:crypto";
import { Store } from "./store.js";
import { type Config, type Providers, type Device, type Call, type CallStatus, defaultProfile, terminal } from "./types.js";
import { HTTPError, record, only, string, uuid, date, parseProfile } from "./validation.js";
import { apnsConfigured, ProviderError } from "./providers.js";
import { liveInstructions } from "./prompt.js";
import { chooseConversation, nextConversationHistory } from "./conversation.js";

const hash = (text: string) => createHash("sha256").update(text).digest("hex");
const equal = (a: string, b: string) => timingSafeEqual(Buffer.from(hash(a), "hex"), Buffer.from(hash(b), "hex"));
export function createAPI(config: Config, upstream: Providers, store = new Store(config.dataFile), clock: () => Date = () => new Date(), pushTestDelayMs = 8_000) {
  const rates = new Map<string, { count: number; reset: number }>();
  const previews = new Set<string>();
  const limit = (key: string, max: number) => {
    const now = clock().getTime(); const bucket = rates.get(key);
    if (!bucket || bucket.reset < now) rates.set(key, { count: 1, reset: now + 60_000 });
    else { if (bucket.count >= max) throw new HTTPError(429, "rate_limited"); bucket.count += 1; }
    if (rates.size > 2000) for (const [k, b] of rates) if (b.reset < now) rates.delete(k);
  };
  const authenticate = (request: IncomingMessage): Device => {
    const authorization = request.headers.authorization;
    if (!authorization?.startsWith("Bearer ") || authorization.length > 100) throw new HTTPError(401, "authentication_required");
    const tokenHash = hash(authorization.slice(7));
    const device = Object.values(store.state.devices).find(d => equal(d.tokenHash, tokenHash));
    if (!device) throw new HTTPError(401, "authentication_required"); return device;
  };
  const ownCall = (id: string, device: Device): Call => {
    const call = store.state.calls[id];
    if (!call || call.deviceId !== device.id) throw new HTTPError(404, "call_not_found"); return call;
  };
  const end = (call: Call, status: CallStatus) => {
    call.status = status; call.endedAt = clock().toISOString();
    delete call.profile; delete call.sessionCreating;
    if (call.openaiSessionId) {
      const sessionId = call.openaiSessionId;
      const hangup = () => { void upstream.hangup?.(sessionId).catch(() => {}); };
      // Let the phone send session.close and receive final usage first.
      if (status === "ended") setTimeout(hangup, 6_000).unref(); else hangup();
    }
    store.save();
  };
  const expire = () => {
    for (const call of Object.values(store.state.calls)) {
      if (["requested", "ringing"].includes(call.status) && Date.parse(call.expiresAt) <= clock().getTime()) end(call, "unanswered");
      else if (!terminal(call.status) && clock().getTime() - Date.parse(call.receivedAt) > 30 * 60_000) end(call, "ended");
    }
  };
  const envelope = (call: Call) => ({ id: call.id, displayName: call.displayName,
    createdAt: call.requestedAt, expiresAt: call.expiresAt, status: call.status,
    delivery: call.mode === "manual" ? "foreground" : "push", character: call.profile?.character,
    openingCue: call.conversation?.opening,
    instructions: call.profile ? liveInstructions(call.profile, call.conversation) : undefined });
  const json = (response: ServerResponse, status: number, value: unknown) => {
    response.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store" }); response.end(JSON.stringify(value));
  };
  const body = async (request: IncomingMessage, max = 32_768): Promise<unknown> => {
    let size = 0; const chunks: Buffer[] = [];
    for await (const chunk of request) {
      size += Buffer.byteLength(chunk); if (size > max) throw new HTTPError(413, "body_too_large"); chunks.push(Buffer.from(chunk));
    }
    if (!request.headers["content-type"]?.startsWith("application/json")) throw new HTTPError(415, "json_required");
    try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { throw new HTTPError(400, "invalid_json"); }
  };
  const server = createServer(async (request, response) => {
    try {
      expire();
      const path = new URL(request.url ?? "/", "http://localhost").pathname;
      const method = request.method;
      if (path === "/health" && method === "GET") {
        json(response, 200, { ok: true, model: config.liveModel, backendModel: config.backendModel, voiceConfigured: Boolean(config.openaiApiKey),
          pushConfigured: apnsConfigured(config),
          automaticApproved: config.automaticApproved && config.appleApprovalReference.trim().length > 4 }); return;
      }
      if (path === "/v1/devices" && method === "POST") {
        limit(`register:${request.socket.remoteAddress}`, 5);
        if (config.registrationCode.length < 16 || !equal(String(request.headers["x-pairing-code"] ?? ""), config.registrationCode)) throw new HTTPError(403, "pairing_code_invalid");
        const payload = record(await body(request)); only(payload, []);
        const token = randomBytes(32).toString("hex"); const id = randomUUID();
        store.state.devices[id] = { id, tokenHash: hash(token), createdAt: clock().toISOString(), profile: defaultProfile() };
        store.save(); json(response, 201, { deviceId: id, token }); return;
      }
      const device = authenticate(request);
      limit(`device:${device.id}`, 120);
      if (path === "/v1/device" && method === "DELETE") {
        for (const call of Object.values(store.state.calls)) if (call.deviceId === device.id) {
          if (!terminal(call.status)) end(call, "ended"); delete store.state.calls[call.id];
        }
        delete store.state.devices[device.id]; store.save(); json(response, 200, { deleted: true }); return;
      }
      if (path === "/v1/device/profile" && method === "PUT") {
        device.profile = parseProfile(await body(request, 196_608)); store.save(); json(response, 200, { saved: true }); return;
      }
      if (path === "/v1/device/push" && method === "PUT") {
        const o = record(await body(request)); only(o, ["token", "environment"]);
        const token = string(o.token, 512);
        if (!/^[a-f\d]{32,512}$/i.test(token)) throw new HTTPError(400, "invalid_push_token");
        if (o.environment !== "sandbox" && o.environment !== "production") throw new HTTPError(400, "invalid_push_environment");
        device.voipToken = token; device.pushEnvironment = o.environment; store.save(); json(response, 200, { registered: true }); return;
      }
      if (path === "/v1/device/push" && method === "DELETE") {
        delete device.voipToken; delete device.pushEnvironment; store.save(); json(response, 200, { deleted: true }); return;
      }
      if (path === "/v1/voice-preview" && method === "POST") {
        limit(`preview:${device.id}`, 6);
        const profile = parseProfile(await body(request));
        if (previews.has(device.id)) throw new HTTPError(409, "preview_busy");
        previews.add(device.id);
        try {
          const audio = await upstream.preview(profile);
          response.writeHead(200, { "Content-Type": "audio/mpeg", "Cache-Control": "no-store" }); response.end(audio);
        } finally { previews.delete(device.id); }
        return;
      }
      if (path === "/v1/calls" && method === "POST") {
        limit(`call:${device.id}`, 6);
        const o = record(await body(request)); only(o, ["requestId", "mode", "createdAt"]);
        const id = uuid(o.requestId); const createdAt = date(o.createdAt);
        if (o.mode !== "manual" && o.mode !== "testPush" && o.mode !== "automatic") throw new HTTPError(400, "invalid_call_mode");
        const existing = store.state.calls[id];
        if (existing) { if (existing.deviceId !== device.id) throw new HTTPError(404, "call_not_found"); json(response, 200, envelope(existing)); return; }
        const age = clock().getTime() - Date.parse(createdAt);
        if (age > 60_000 || age < -10_000) throw new HTTPError(410, "stale_request");
        if (o.mode === "automatic") {
          if (!config.automaticApproved || config.appleApprovalReference.trim().length <= 4) throw new HTTPError(403, "apple_approval_pending");
          const day = new Intl.DateTimeFormat("en-CA", { timeZone: device.profile.timeZone, year: "numeric", month: "2-digit", day: "2-digit" }).format(clock());
          if (!device.profile.proactiveEnabled || device.profile.pausedDay === day) throw new HTTPError(409, "automatic_paused");
        }
        if (o.mode === "testPush") {
          // Explicit device-initiated sandbox call. It has no Screen Time input and
          // cannot enable the automatic-call path while Apple review is pending.
          if (config.apns.environment !== "sandbox") throw new HTTPError(403, "push_test_sandbox_only");
          if (!apnsConfigured(config) || !device.voipToken || device.pushEnvironment !== "sandbox") {
            throw new HTTPError(409, "voip_device_not_registered");
          }
          limit(`push-test:${device.id}`, 2);
        }
        if (Object.values(store.state.calls).some(c => c.deviceId === device.id && !terminal(c.status))) throw new HTTPError(409, "already_in_call");
        const call: Call = { id, deviceId: device.id, mode: o.mode, status: "requested", displayName: device.profile.character.name,
          requestedAt: new Date(createdAt).toISOString(), receivedAt: clock().toISOString(),
          expiresAt: new Date(clock().getTime() + (o.mode === "testPush" ? 45_000 : 30_000)).toISOString(),
          profile: structuredClone(device.profile), conversation: chooseConversation(device.recentConversationIds) };
        device.recentConversationIds = nextConversationHistory(device.recentConversationIds ?? [], call.conversation!);
        store.state.calls[id] = call; store.save();
        if (call.mode === "automatic") {
          try { await upstream.push(device, call); }
          catch (error) { end(call, "failed"); throw error; }
        } else if (call.mode === "testPush") {
          // Give the tester time to lock the phone before the real incoming call.
          setTimeout(() => {
            if (call.status !== "requested") return;
            void upstream.push(device, call).catch(() => end(call, "failed"));
          }, pushTestDelayMs).unref();
        }
        json(response, 201, envelope(call)); return;
      }
      const match = path.match(/^\/v1\/calls\/([a-f\d-]{36})(?:\/(session|result|feedback|usage))?$/i);
      if (match?.[1]) {
        const call = ownCall(uuid(match[1]), device); const action = match[2];
        if (!action && method === "GET") { json(response, 200, envelope(call)); return; }
        if (action === "session" && method === "POST") {
          const o = record(await body(request, 131_072)); only(o, ["sdp"]);
          const sdp = string(o.sdp, 120_000); if (!sdp.startsWith("v=0")) throw new HTTPError(400, "invalid_sdp");
          if (call.status !== "answered" || !call.profile) throw new HTTPError(409, "call_not_answered");
          if (call.sessionCreating || call.sessionCreated) throw new HTTPError(409, "session_already_created");
          call.sessionCreating = true; store.save();
          try {
            const result = await upstream.session(sdp, call.profile, device.id, call.conversation);
            if (terminal(call.status)) {
              if (result.sessionId) await upstream.hangup?.(result.sessionId).catch(() => {});
              throw new HTTPError(410, "call_ended");
            }
            delete call.sessionCreating; call.sessionCreated = true;
            if (result.sessionId) call.openaiSessionId = result.sessionId;
            store.save(); response.writeHead(200, { "Content-Type": "application/sdp", "Cache-Control": "no-store" }); response.end(result.sdp);
          } catch (error) { if (!terminal(call.status)) end(call, "failed"); throw error; }
          return;
        }
        if (action === "result" && method === "POST") {
          const o = record(await body(request)); only(o, ["status"]);
          const status = string(o.status, 20) as CallStatus;
          if (!["ringing", "answered", "voiceConnected", "declined", "unanswered", "failed", "ended"].includes(status)) throw new HTTPError(400, "invalid_status");
          if (terminal(call.status) || call.status === status) { json(response, 200, { status: call.status }); return; }
          if (call.answeredAt && ["declined", "unanswered", "ringing"].includes(status)) throw new HTTPError(409, "invalid_transition");
          if (status === "voiceConnected" && (!call.sessionCreated || !call.answeredAt)) throw new HTTPError(409, "session_not_connected");
          if (status === "ringing" && call.status !== "requested") throw new HTTPError(409, "invalid_transition");
          if (status === "answered") call.answeredAt = clock().toISOString();
          if (status === "voiceConnected") call.voiceConnectedAt = clock().toISOString();
          if (terminal(status)) end(call, status); else { call.status = status; store.save(); }
          json(response, 200, { status: call.status }); return;
        }
        if (action === "feedback" && method === "POST") {
          const o = record(await body(request)); only(o, ["openingEngaging", "appStopped", "wantsTomorrow"]);
          if (!terminal(call.status) || !call.answeredAt) throw new HTTPError(409, "feedback_not_available");
          const appStopped = string(o.appStopped, 7); const wantsTomorrow = string(o.wantsTomorrow, 7);
          const openingEngaging = o.openingEngaging === undefined ? undefined : string(o.openingEngaging, 7);
          if (!["yes", "no", "unknown"].includes(appStopped) || !["yes", "no", "unknown"].includes(wantsTomorrow)) throw new HTTPError(400, "invalid_feedback");
          if (openingEngaging !== undefined && !["yes", "no", "unknown"].includes(openingEngaging)) throw new HTTPError(400, "invalid_feedback");
          call.observations = { ...(openingEngaging === undefined ? {} : { openingEngaging: openingEngaging as "yes" | "no" | "unknown" }),
            appStopped: appStopped as "yes" | "no" | "unknown", wantsTomorrow: wantsTomorrow as "yes" | "no" | "unknown" };
          store.save(); json(response, 200, { saved: true }); return;
        }
        if (action === "usage" && method === "POST") {
          const o = record(await body(request)); only(o, ["seconds"]);
          const seconds = o.seconds;
          if (!call.sessionCreated || typeof seconds !== "number" || !Number.isFinite(seconds) || seconds < 0 || seconds > 31 * 60) {
            throw new HTTPError(400, "invalid_usage");
          }
          if (call.liveFinalizedAt && call.liveUsageSeconds !== seconds) throw new HTTPError(409, "usage_already_finalized");
          call.liveUsageSeconds = seconds; call.liveFinalizedAt = clock().toISOString(); store.save();
          json(response, 200, { saved: true }); return;
        }
      }
      throw new HTTPError(404, "not_found");
    } catch (error) {
      if (response.headersSent) { response.end(); return; }
      if (error instanceof HTTPError) json(response, error.status, { error: error.code });
      else if (error instanceof ProviderError) json(response, 503, { error: error.code });
      else { console.error("A request failed safely; inspect server configuration."); json(response, 500, { error: "internal_error" }); }
    }
  });
  server.requestTimeout = 35_000; server.headersTimeout = 10_000;
  const sweep = setInterval(expire, 5000); sweep.unref(); server.on("close", () => clearInterval(sweep));
  return { server, store, expire };
}
