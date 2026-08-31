import fs from "node:fs/promises";
import { maxBytesForKind } from "openclaw/plugin-sdk/media-runtime";
import { getRelayConfig, getRelayRuntime } from "./runtime.js";
import { IDENTITY_REFRESH_INTERVAL_MS, RELAY_PLUGIN_VERSION, Service } from "./service.js";
import type { ResolvedR2RelayAccount } from "./config.js";
import type { ConversationDescriptor, AgentDescriptor, ServerLimits } from "./protocol.js";

const MAX_IMAGE_BYTES = maxBytesForKind("image");
const MAX_VIDEO_BYTES = maxBytesForKind("video");
const MAX_AUDIO_BYTES = maxBytesForKind("audio");
const MAX_DOCUMENT_BYTES = maxBytesForKind("document");

const publishedSessionSignatures = new Map<string, string>();
const publishedIdentityAt = new Map<string, number>();
const scheduledIdentityRefreshes = new Map<string, ReturnType<typeof setTimeout>>();

export async function syncPublishedIdentity(
  service: Service,
  account: ResolvedR2RelayAccount,
  force = false,
): Promise<void> {
  const { agents, conversations } = await collectPublishedConversations(account);
  const modelCapabilities = await collectPublishedModelCapabilities(account);
  const signature = JSON.stringify({ agents, conversations, modelCapabilities });
  const previousSignature = publishedSessionSignatures.get(account.accountId);
  const now = Date.now();
  const lastPublishedAt = publishedIdentityAt.get(account.accountId) ?? 0;
  const heartbeatDue = now - lastPublishedAt >= IDENTITY_REFRESH_INTERVAL_MS;
  if (previousSignature === signature && !heartbeatDue) {
    return;
  }

  await service.publishIdentity({
    peer: account.serverId,
    display_name: deriveGatewayDisplayName(account.serverId),
    role: "server",
    last_seen: now,
    protocol: { name: "r2-relay", version: 3 },
    software: { id: "openclaw", name: "OpenClaw", version: RELAY_PLUGIN_VERSION },
    capabilities: {
      messaging: { text: true, streaming: true, reactions: true, system_events: true },
      conversations: { list: true, create: false, reset: false, archive: false, threading: false },
      agents: { list: true, multiple: agents.length > 1, switch: true, per_agent_models: Boolean(modelCapabilities) },
      attachments: {
        supported: true,
        kinds: ["image", "video", "audio", "file", "unknown"],
        max_bytes_by_kind: resolvePublishedAttachmentCapabilityLimits(),
        oversize_behavior: "reject",
      },
      approvals: {
        exec: true,
        tool: false,
        custom: false,
      },
      extensions: null,
    },
    limits: resolvePublishedServerLimits(),
    agents: modelCapabilities
      ? agents.map((a) => ({ ...a, models: modelCapabilities }))
      : agents,
    conversations,
  });
  publishedSessionSignatures.set(account.accountId, signature);
  publishedIdentityAt.set(account.accountId, now);
}

export function schedulePublishedIdentityRefresh(
  service: Service,
  account: ResolvedR2RelayAccount,
  delayMs = 250,
): void {
  const existing = scheduledIdentityRefreshes.get(account.accountId);
  if (existing) {
    clearTimeout(existing);
  }

  const timer = setTimeout(() => {
    scheduledIdentityRefreshes.delete(account.accountId);
    void syncPublishedIdentity(service, account).catch(() => {});
  }, Math.max(0, delayMs));
  scheduledIdentityRefreshes.set(account.accountId, timer);
}

async function collectPublishedModelCapabilities(
  _account: ResolvedR2RelayAccount,
): Promise<{ available: { id: string; label?: string | null; provider?: string | null }[]; default?: string | null } | null> {
  try {
    const cfg = getRelayConfig();
    const availableByID = new Map<string, { id: string; label?: string | null; provider?: string | null }>();
    const addModel = (modelRef?: string | null, label?: string | null) => {
      const normalized = modelRef?.trim();
      if (!normalized) {
        return;
      }
      const existing = availableByID.get(normalized);
      availableByID.set(normalized, {
        id: normalized,
        label: existing?.label ?? (label?.trim() || undefined),
        provider: normalized.includes("/") ? normalized.split("/")[0] : null,
      });
    };
    const addModelConfig = (value?: string | { primary?: string | null; fallbacks?: Array<string | null> | null } | null) => {
      if (!value) {
        return;
      }
      if (typeof value === "string") {
        addModel(value);
        return;
      }
      addModel(value.primary);
      for (const fallback of value.fallbacks ?? []) {
        addModel(fallback);
      }
    };

    for (const [key, entry] of Object.entries(cfg.agents?.defaults?.models ?? {})) {
      const alias = (entry as { alias?: unknown } | null | undefined)?.alias;
      addModel(key, typeof alias === "string" ? alias : null);
    }
    addModelConfig(cfg.agents?.defaults?.model);
    for (const agent of cfg.agents?.list ?? []) {
      addModelConfig(agent?.model);
      addModelConfig(agent?.subagents?.model);
    }

    const available = Array.from(availableByID.values()).sort((lhs, rhs) => lhs.id.localeCompare(rhs.id));
    const modelConfig = cfg.agents?.defaults?.model;
    const defaultModel = typeof modelConfig === "string"
      ? modelConfig
      : modelConfig && typeof modelConfig.primary === "string"
        ? modelConfig.primary
        : null;
    return available.length > 0 ? { available, default: defaultModel } : null;
  } catch {
    return null;
  }
}

async function collectPublishedConversations(_account: ResolvedR2RelayAccount): Promise<{ agents: AgentDescriptor[]; conversations: ConversationDescriptor[] }> {
  const configuredAgents = listConfiguredAgents();
  const agents: AgentDescriptor[] = configuredAgents.map((agent) => ({
    id: agent.id,
    display_name: agent.name ?? null,
    description: null,
    is_default: agent.id === "main",
    models: null,
    default_route: { agent_id: agent.id, conversation_id: null, instance_id: null },
    capabilities: null,
  }));
  const conversations: ConversationDescriptor[] = [];

  for (const agent of configuredAgents) {
    const agentId = agent.id;
    try {
      const store = await readPublishedSessionStore(agentId);
      for (const [sessionKey, entry] of Object.entries(store)) {
        if (typeof sessionKey !== "string" || !sessionKey.startsWith(`agent:${agentId}:`)) {
          continue;
        }
        if (!shouldPublishIdentitySession(sessionKey)) {
          continue;
        }
        conversations.push(identityConversationDocFromEntry(sessionKey, entry));
      }
    } catch {
      // No session store yet for this agent.
    }
  }

  return {
    agents,
    conversations: conversations.sort((a, b) => (b.updated_at ?? 0) - (a.updated_at ?? 0)),
  };
}

function shouldPublishIdentitySession(sessionKey: string): boolean {
  const normalized = sessionKey.trim().toLowerCase();
  if (!normalized) {
    return false;
  }
  if (normalized.startsWith("cron:")) {
    return false;
  }
  if (normalized.startsWith("dreaming-")) {
    return false;
  }

  const parts = normalized.split(":");
  if (parts.length >= 3 && parts[0] === "agent") {
    const scopedKey = parts.slice(2).join(":");
    if (scopedKey.startsWith("cron:")) {
      return false;
    }
  }

  return true;
}

function listConfiguredAgents(): Array<{ id: string; name?: string | null }> {
  const cfg = getRelayConfig() as { agents?: { main?: { name?: string | null }; list?: Array<{ id?: string | null; name?: string | null }> } };
  const agents = new Map<string, { id: string; name?: string | null }>([
    ["main", { id: "main", name: cfg.agents?.main?.name ?? null }],
  ]);
  for (const agent of cfg.agents?.list ?? []) {
    const id = agent?.id?.trim();
    if (id && !agents.has(id)) {
      agents.set(id, { id, name: agent.name ?? null });
    }
  }
  return Array.from(agents.values());
}

export function agentIdFromSessionKey(sessionKey: string): string {
  const parts = sessionKey.split(":");
  if (parts.length >= 2 && parts[0] === "agent" && parts[1]?.trim()) {
    return parts[1].trim();
  }
  return "main";
}

function identityConversationDocFromEntry(sessionKey: string, entry: any): ConversationDescriptor {
  const agentId = agentIdFromSessionKey(sessionKey);
  return {
    id: sessionKey,
    display_title: resolveConversationDisplayTitle(sessionKey, entry),
    route: {
      agent_id: agentId,
      conversation_id: sessionKey,
      instance_id: readInstanceId(entry),
    },
    source: conversationSourceFromEntry(sessionKey, entry),
    updated_at: typeof entry?.updatedAt === "number" ? entry.updatedAt : null,
  };
}

async function readPublishedSessionStore(agentId = "main"): Promise<Record<string, any>> {
  const storePath = getRelayRuntime().channel.session.resolveStorePath(undefined, {
    agentId,
  });
  const raw = await fs.readFile(storePath, "utf8");
  return JSON.parse(raw) as Record<string, any>;
}

export async function readPublishedConversationEntry(sessionKey: string): Promise<ConversationDescriptor | null> {
  try {
    const store = await readPublishedSessionStore(agentIdFromSessionKey(sessionKey));
    const entry = store[sessionKey];
    if (!entry) {
      return null;
    }
    return identityConversationDocFromEntry(sessionKey, entry);
  } catch {
    return null;
  }
}

function displayTitleFromConversationId(conversationId: string): string {
  const parts = conversationId.split(":");
  if (parts[0] === "agent" && parts[1]) {
    const remainder = parts.slice(2).join(":");
    return remainder || parts[1];
  }
  return conversationId;
}

function resolveConversationDisplayTitle(conversationId: string, entry: any): string {
  const candidates = [
    typeof entry?.label === "string" ? entry.label : null,
    typeof entry?.displayName === "string" ? entry.displayName : null,
    typeof entry?.derivedTitle === "string" ? entry.derivedTitle : null,
  ];
  for (const candidate of candidates) {
    const trimmed = candidate?.trim();
    if (trimmed) {
      return trimmed;
    }
  }
  return displayTitleFromConversationId(conversationId);
}

function conversationSourceFromEntry(sessionKey: string, entry: any): ConversationDescriptor["source"] {
  const parsed = parseSessionKeySource(sessionKey);
  const peerKind = firstNonEmptyString(entry?.peerKind, parsed.peerKind);
  const threadId = firstNonEmptyString(entry?.threadId, parsed.threadId);
  const channel = normalizeChannelName(entry?.channel ?? parsed.channel ?? "local");

  return {
    channel,
    chat_kind: normalizeChatKind(peerKind, threadId),
    account_id: firstNonEmptyString(entry?.accountId, entry?.workspaceId, entry?.orgId),
    account_display: firstNonEmptyString(entry?.accountDisplay, entry?.workspaceName, entry?.orgName),
    space_id: firstNonEmptyString(entry?.spaceId, entry?.guildId, entry?.teamId),
    space_display: firstNonEmptyString(entry?.spaceDisplay, entry?.guildName, entry?.teamName),
    chat_id: peerKind === "direct" ? null : firstNonEmptyString(entry?.chatId, entry?.peerId, parsed.peerId),
    chat_display: peerKind === "direct" ? null : firstNonEmptyString(entry?.chatDisplay, entry?.channelName, entry?.roomName),
    participant_id: peerKind === "direct" ? firstNonEmptyString(entry?.participantId, entry?.peerId, parsed.peerId) : null,
    participant_display: peerKind === "direct"
      ? firstNonEmptyString(entry?.participantDisplay, entry?.peerDisplayName, entry?.senderName, entry?.userName)
      : null,
    thread_id: threadId,
    thread_display: firstNonEmptyString(entry?.threadDisplay, entry?.threadName),
    sharing: normalizeSharing(entry?.sharing, entry?.sharedMultiUserSession),
  };
}

function readInstanceId(entry: any): string | null {
  return firstNonEmptyString(entry?.instanceId, entry?.sessionId, entry?.runtimeSessionId);
}

function parseSessionKeySource(sessionKey: string): { channel: string | null; peerKind: string | null; peerId: string | null; threadId: string | null } {
  const parts = sessionKey.split(":");
  const scoped = parts[0] === "agent" ? parts.slice(2) : parts;
  const threadIndex = scoped.indexOf("thread");
  const base = threadIndex >= 0 ? scoped.slice(0, threadIndex) : scoped;
  const threadId = threadIndex >= 0 ? scoped.slice(threadIndex + 1).join(":") || null : null;
  return {
    channel: base[0] ?? null,
    peerKind: base[1] ?? null,
    peerId: base.length > 2 ? base.slice(2).join(":") : null,
    threadId,
  };
}

function normalizeChannelName(value: unknown): string {
  const normalized = firstNonEmptyString(value) ?? "local";
  return normalized === "r2-relay-channel" ? "r2_relay" : normalized;
}

function normalizeChatKind(peerKind: string | null, threadId: string | null): "dm" | "group" | "channel" | "thread" | null {
  if (threadId) {
    return "thread";
  }
  switch (peerKind) {
    case "direct":
    case "dm":
    case "im":
      return "dm";
    case "group":
      return "group";
    case "channel":
      return "channel";
    default:
      return null;
  }
}

function normalizeSharing(value: unknown, sharedFallback: unknown): "private" | "shared" | "per-user" | null {
  const normalized = firstNonEmptyString(value)?.toLowerCase();
  if (normalized === "private" || normalized === "shared" || normalized === "per-user") {
    return normalized;
  }
  if (sharedFallback === true) {
    return "shared";
  }
  return null;
}

function firstNonEmptyString(...values: unknown[]): string | null {
  for (const value of values) {
    if (typeof value === "string" && value.trim()) {
      return value.trim();
    }
  }
  return null;
}

function deriveGatewayDisplayName(serverId: string): string {
  const cfg = getRelayConfig();
  const candidates = [
    (cfg as { identity?: { name?: string } }).identity?.name,
    (cfg as { agents?: { main?: { name?: string } } }).agents?.main?.name,
    (cfg as { assistant?: { name?: string } }).assistant?.name,
    (cfg as { gateway?: { name?: string } }).gateway?.name,
  ];
  for (const candidate of candidates) {
    const trimmed = candidate?.trim();
    if (trimmed) {
      return trimmed;
    }
  }
  return serverId
    .replace(/[-_.]+/g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .replace(/\b\w/g, (ch) => ch.toUpperCase()) || "Gateway";
}

function resolvePublishedServerLimits(): ServerLimits {
  return {
    inbound_attachment_max_bytes: {
      image: MAX_IMAGE_BYTES,
      video: MAX_VIDEO_BYTES,
      audio: MAX_AUDIO_BYTES,
      file: MAX_DOCUMENT_BYTES,
    },
    oversize_attachment_behavior: "reject",
  };
}

function resolvePublishedAttachmentCapabilityLimits() {
  return {
    image: MAX_IMAGE_BYTES,
    video: MAX_VIDEO_BYTES,
    audio: MAX_AUDIO_BYTES,
    file: MAX_DOCUMENT_BYTES,
  };
}
