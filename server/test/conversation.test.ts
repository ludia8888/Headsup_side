import test from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { chooseConversation, nextConversationHistory, conversationIdeas, conversationHistoryLimit } from "../src/conversation.js";
import { Store } from "../src/store.js";
import { defaultProfile } from "../src/types.js";

test("random selection can reach different ideas and excludes recent stories and consecutive genres", () => {
  assert.notEqual(chooseConversation([], () => 0).id, chooseConversation([], max => max - 1).id);
  let recent: string[] = ["unknown-from-an-older-version"];
  let lastKind: string | undefined;
  const reached = new Set<string>();
  for (let i = 0; i < 80; i++) {
    const plan = chooseConversation(recent, max => i % max);
    assert.ok(!recent.includes(plan.id), "a recent story should not repeat");
    assert.notEqual(plan.kind, lastKind, "consecutive calls should differ in kind");
    assert.ok(conversationIdeas.some(idea => idea.id === plan.id));
    reached.add(plan.id); recent = nextConversationHistory(recent, plan); lastKind = plan.kind;
    assert.ok(recent.length <= conversationHistoryLimit);
  }
  assert.ok(reached.size > conversationHistoryLimit, "the chooser should rotate beyond one small subset");
});

test("a server restart keeps story history, and old devices without history remain compatible", () => {
  const directory = mkdtempSync(join(tmpdir(), "jimin-stories-"));
  try {
    const path = join(directory, "state.json"); const store = new Store(path);
    const first = chooseConversation([]);
    store.state.devices.a = { id: "a", tokenHash: "test-only", createdAt: new Date().toISOString(),
      profile: defaultProfile(), recentConversationIds: [first.id] };
    store.state.devices.legacy = { id: "legacy", tokenHash: "test-only-legacy",
      createdAt: new Date().toISOString(), profile: defaultProfile() };
    store.save();
    const restored = new Store(path);
    const next = chooseConversation(restored.state.devices.a!.recentConversationIds);
    assert.notEqual(next.id, first.id);
    assert.deepEqual(restored.state.devices.a!.recentConversationIds, [first.id]);
    assert.ok(chooseConversation(restored.state.devices.legacy!.recentConversationIds));
  } finally { rmSync(directory, { recursive: true, force: true }); }
});
