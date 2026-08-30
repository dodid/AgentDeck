import type { OutboundMediaAccess } from "openclaw/plugin-sdk/media-runtime";
import type { ResolvedR2RelayAccount } from "./config.js";
import type { AttachmentRef, RelayContent, RelayRoute } from "./protocol.js";
import type { Service } from "./service.js";
import { getOrCreateService, emitRelayDebug, touchRuntime, type RelayPollLog } from "./lifecycle.js";
import { parseRelayTarget } from "./target.js";
import {
  buildRelayAttachments,
  describeLocalMediaReference,
  resolveRelayPayloadMediaUrls,
} from "./media.js";
import { resolveR2RelayAccount } from "./config.js";
import { schedulePublishedIdentityRefresh } from "./session-publication.js";

export async function sendRelayPayloadMessage(params: {
  cfg: Record<string, unknown>;
  to: string;
  payload: {
    text?: string | null;
    mediaUrl?: string | null;
    mediaUrls?: string[] | null;
    channelData?: Record<string, unknown> | null;
  };
  accountId?: string | null;
  log?: RelayPollLog;
  source?: string;
  meta?: {
    route?: RelayRoute | null;
    workspaceDir?: string | null;
    mediaAccess?: OutboundMediaAccess;
    mediaLocalRoots?: readonly string[];
    mediaReadFile?: (filePath: string) => Promise<Buffer>;
  };
}) {
  const account = resolveR2RelayAccount({ cfg: params.cfg as never, accountId: params.accountId });
  const service = getOrCreateService(account);
  const target = parseRelayTarget(params.to);
  const text = params.payload.text ?? "";
  const mediaUrls = resolveRelayPayloadMediaUrls(params.payload);
  const route: RelayRoute = params.meta?.route ?? {
    agent_id: agentIdFromConversationId(target.conversationId ?? "main") ?? "main",
    conversation_id: target.conversationId ?? null,
    instance_id: null,
  };

  emitRelayDebug(params.log, `[${account.accountId}] outbound relay send starting`, {
    source: params.source ?? "unknown",
    to: params.to,
    peer: target.peer,
    route,
    mediaCount: mediaUrls.length,
    hasText: Boolean(text.trim()),
  });

  const attachmentBuild = await buildRelayAttachments({
    account,
    service,
    targetPeer: target.peer,
    mediaUrls,
    workspaceDir: params.meta?.workspaceDir ?? null,
    mediaAccess: params.meta?.mediaAccess,
    mediaLocalRoots: params.meta?.mediaLocalRoots,
    mediaReadFile: params.meta?.mediaReadFile,
    log: params.log,
    source: params.source,
  });
  const attachments = attachmentBuild.attachments;

  emitRelayDebug(params.log, `[${account.accountId}] sending outbound relay message`, {
    source: params.source ?? "unknown",
    attachmentCount: attachments.length,
    hasText: Boolean(text.trim()),
    targetPeer: target.peer,
    route,
  });

  if (mediaUrls.length > 0 && attachments.length === 0) {
    const detail = attachmentBuild.failures.length > 0
      ? attachmentBuild.failures.join(" | ")
      : "no attachment objects were created";
    throw new Error(`Failed to prepare outbound relay attachments: ${detail}`);
  }

  const fallbackText = text.trim() || (mediaUrls.length > 0 && attachments.length === 0
    ? mediaUrls.map((url) => `[Attachment unavailable: ${describeLocalMediaReference(url)}]`).join("\n")
    : text);

  const result = await service.sendMessage(target.peer, {
    route,
    content: relayContentFromPayload(fallbackText, attachments, params.payload.channelData),
  });
  emitRelayDebug(params.log, `[${account.accountId}] outbound relay message sent`, {
    source: params.source ?? "unknown",
    messageId: result.messageId,
    attachmentCount: attachments.length,
  });

  touchRuntime(account.accountId, {
    lastOutboundAt: Date.now(),
    lastError: null,
  });
  schedulePublishedIdentityRefresh(service, account);
  return {
    channel: "r2-relay-channel",
    to: params.to.trim(),
    messageId: result.messageId,
    timestamp: Date.now(),
  };
}

function relayContentFromPayload(
  text: string,
  attachments: AttachmentRef[],
  channelData?: Record<string, unknown> | null,
): RelayContent {
  const execApproval = readExecApprovalChannelData(channelData);
  if (execApproval?.state === "pending") {
    return {
      type: "approval_request",
      approval_id: execApproval.approvalId,
      approval_kind: execApproval.approvalKind === "plugin" ? "tool" : execApproval.approvalKind,
      title: firstNonEmptyLine(text) ?? "Approval required",
      body: text.trim() || null,
      allowed_decisions: execApproval.allowedDecisions.length > 0
        ? execApproval.allowedDecisions
        : ["allow-once", "allow-always", "deny"],
      metadata: {
        openclaw: execApproval.raw,
      },
    };
  }

  return {
    type: "text",
    text,
    attachments: attachments.length > 0 ? attachments : undefined,
  };
}

function readExecApprovalChannelData(channelData?: Record<string, unknown> | null): {
  approvalId: string;
  approvalKind: "exec" | "tool" | "custom" | "plugin";
  allowedDecisions: string[];
  state: string | null;
  raw: Record<string, unknown>;
} | null {
  const raw = channelData?.execApproval;
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) {
    return null;
  }
  const record = raw as Record<string, unknown>;
  const approvalId = typeof record.approvalId === "string" ? record.approvalId.trim() : "";
  if (!approvalId) {
    return null;
  }
  const approvalKind = normalizeApprovalKind(record.approvalKind);
  const allowedDecisions = Array.isArray(record.allowedDecisions)
    ? record.allowedDecisions.filter((value): value is string => typeof value === "string" && value.trim().length > 0)
    : [];
  return {
    approvalId,
    approvalKind,
    allowedDecisions,
    state: typeof record.state === "string" ? record.state : null,
    raw: record,
  };
}

function normalizeApprovalKind(value: unknown): "exec" | "tool" | "custom" | "plugin" {
  if (value === "exec" || value === "tool" || value === "custom" || value === "plugin") {
    return value;
  }
  return "exec";
}

function firstNonEmptyLine(value: string): string | null {
  for (const line of value.split(/\r?\n/)) {
    const trimmed = line.trim();
    if (trimmed) {
      return trimmed;
    }
  }
  return null;
}

function agentIdFromConversationId(conversationId: string): string | null {
  const parts = conversationId.split(":");
  if (parts.length >= 2 && parts[0] === "agent" && parts[1]?.trim()) {
    return parts[1].trim();
  }
  return null;
}
