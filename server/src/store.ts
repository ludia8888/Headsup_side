import { mkdirSync, readFileSync, writeFileSync, renameSync, existsSync, chmodSync } from "node:fs";
import { dirname } from "node:path";
import type { State } from "./types.js";

/** Single-process prototype storage. Do not run multiple workers against this file. */
export class Store {
  state: State;
  constructor(private readonly path?: string) {
    this.state = path && existsSync(path) ? JSON.parse(readFileSync(path, "utf8")) as State : { devices: {}, calls: {} };
    if (!this.state.devices || !this.state.calls) throw new Error("Invalid persisted state; refusing to reset it.");
    // A server restart cannot resume an old voice transport or deliver a stale ring.
    for (const call of Object.values(this.state.calls)) {
      if (!["declined", "unanswered", "failed", "ended"].includes(call.status)) {
        call.status = "failed"; call.endedAt = new Date().toISOString();
        delete call.profile; delete call.sessionCreating;
      }
    }
    this.save();
  }
  save(): void {
    if (!this.path) return;
    mkdirSync(dirname(this.path), { recursive: true, mode: 0o700 });
    const temporary = `${this.path}.tmp`;
    writeFileSync(temporary, JSON.stringify(this.state), { mode: 0o600 });
    renameSync(temporary, this.path); chmodSync(this.path, 0o600);
  }
}
