export type Persona = "playful" | "gentle" | "direct";
export type CallStatus = "requested" | "ringing" | "answered" | "voiceConnected" | "declined" | "unanswered" | "failed" | "ended";
export interface Profile {
  character: { name: string; persona: Persona; voice: string; nickname: string };
  memories: { id: string; text: string; confirmedAt: string }[];
  proactiveEnabled: boolean;
  pausedDay: string | null;
  timeZone: string;
}
export interface Device {
  id: string; tokenHash: string; createdAt: string; profile: Profile;
  voipToken?: string; pushEnvironment?: "sandbox" | "production";
  recentConversationIds?: string[];
}
export interface Call {
  id: string; deviceId: string; mode: "manual" | "automatic"; status: CallStatus;
  requestedAt: string; receivedAt: string; expiresAt: string;
  displayName: string;
  answeredAt?: string; voiceConnectedAt?: string; endedAt?: string;
  liveFinalizedAt?: string; liveUsageSeconds?: number;
  profile?: Profile; sessionCreating?: boolean; sessionCreated?: boolean;
  conversation?: ConversationPlan;
  openaiSessionId?: string;
  observations?: { openingEngaging?: "yes" | "no" | "unknown"; appStopped: "yes" | "no" | "unknown"; wantsTomorrow: "yes" | "no" | "unknown" };
}
export interface State { devices: Record<string, Device>; calls: Record<string, Call> }
export interface Config {
  registrationCode: string; dataFile?: string; openaiApiKey: string; liveModel: "gpt-live-1"; backendModel: string;
  automaticApproved: boolean; appleApprovalReference: string;
  apns: { keyPath: string; keyId: string; teamId: string; bundleId: string; environment: "sandbox" | "production" };
}
export interface Providers {
  push(device: Device, call: Call): Promise<void>;
  session(offer: string, profile: Profile, deviceId: string, conversation?: ConversationPlan): Promise<{ sdp: string; sessionId?: string }>;
  hangup?(sessionId: string): Promise<void>;
  preview(profile: Profile): Promise<Uint8Array>;
}
export const terminal = (s: CallStatus) => ["declined", "unanswered", "failed", "ended"].includes(s);
export const defaultProfile = (): Profile => ({
  character: { name: "지민", persona: "playful", voice: "marin", nickname: "자기야" },
  memories: [], proactiveEnabled: true, pausedDay: null, timeZone: "Asia/Seoul"
});
import type { ConversationPlan } from "./conversation.js";
