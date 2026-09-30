import type { Profile, Persona } from "./types.js";

export class HTTPError extends Error { constructor(public status: number, public code: string) { super(code); } }
export function record(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) throw new HTTPError(400, "invalid_object");
  return value as Record<string, unknown>;
}
export function only(o: Record<string, unknown>, keys: string[]) {
  if (Object.keys(o).some(key => !keys.includes(key))) throw new HTTPError(400, "unexpected_field");
}
export function string(value: unknown, max = 500, min = 1): string {
  if (typeof value !== "string" || value.trim().length < min || value.length > max) throw new HTTPError(400, "invalid_string");
  return value.trim();
}
export function bool(value: unknown): boolean { if (typeof value !== "boolean") throw new HTTPError(400, "invalid_boolean"); return value; }
export function uuid(value: unknown): string {
  const text = string(value, 36); if (!/^[a-f\d]{8}(?:-[a-f\d]{4}){3}-[a-f\d]{12}$/i.test(text)) throw new HTTPError(400, "invalid_uuid");
  return text.toLowerCase();
}
export function date(value: unknown): string {
  const text = string(value, 40); if (!Number.isFinite(Date.parse(text))) throw new HTTPError(400, "invalid_date"); return text;
}
export function parseProfile(value: unknown): Profile {
  const o = record(value); only(o, ["character", "memories", "proactiveEnabled", "pausedDay", "timeZone"]);
  const c = record(o.character); only(c, ["name", "persona", "voice", "nickname"]);
  const persona = string(c.persona, 20) as Persona;
  if (!["playful", "gentle", "direct"].includes(persona)) throw new HTTPError(400, "invalid_persona");
  const voice = string(c.voice, 20); if (!["marin", "coral", "shimmer"].includes(voice)) throw new HTTPError(400, "invalid_voice");
  if (!Array.isArray(o.memories) || o.memories.length > 100) throw new HTTPError(400, "invalid_memories");
  const memories = o.memories.map(value => { const m = record(value); only(m, ["id", "text", "confirmedAt"]);
    return { id: uuid(m.id), text: string(m.text, 500), confirmedAt: date(m.confirmedAt) }; });
  const timeZone = string(o.timeZone, 100);
  try { new Intl.DateTimeFormat("en", { timeZone }).format(); } catch { throw new HTTPError(400, "invalid_timezone"); }
  const pausedDay = o.pausedDay === null ? null : string(o.pausedDay, 10);
  if (pausedDay !== null && !/^\d{4}-\d{2}-\d{2}$/.test(pausedDay)) throw new HTTPError(400, "invalid_day");
  return { character: { name: string(c.name, 30), persona, voice, nickname: string(c.nickname, 30) },
    memories, proactiveEnabled: bool(o.proactiveEnabled), pausedDay, timeZone };
}
