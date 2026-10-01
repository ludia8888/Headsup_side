import test from "node:test";
import assert from "node:assert/strict";
import { generateKeyPairSync, randomUUID } from "node:crypto";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createAPI } from "../src/api.js";
import { defaultProfile, type Config, type Providers, type Call } from "../src/types.js";
import { Store } from "../src/store.js";
import { providers, ProviderError } from "../src/providers.js";
import { sessionConfig } from "../src/prompt.js";
import type { ConversationPlan } from "../src/conversation.js";

const configuration = (): Config => ({ registrationCode: "test-code-very-long-and-private", openaiApiKey: "", liveModel: "gpt-live-1", backendModel: "gpt-6-luna",
  automaticApproved: false, appleApprovalReference: "", apns: { keyPath: "", keyId: "", teamId: "", bundleId: "com.jimin.mvp", environment: "sandbox" } });

async function fixture(overrides: Partial<Config> = {}, injected?: Partial<Providers>, pushTestDelayMs = 8_000) {
  let now = new Date("2026-09-29T10:00:00.000Z");
  const pushed: Call[] = []; const sessions: { profile: ReturnType<typeof defaultProfile>; offer: string; conversation?: ConversationPlan }[] = [];
  const p: Providers = {
    push: async (_, call) => { pushed.push(structuredClone(call)); },
    session: async (offer, profile, _, conversation) => { sessions.push({ profile: structuredClone(profile), offer, ...(conversation ? { conversation: structuredClone(conversation) } : {}) }); return { sdp: "v=0\r\na=mock-answer", sessionId: "live_mock" }; },
    preview: async () => new Uint8Array([1, 2]), ...injected
  };
  const config = { ...configuration(), ...overrides };
  const { server, store, expire } = createAPI(config, p, new Store(), () => now, pushTestDelayMs);
  await new Promise<void>(resolve => server.listen(0, "127.0.0.1", resolve));
  const address = server.address(); assert.ok(address && typeof address === "object"); const base = `http://127.0.0.1:${address.port}`;
  const request = async (path: string, payload?: unknown, token?: string, method = "POST", extra: Record<string, string> = {}) => {
    return fetch(base + path, { method, headers: { "Content-Type": "application/json", ...(token ? { Authorization: `Bearer ${token}` } : {}), ...extra },
      ...(payload === undefined ? {} : { body: JSON.stringify(payload) }) });
  };
  const register = async () => {
    const response = await request("/v1/devices", {}, undefined, "POST", { "X-Pairing-Code": config.registrationCode });
    assert.equal(response.status, 201); return await response.json() as { deviceId: string; token: string };
  };
  const close = async () => { server.closeAllConnections(); await new Promise<void>((resolve, reject) => server.close(e => e ? reject(e) : resolve())); };
  return { request, register, close, pushed, sessions, store, expire, setTime: (date: string) => { now = new Date(date); },
    callBody: (mode: "manual" | "testPush" | "automatic" = "manual", requestId = randomUUID()) => ({ requestId, mode, createdAt: now.toISOString() }) };
}

test("pairing and ownership protect all call/session routes", async () => {
  const f = await fixture(); try {
    assert.equal((await f.request("/v1/devices", {})).status, 403);
    assert.equal((await f.request("/v1/calls", f.callBody())).status, 401);
    const a = await f.register(); const b = await f.register(); const body = f.callBody();
    assert.equal((await f.request("/v1/calls", body, a.token)).status, 201);
    assert.equal((await f.request(`/v1/calls/${body.requestId}/result`, { status: "answered" }, b.token)).status, 404);
    assert.equal((await f.request(`/v1/calls/${body.requestId}/session`, { sdp: "v=0" }, b.token)).status, 404);
  } finally { await f.close(); }
});
test("automatic gate rejects even a minimal signal and never pushes", async () => {
  const f = await fixture(); try {
    const d = await f.register(); const r = await f.request("/v1/calls", f.callBody("automatic"), d.token);
    assert.equal(r.status, 403); assert.equal((await r.json() as { error: string }).error, "apple_approval_pending");
    assert.equal(f.pushed.length, 0); assert.equal(Object.keys(f.store.state.calls).length, 0);
  } finally { await f.close(); }
});
test("explicit sandbox push test requires a registered VoIP token and does not unlock automatic calls", async () => {
  const directory = mkdtempSync(join(tmpdir(), "jimin-push-test-"));
  const keyPath = join(directory, "test.p8");
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  writeFileSync(keyPath, privateKey.export({ type: "pkcs8", format: "pem" }), { mode: 0o600 });
  const apns = { keyPath, keyId: "ABCDE12345", teamId: "TEAM123456",
    bundleId: "com.jimin.mvp", environment: "sandbox" as const };
  const f = await fixture({ apns }, undefined, 5);
  try {
    const d = await f.register();
    assert.equal((await f.request("/v1/calls", f.callBody("testPush"), d.token)).status, 409);
    assert.equal((await f.request("/v1/device/push", { token: "a".repeat(64), environment: "sandbox" }, d.token, "PUT")).status, 200);
    const body = f.callBody("testPush");
    const response = await f.request("/v1/calls", body, d.token);
    assert.equal(response.status, 201);
    assert.equal((await response.json() as { delivery: string }).delivery, "push");
    await new Promise(resolve => setTimeout(resolve, 25));
    assert.deepEqual(f.pushed.map(c => c.id), [body.requestId]);
    assert.equal((await f.request("/v1/calls", f.callBody("automatic"), d.token)).status, 403);
  } finally { await f.close(); rmSync(directory, { recursive: true, force: true }); }
});
test("APNs health verifies a readable P-256 key, not just nonempty settings", async () => {
  const directory = mkdtempSync(join(tmpdir(), "jimin-apns-"));
  const keyPath = join(directory, "test.p8");
  const { privateKey } = generateKeyPairSync("ec", { namedCurve: "prime256v1" });
  writeFileSync(keyPath, privateKey.export({ type: "pkcs8", format: "pem" }), { mode: 0o600 });
  const config = configuration(); config.apns = { keyPath, keyId: "ABCDE12345", teamId: "TEAM123456",
    bundleId: "com.jimin.mvp", environment: "sandbox" };
  const f = await fixture({ apns: config.apns });
  try {
    const healthy = await f.request("/health", undefined, undefined, "GET");
    assert.equal((await healthy.json() as { pushConfigured: boolean }).pushConfigured, true);
    rmSync(keyPath);
    const missingKey = await f.request("/health", undefined, undefined, "GET");
    assert.equal((await missingKey.json() as { pushConfigured: boolean }).pushConfigured, false);
  } finally { await f.close(); rmSync(directory, { recursive: true, force: true }); }
});
test("manual calls do not require APNs and session creation needs answer", async () => {
  const f = await fixture(); try {
    const d = await f.register(); const b = f.callBody(); const r = await f.request("/v1/calls", b, d.token);
    assert.equal((await r.json() as { delivery: string }).delivery, "foreground"); assert.equal(f.pushed.length, 0);
    assert.equal((await f.request(`/v1/calls/${b.requestId}/session`, { sdp: "v=0" }, d.token)).status, 409);
    assert.equal((await f.request(`/v1/calls/${b.requestId}/result`, { status: "answered" }, d.token)).status, 200);
    const answer = await f.request(`/v1/calls/${b.requestId}/session`, { sdp: "v=0\r\na=offer" }, d.token);
    assert.equal(answer.status, 200); assert.match(answer.headers.get("content-type") ?? "", /application\/sdp/);
    assert.equal(await answer.text(), "v=0\r\na=mock-answer");
    assert.equal((await f.request(`/v1/calls/${b.requestId}/session`, { sdp: "v=0" }, d.token)).status, 409);
    assert.equal((await f.request(`/v1/calls/${b.requestId}/result`, { status: "voiceConnected" }, d.token)).status, 200);
  } finally { await f.close(); }
});
test("idempotency prevents duplicate pushes and concurrent calls are discarded", async () => {
  const f = await fixture({ automaticApproved: true, appleApprovalReference: "TEST ONLY, NOT ACTUAL APPROVAL" }); try {
    const d = await f.register(); const b = f.callBody("automatic");
    assert.equal((await f.request("/v1/calls", b, d.token)).status, 201);
    assert.equal((await f.request("/v1/calls", b, d.token)).status, 200);
    assert.equal(f.pushed.length, 1);
    assert.equal((await f.request("/v1/calls", f.callBody(), d.token)).status, 409);
  } finally { await f.close(); }
});
test("stale requests and expired rings cannot connect", async () => {
  const f = await fixture(); try {
    const d = await f.register(); const old = f.callBody(); old.createdAt = "2026-09-29T09:58:59Z";
    assert.equal((await f.request("/v1/calls", old, d.token)).status, 410);
    const b = f.callBody(); await f.request("/v1/calls", b, d.token);
    f.setTime("2026-09-29T10:00:31Z"); f.expire();
    assert.equal(f.store.state.calls[b.requestId]?.status, "unanswered");
    assert.equal((await f.request(`/v1/calls/${b.requestId}/session`, { sdp: "v=0" }, d.token)).status, 409);
  } finally { await f.close(); }
});
test("profile edits affect next call but preserve an active call snapshot", async () => {
  const f = await fixture(); try {
    const d = await f.register(); const p = defaultProfile(); p.memories = [{ id: randomUUID(), text: "이번 주 글을 쓰기로 함", confirmedAt: "2026-09-29T09:00:00Z" }];
    await f.request("/v1/device/profile", p, d.token, "PUT"); const b = f.callBody(); await f.request("/v1/calls", b, d.token);
    p.character.name = "서연"; p.character.persona = "gentle"; p.memories = [];
    await f.request("/v1/device/profile", p, d.token, "PUT");
    await f.request(`/v1/calls/${b.requestId}/result`, { status: "answered" }, d.token);
    await f.request(`/v1/calls/${b.requestId}/session`, { sdp: "v=0" }, d.token);
    assert.equal(f.sessions[0]?.profile.character.name, "지민"); assert.equal(f.sessions[0]?.profile.memories.length, 1);
    await f.request(`/v1/calls/${b.requestId}/result`, { status: "ended" }, d.token);
    assert.equal(f.store.state.calls[b.requestId]?.profile, undefined, "finished call drops its private context");
    const next = f.callBody(); await f.request("/v1/calls", next, d.token);
    assert.equal(f.store.state.calls[next.requestId]?.profile?.character.name, "서연");
    assert.equal(f.store.state.calls[next.requestId]?.profile?.memories.length, 0);
  } finally { await f.close(); }
});
test("today pause uses device timezone and proactive-off prevents pushes", async () => {
  const f = await fixture({ automaticApproved: true, appleApprovalReference: "TEST ONLY" }); try {
    const d = await f.register(); const p = defaultProfile(); p.pausedDay = "2026-09-29";
    await f.request("/v1/device/profile", p, d.token, "PUT");
    assert.equal((await f.request("/v1/calls", f.callBody("automatic"), d.token)).status, 409);
    f.setTime("2026-09-29T15:01:00Z"); // Sept 30 in Korea.
    assert.equal((await f.request("/v1/calls", f.callBody("automatic"), d.token)).status, 201);
    assert.equal(f.pushed.length, 1);
  } finally { await f.close(); }
});
test("unknown usage fields and unconfirmed-memory fields cannot leak through payloads", async () => {
  const f = await fixture(); try {
    const d = await f.register();
    assert.equal((await f.request("/v1/calls", { ...f.callBody(), applicationToken: "opaque-secret" }, d.token)).status, 400);
    assert.equal((await f.request("/v1/device/profile", { ...defaultProfile(), pendingMemories: ["maybe"] }, d.token, "PUT")).status, 400);
    assert.equal(Object.keys(f.store.state.calls).length, 0);
  } finally { await f.close(); }
});
test("missing OpenAI key fails honestly instead of reporting voice-connected", async () => {
  const c = configuration(); const p = providers(c);
  await assert.rejects(p.session("v=0", defaultProfile(), randomUUID()), (e: unknown) => e instanceof ProviderError && e.code === "openai_not_configured");
  const f = await fixture({}, { session: p.session }); try {
    const d = await f.register(); const b = f.callBody(); await f.request("/v1/calls", b, d.token);
    await f.request(`/v1/calls/${b.requestId}/result`, { status: "answered" }, d.token);
    const r = await f.request(`/v1/calls/${b.requestId}/session`, { sdp: "v=0" }, d.token);
    assert.equal(r.status, 503); assert.equal(f.store.state.calls[b.requestId]?.status, "failed");
    assert.equal(f.store.state.calls[b.requestId]?.voiceConnectedAt, undefined);
  } finally { await f.close(); }
});
test("session creation uses GPT-Live JSON WebRTC and keeps the API key on the server", async () => {
  const c = configuration(); c.openaiApiKey = "sk-proj-test-only-key";
  const p = providers(c, async (url, init) => {
    assert.equal(url, "https://api.openai.com/v1/live/sessions");
    assert.equal(init?.method, "POST");
    const headers = init?.headers as Record<string, string>;
    assert.equal(headers["Content-Type"], "application/json");
    assert.equal(headers.Authorization, `Bearer ${c.openaiApiKey}`);
    assert.match(headers["OpenAI-Safety-Identifier"] ?? "", /^[a-f0-9]{64}$/);
    const sent = JSON.parse(init?.body as string);
    assert.equal(sent.session.model, "gpt-live-1");
    assert.equal(sent.session.delegation.responses.model, "gpt-6-luna");
    assert.equal(sent.transport.type, "webrtc"); assert.equal(sent.transport.sdp, "v=0\r\n");
    assert.equal(JSON.stringify(sent).includes(c.openaiApiKey), false);
    return Response.json({ session: { id: "live_test_123" }, transport: { type: "webrtc", sdp: "v=0\r\na=answer" } }, { status: 201 });
  });
  assert.deepEqual(await p.session("v=0", defaultProfile(), randomUUID()), { sdp: "v=0\r\na=answer", sessionId: "live_test_123" });
  assert.deepEqual(await p.session("v=0\r\n", defaultProfile(), randomUUID()), { sdp: "v=0\r\na=answer", sessionId: "live_test_123" });
});
test("final GPT-Live usage is recorded once for the owning device", async () => {
  const f = await fixture(); try {
    const owner = await f.register(); const other = await f.register(); const b = f.callBody();
    await f.request("/v1/calls", b, owner.token);
    await f.request(`/v1/calls/${b.requestId}/result`, { status: "answered" }, owner.token);
    await f.request(`/v1/calls/${b.requestId}/session`, { sdp: "v=0" }, owner.token);
    assert.equal((await f.request(`/v1/calls/${b.requestId}/usage`, { seconds: 11.25 }, other.token)).status, 404);
    assert.equal((await f.request(`/v1/calls/${b.requestId}/usage`, { seconds: -1 }, owner.token)).status, 400);
    assert.equal((await f.request(`/v1/calls/${b.requestId}/usage`, { seconds: 11.25 }, owner.token)).status, 200);
    assert.equal((await f.request(`/v1/calls/${b.requestId}/usage`, { seconds: 12 }, owner.token)).status, 409);
    assert.equal(f.store.state.calls[b.requestId]?.liveUsageSeconds, 11.25);
  } finally { await f.close(); }
});
test("answer cannot be converted into missed call and feedback is explicitly self-report", async () => {
  const f = await fixture(); try {
    const d = await f.register(); const b = f.callBody(); await f.request("/v1/calls", b, d.token);
    await f.request(`/v1/calls/${b.requestId}/result`, { status: "answered" }, d.token);
    assert.equal((await f.request(`/v1/calls/${b.requestId}/result`, { status: "unanswered" }, d.token)).status, 409);
    await f.request(`/v1/calls/${b.requestId}/result`, { status: "ended" }, d.token);
    assert.equal((await f.request(`/v1/calls/${b.requestId}/feedback`, { openingEngaging: "yes", appStopped: "unknown", wantsTomorrow: "yes" }, d.token)).status, 200);
    assert.equal(f.store.state.calls[b.requestId]?.observations?.openingEngaging, "yes");
    assert.equal(f.store.state.calls[b.requestId]?.observations?.appStopped, "unknown");
    assert.equal((await f.request(`/v1/calls/${b.requestId}/feedback`, { openingEngaging: "maybe", appStopped: "unknown", wantsTomorrow: "yes" }, d.token)).status, 400);
  } finally { await f.close(); }
});
test("device deletion erases server context and revokes its token", async () => {
  const f = await fixture(); try {
    const d = await f.register(); await f.request("/v1/calls", f.callBody(), d.token);
    assert.equal((await f.request("/v1/device", undefined, d.token, "DELETE")).status, 200);
    assert.equal(Object.keys(f.store.state.devices).length, 0); assert.equal(Object.keys(f.store.state.calls).length, 0);
    assert.equal((await f.request("/v1/calls", f.callBody(), d.token)).status, 401);
  } finally { await f.close(); }
});
test("GPT-Live config separates natural voice conversation from Responses tools", () => {
  const c = sessionConfig(defaultProfile(), "gpt-live-1", "gpt-6-luna");
  assert.equal(c.model, "gpt-live-1"); assert.equal(c.audio.output.voice, "marin"); assert.equal(c.store, false);
  assert.equal(c.delegation.type, "responses"); assert.equal(c.delegation.responses.model, "gpt-6-luna");
  assert.equal(c.delegation.responses.parallel_tool_calls, false);
  assert.deepEqual(c.delegation.responses.tools.map(t => t.name), ["propose_memory", "confirm_memory", "start_body_doubling", "pause_today"]);
  assert.match(c.instructions, /앱을 끄라거나/); assert.match(c.delegation.responses.instructions, /confirm_memory/);
  assert.match(c.instructions, /인사, 자기소개, 전화한 이유/);
  assert.match(c.instructions, /한 질문에 답한 뒤 사용자가 바로 끊어도/);
});

test("each call pins its random story across repeated requests, fetches and the voice session", async () => {
  const f = await fixture({ automaticApproved: true, appleApprovalReference: "TEST ONLY" });
  try {
    const d = await f.register(); const b = f.callBody("automatic");
    const response = await f.request("/v1/calls", b, d.token);
    const first = await response.json() as { instructions: string; openingCue: string };
    const plan = structuredClone(f.store.state.calls[b.requestId]?.conversation);
    assert.ok(plan); assert.equal(first.openingCue, plan.opening); assert.ok(first.instructions.includes(plan.opening));
    const history = [...f.store.state.devices[d.deviceId]!.recentConversationIds!];
    const again = await f.request("/v1/calls", b, d.token);
    const fetched = await f.request(`/v1/calls/${b.requestId}`, undefined, d.token, "GET");
    assert.equal((await again.json() as { instructions: string }).instructions, first.instructions);
    assert.equal((await fetched.json() as { instructions: string }).instructions, first.instructions);
    assert.deepEqual(f.store.state.devices[d.deviceId]?.recentConversationIds, history);
    assert.equal(f.pushed.length, 1);
    await f.request(`/v1/calls/${b.requestId}/result`, { status: "answered" }, d.token);
    await f.request(`/v1/calls/${b.requestId}/session`, { sdp: "v=0" }, d.token);
    assert.deepEqual(f.sessions[0]?.conversation, plan);
    const sentConfig = sessionConfig(f.sessions[0]!.profile, "gpt-live-1", "gpt-6-luna", f.sessions[0]!.conversation);
    assert.equal(sentConfig.instructions, first.instructions);
    await f.request(`/v1/calls/${b.requestId}/result`, { status: "ended" }, d.token);
    const next = f.callBody("manual"); await f.request("/v1/calls", next, d.token);
    const nextPlan = f.store.state.calls[next.requestId]?.conversation;
    assert.ok(nextPlan); assert.notEqual(nextPlan.id, plan.id); assert.notEqual(nextPlan.kind, plan.kind);
  } finally { await f.close(); }
});
