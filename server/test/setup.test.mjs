import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, writeFileSync, readFileSync, statSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { parseEnv } from "node:util";
import { once } from "node:events";
import { request } from "node:http";
import { createSetup, prepareEnvironment, writeEnvironment, verifyKey, keyFromFile } from "../scripts/configure-openai.mjs";

test("private env creates random pairing, preserves settings and applies owner-only permissions", () => {
  const directory = mkdtempSync(join(tmpdir(), "jimin-env-"));
  try {
    writeFileSync(join(directory, ".env.example"), "REGISTRATION_CODE=replace-me\nOPENAI_API_KEY=\nAUTO_CALL_APPROVED=false\nAPNS_KEY_PATH=\"/a path/key.p8\"\n");
    const first = prepareEnvironment(directory); const second = prepareEnvironment(directory);
    assert.equal(first.REGISTRATION_CODE, second.REGISTRATION_CODE); assert.ok(first.REGISTRATION_CODE.length >= 32);
    assert.equal(second.APNS_KEY_PATH, "/a path/key.p8"); assert.equal(second.AUTO_CALL_APPROVED, "false");
    assert.equal(statSync(join(directory, ".env")).mode & 0o777, 0o600);
    assert.equal(second.OPENAI_LIVE_BACKEND_MODEL, "gpt-6-luna");
    const key = "sk-proj-unit-test-only-not-a-real-secret-123";
    writeEnvironment(directory, { ...second, OPENAI_API_KEY: key });
    assert.equal(keyFromFile(join(directory, ".env")), key);
    assert.equal(parseEnv(readFileSync(join(directory, ".env"), "utf8")).REGISTRATION_CODE, first.REGISTRATION_CODE);
  } finally { rmSync(directory, { recursive: true }); }
});

test("key verification rejects invalid credentials without echoing the secret", async () => {
  const key = "sk-proj-unit-test-only-not-a-real-secret-123";
  await assert.rejects(verifyKey("bad"), /invalid_key_format/);
  await assert.rejects(verifyKey(key, async () => new Response("upstream secret body", { status: 401 })), { message: "key_rejected" });
  await assert.rejects(verifyKey(key, async () => new Response("", { status: 404 })), /live_model_unavailable/);
  const checked = [];
  await verifyKey(key, async (url, request) => {
    checked.push(url);
    assert.equal(request.headers.Authorization, `Bearer ${key}`);
    return Response.json({ id: url.split("/").at(-1) });
  });
  assert.deepEqual(checked, ["https://api.openai.com/v1/models/gpt-live-1", "https://api.openai.com/v1/models/gpt-6-luna"]);
});

test("local setup rejects cross-origin and rebound-host writes and never returns keys", async () => {
  const configured = [];
  const server = createSetup({ port: 0, configure: async key => configured.push(key), status: async () => ({ serverReady: true }), pair: async () => {} });
  server.listen(0, "127.0.0.1"); await once(server, "listening");
  const origin = `http://127.0.0.1:${server.address().port}`;
  try {
    const response = await fetch(origin); const html = await response.text();
    assert.equal(response.headers.get("cache-control"), "no-store");
    assert.ok(response.headers.get("content-security-policy").includes("frame-ancestors 'none'"));
    const token = html.match(/const token="([a-f0-9]+)"/)[1];
    const key = "sk-proj-unit-test-only-not-a-real-secret-123";
    const submit = (headers) => fetch(`${origin}/configure`, { method: "POST", headers: { "Content-Type": "application/json", "X-Setup-Token": token, ...headers }, body: JSON.stringify({ key }) });
    assert.equal((await submit({ Origin: "https://evil.example" })).status, 403);
    const reboundStatus = await new Promise((resolve, reject) => {
      const forged = request(`${origin}/configure`, { method: "POST", headers: {
        Host: "evil.example", Origin: origin, "Content-Type": "application/json", "X-Setup-Token": token
      } }, response => { response.resume(); response.once("end", () => resolve(response.statusCode)); });
      forged.once("error", reject); forged.end(JSON.stringify({ key }));
    });
    assert.equal(reboundStatus, 403);
    assert.equal((await submit({ Origin: origin, "X-Setup-Token": "wrong" })).status, 403);
    assert.equal(configured.length, 0);
    const success = await submit({ Origin: origin });
    assert.equal(success.status, 200); assert.equal((await success.text()).includes(key), false); assert.deepEqual(configured, [key]);
    assert.equal((await (await fetch(`${origin}/status`)).text()).includes(key), false);
  } finally { server.close(); await once(server, "close"); }
});
