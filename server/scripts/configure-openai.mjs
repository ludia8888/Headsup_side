import { createServer } from "node:http";
import { randomBytes, timingSafeEqual } from "node:crypto";
import { existsSync, readFileSync, writeFileSync, renameSync, chmodSync, mkdirSync, openSync, closeSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { parseEnv } from "node:util";
import { spawn, execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);
const serverDirectory = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const setupPort = 8788;
const origin = `http://127.0.0.1:${setupPort}`;

export function prepareEnvironment(directory) {
  const path = resolve(directory, ".env");
  const values = parseEnv(readFileSync(existsSync(path) ? path : resolve(directory, ".env.example"), "utf8"));
  if (!values.REGISTRATION_CODE || values.REGISTRATION_CODE.startsWith("replace-") || values.REGISTRATION_CODE.length < 16) {
    values.REGISTRATION_CODE = randomBytes(24).toString("hex");
  }
  values.HOST = "127.0.0.1";
  values.PORT = "8787";
  delete values.OPENAI_REALTIME_MODEL;
  values.OPENAI_LIVE_BACKEND_MODEL = "gpt-6-luna";
  writeEnvironment(directory, values);
  return values;
}

export function writeEnvironment(directory, values) {
  const path = resolve(directory, ".env");
  const temporary = `${path}.${randomBytes(8).toString("hex")}.tmp`;
  const text = Object.entries(values).map(([name, value]) => `${name}=${JSON.stringify(value)}`).join("\n") + "\n";
  writeFileSync(temporary, text, { mode: 0o600, flag: "wx" });
  renameSync(temporary, path);
  chmodSync(path, 0o600);
}

export function keyFromFile(path) {
  const text = readFileSync(resolve(path), "utf8").trim();
  return text.startsWith("sk-") && !text.includes("\n") ? text : parseEnv(text).OPENAI_API_KEY ?? "";
}

export async function verifyKey(key, request = fetch, backendModel = "gpt-6-luna") {
  if (typeof key !== "string" || !/^sk-[A-Za-z0-9_-]{20,512}$/.test(key)) throw new Error("invalid_key_format");
  for (const model of ["gpt-live-1", backendModel]) {
    let response;
    try {
      response = await request(`https://api.openai.com/v1/models/${encodeURIComponent(model)}`, {
        headers: { Authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(20_000)
      });
    } catch { throw new Error("openai_connection_failed"); }
    if (!response.ok) {
      await response.arrayBuffer();
      const code = { 401: "key_rejected", 403: "key_permission_missing", 404: "live_model_unavailable", 429: "openai_rate_limited" }[response.status];
      throw new Error(code ?? "openai_check_failed");
    }
    const result = await response.json();
    if (result.id !== model) throw new Error("live_model_unavailable");
  }
}

export function createSetup({ configure, status, pair, port = setupPort }) {
  const secret = randomBytes(32).toString("hex");
  const nonce = randomBytes(24).toString("base64");
  const page = readFileSync(resolve(serverDirectory, "scripts/setup.html"), "utf8")
    .replaceAll("__NONCE__", nonce).replace("__CSRF__", secret);
  let configuring = false;
  const allowedErrors = new Set(["invalid_key_format", "key_rejected", "key_permission_missing", "live_model_unavailable",
    "openai_rate_limited", "openai_check_failed", "openai_connection_failed", "server_start_failed", "server_already_running", "simulator_unavailable"]);
  const server = createServer(async (request, response) => {
    const actualPort = server.address().port;
    const expectedOrigin = `http://127.0.0.1:${actualPort}`;
    const finish = (code, value) => {
      response.writeHead(code, { "Content-Type": "application/json; charset=utf-8" });
      response.end(JSON.stringify(value));
    };
    response.setHeader("Cache-Control", "no-store");
    response.setHeader("Referrer-Policy", "no-referrer");
    response.setHeader("X-Content-Type-Options", "nosniff");
    response.setHeader("Content-Security-Policy", `default-src 'none'; script-src 'nonce-${nonce}'; style-src 'nonce-${nonce}'; connect-src 'self'; frame-ancestors 'none'; form-action 'self'; base-uri 'none'`);
    try {
      if (request.headers.host !== `127.0.0.1:${actualPort}`) { finish(403, { error: "local_only" }); return; }
      const path = new URL(request.url ?? "/", expectedOrigin).pathname;
      if (request.method === "GET" && path === "/") {
        response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" }); response.end(page); return;
      }
      if (request.method === "GET" && path === "/status") { finish(200, await status()); return; }
      if (request.method !== "POST" || !["/configure", "/pair"].includes(path)) { finish(404, { error: "not_found" }); return; }
      const submitted = request.headers["x-setup-token"];
      if (request.headers.origin !== expectedOrigin || typeof submitted !== "string" || submitted.length !== secret.length ||
          !timingSafeEqual(Buffer.from(submitted), Buffer.from(secret))) { finish(403, { error: "setup_token_required" }); return; }
      if (path === "/pair") { await pair(); finish(200, { launched: true }); return; }
      if (configuring) { finish(409, { error: "setup_busy" }); return; }
      if (request.headers["content-type"] !== "application/json") { finish(415, { error: "json_required" }); return; }
      const chunks = []; let size = 0;
      for await (const chunk of request) {
        size += chunk.length;
        if (size > 2048) { finish(413, { error: "body_too_large" }); return; }
        chunks.push(chunk);
      }
      let payload;
      try { payload = JSON.parse(Buffer.concat(chunks).toString("utf8")); }
      catch { finish(400, { error: "invalid_json" }); return; }
      if (!payload || typeof payload !== "object" || Object.keys(payload).join() !== "key") { finish(400, { error: "invalid_payload" }); return; }
      configuring = true;
      try { await configure(payload.key); finish(200, await status()); }
      finally { payload.key = ""; configuring = false; }
    } catch (error) {
      // Never return arbitrary upstream errors, request bodies, environment values, or keys.
      finish(400, { error: allowedErrors.has(error?.message) ? error.message : "setup_failed" });
    }
  });
  server.requestTimeout = 30_000; server.headersTimeout = 5_000;
  return server;
}

async function main() {
  process.umask(0o077);
  let values = prepareEnvironment(serverDirectory);
  const privateDirectory = resolve(serverDirectory, ".local");
  mkdirSync(privateDirectory, { recursive: true, mode: 0o700 }); chmodSync(privateDirectory, 0o700);
  const receiptPath = resolve(privateDirectory, "setup-status.json");
  let receipt = existsSync(receiptPath) ? JSON.parse(readFileSync(receiptPath, "utf8")) : {};
  let backend;
  const health = async () => {
    try {
      const response = await fetch("http://127.0.0.1:8787/health", { signal: AbortSignal.timeout(1000) });
      return response.ok ? await response.json() : undefined;
    } catch { return undefined; }
  };
  const startBackend = async () => {
    if (backend && backend.exitCode === null) {
      await new Promise(resolveExit => { backend.once("exit", resolveExit); backend.kill("SIGTERM"); });
    } else if (await health()) { throw new Error("server_already_running"); }
    const log = openSync(resolve(privateDirectory, "server.log"), "a", 0o600);
    const environment = { ...process.env };
    for (const name of Object.keys(values)) delete environment[name];
    backend = spawn(process.execPath, ["--env-file=.env", "dist/src/main.js"], {
      cwd: serverDirectory, env: environment, detached: true, stdio: ["ignore", log, log]
    });
    closeSync(log); backend.unref();
    for (let attempt = 0; attempt < 40; attempt++) {
      if (await health()) {
        writeFileSync(resolve(privateDirectory, "server-process.json"), JSON.stringify({ pid: backend.pid, port: 8787 }), { mode: 0o600 }); return;
      }
      if (backend.exitCode !== null) break;
      await new Promise(resume => setTimeout(resume, 125));
    }
    throw new Error("server_start_failed");
  };
  const pair = async () => {
    try {
      const { stdout } = await run("xcrun", ["simctl", "list", "devices", "booted", "--json"], { timeout: 10_000 });
      const devices = Object.values(JSON.parse(stdout).devices).flat().filter(device => device.state === "Booted");
      // Never choose between multiple active simulators on the user's behalf.
      if (devices.length !== 1) throw new Error();
      const url = new URL("jimin-local://connect"); url.searchParams.set("code", values.REGISTRATION_CODE);
      await run("xcrun", ["simctl", "openurl", devices[0].udid, url.toString()], { timeout: 10_000 });
    } catch { throw new Error("simulator_unavailable"); }
  };
  const status = async () => {
    const h = await health();
    let calls = [];
    try { calls = Object.values(JSON.parse(readFileSync(resolve(serverDirectory, values.DATA_FILE ?? "./data/state.json"), "utf8")).calls); } catch {}
    return { keyConfigured: Boolean(values.OPENAI_API_KEY), keyVerified: Boolean(receipt.keyVerifiedAt && receipt.model === "gpt-live-1"),
      serverReady: h?.ok === true, voiceConfigured: h?.voiceConfigured === true, model: h?.model ?? "gpt-live-1",
      automaticApproved: h?.automaticApproved === true,
      liveSessionCreated: calls.some(call => call.sessionCreated),
      voiceConnected: calls.some(call => Boolean(call.voiceConnectedAt)) };
  };
  const configure = async key => {
    await verifyKey(key, fetch, values.OPENAI_LIVE_BACKEND_MODEL);
    values = { ...values, OPENAI_API_KEY: key };
    writeEnvironment(serverDirectory, values);
    await startBackend();
    receipt = { keyVerifiedAt: new Date().toISOString(), model: "gpt-live-1" };
    writeFileSync(receiptPath, JSON.stringify(receipt), { mode: 0o600 });
    try { await pair(); } catch {}
  };
  await startBackend();
  const argument = process.argv.indexOf("--key-file");
  if (argument >= 0) {
    if (!process.argv[argument + 1]) throw new Error("missing_key_file");
    await configure(keyFromFile(process.argv[argument + 1]));
  } else if (values.OPENAI_API_KEY) {
    try {
      await verifyKey(values.OPENAI_API_KEY, fetch, values.OPENAI_LIVE_BACKEND_MODEL);
      receipt = { keyVerifiedAt: new Date().toISOString(), model: "gpt-live-1" };
      writeFileSync(receiptPath, JSON.stringify(receipt), { mode: 0o600 });
    } catch { receipt = {}; }
  }
  const server = createSetup({ configure, status, pair });
  server.listen(setupPort, "127.0.0.1", () => console.log(`Private local OpenAI setup: ${origin}. No secrets are printed.`));
  for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => server.close(() => process.exit(0)));
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch(() => { console.error("Setup could not start. Check ports 8787/8788 and the private server log. No secret was printed."); process.exitCode = 1; });
}
