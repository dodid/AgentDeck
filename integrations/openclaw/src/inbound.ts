import fs from "node:fs";
import path from "node:path";
import { createChannelReplyPipeline } from "openclaw/plugin-sdk/channel-reply-pipeline";
import {
  buildChannelInboundMediaPayload,
  toInboundMediaFacts,
  type ChannelInboundMediaInput,
} from "openclaw/plugin-sdk/channel-inbound";
import { getRelayRuntime } from "./runtime.js";
import { rememberConversationTarget } from "./conversation-targets.js";
import type { ResolvedR2RelayAccount } from "./config.js";
import type { AttachmentRef, RelayRoute, ServerLimits } from "./protocol.js";
import type { Service } from "./service.js";
import { emitRelayDebug, touchRuntime, type RelayPollLog } from "./lifecycle.js";
import { sendRelayPayloadMessage } from "./outbound.js";
import {
  formatAttachmentContext,
  normalizeAttachmentContentType,
  resolveInboundAttachmentBestEffortMaxBytes,
  resolveInboundAttachmentMaxBytes,
  resolveRelayPayloadMediaUrls,
} from "./media.js";
import {
  agentIdFromSessionKey,
  readPublishedConversationEntry,
  schedulePublishedIdentityRefresh,
} from "./session-publication.js";

export async function dispatchInboundMessage(params: {
  cfg: Record<string, unknown>;
  account: ResolvedR2RelayAccount;
  service: Service;
  log?: RelayPollLog;
  senderId: string;
  text: string;
  timestamp: number;
  messageId: string;
  route: RelayRoute;
  attachments?: AttachmentRef[];
}): Promise<void> {
  const core = getRelayRuntime();
  const resolvedRoute = core.channel.routing.resolveAgentRoute({
    cfg: params.cfg as never,
    channel: "r2-relay-channel",
    accountId: params.account.accountId,
    peer: {
      kind: "direct",
      id: params.senderId,
    },
  });
  const conversationId = (params.route.conversation_id ?? "").trim();
  const route = conversationId
    ? {
        ...resolvedRoute,
        agentId: params.route.agent_id?.trim() || agentIdFromSessionKey(conversationId),
        sessionKey: conversationId,
      }
    : resolvedRoute;

  const storePath = core.channel.session.resolveStorePath(
    (params.cfg as { session?: { store?: string } }).session?.store,
    {
      agentId: route.agentId,
    },
  );

  const attachmentContext = formatAttachmentContext(params.attachments);
  const agentText = attachmentContext
    ? `${params.text}\n\n${attachmentContext}`
    : params.text;

  const inboundMedia: ChannelInboundMediaInput[] = [];
  if (params.attachments) {
    const logger = getRelayRuntime().logging.getChildLogger();
    for (const att of params.attachments) {
      if (!att.key) {
        continue;
      }

      const maxBytes = resolveInboundAttachmentMaxBytes(att);
      const bestEffortMaxBytes = resolveInboundAttachmentBestEffortMaxBytes(att, maxBytes);
      try {
        logger.info(
          `[${params.account.accountId}] staging inbound relay attachment key=${att.key} name=${att.file_name ?? ""} type=${att.content_type ?? ""} kind=${att.kind ?? "unknown"} declaredSize=${att.size ?? -1} maxBytes=${maxBytes} bestEffortMaxBytes=${bestEffortMaxBytes}`,
        );
        logger.info(`[${params.account.accountId}] inbound relay attachment fetching object key=${att.key}`);
        const fetchedObject = await params.service.getAttachmentObject(att.key);
        if (!fetchedObject?.Body) {
          throw new Error(`AttachmentNotFound: key=${att.key}`);
        }
        const chunks: Buffer[] = [];
        let total = 0;
        let nextProgressBytes = 1024 * 1024;
        for await (const chunk of fetchedObject.Body as AsyncIterable<Uint8Array | Buffer | string>) {
          const buf = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk as Uint8Array);
          chunks.push(buf);
          total += buf.length;
          if (total >= nextProgressBytes) {
            logger.info(
              `[${params.account.accountId}] inbound relay attachment streaming progress key=${att.key} downloadedBytes=${total} declaredSize=${att.size ?? -1}`,
            );
            nextProgressBytes += 1024 * 1024;
          }
          if (total > bestEffortMaxBytes) {
            throw new Error(`AttachmentTooLarge: streamedSize>${bestEffortMaxBytes}`);
          }
        }
        const buffer = Buffer.concat(chunks);
        logger.info(`[${params.account.accountId}] inbound relay attachment fetched object key=${att.key} bytes=${buffer.length}`);
        const contentType = normalizeAttachmentContentType(
          fetchedObject.ContentType,
          att.content_type,
          att.file_name,
        );
        const saved = await core.channel.media.saveMediaBuffer(
          buffer,
          contentType,
          "inbound",
          bestEffortMaxBytes,
          att.file_name ?? undefined,
        );

        const workspaceMediaPath = stageInboundMediaForAgentWorkspace({
          workspaceDir: resolveAgentWorkspaceDirFromConfig(params.cfg as Record<string, unknown>, route.agentId),
          sourcePath: saved.path,
          originalFileName: att.file_name,
          buffer,
        });

        inboundMedia.push({
          path: workspaceMediaPath,
          contentType: saved.contentType ?? contentType ?? att.content_type ?? "application/octet-stream",
          kind: att.kind === "file" ? "document" : att.kind,
          messageId: params.messageId,
        });
        logger.info(
          `[${params.account.accountId}] staged inbound relay attachment key=${att.key} savedPath=${saved.path} workspacePath=${workspaceMediaPath} savedType=${saved.contentType ?? contentType ?? att.content_type ?? "application/octet-stream"} bytes=${buffer.length}`,
        );
      } catch (err) {
        getRelayRuntime().logging.getChildLogger().error(
          `[${params.account.accountId}] failed to stage inbound relay attachment ${att.key}: ${String(err)}`,
        );
      }
    }
  }

  const envelopeOptions = core.channel.reply.resolveEnvelopeFormatOptions(params.cfg as never);
  const previousTimestamp = core.channel.session.readSessionUpdatedAt({
    storePath,
    sessionKey: route.sessionKey,
  });
  const body = core.channel.reply.formatAgentEnvelope({
    channel: "R2 Relay",
    from: params.senderId,
    timestamp: params.timestamp,
    previousTimestamp,
    envelope: envelopeOptions,
    body: agentText,
  });
  const mediaPayload = buildChannelInboundMediaPayload(
    toInboundMediaFacts(inboundMedia, { messageId: params.messageId }),
  );

  const ctxPayload = core.channel.reply.finalizeInboundContext({
    Body: body,
    BodyForAgent: agentText,
    RawBody: params.text,
    CommandBody: params.text,
    CommandAuthorized: true,
    From: `r2-relay-channel:${params.senderId}`,
    To: `r2-relay-channel:${params.account.serverId}`,
    SessionKey: route.sessionKey,
    AccountId: route.accountId,
    ChatType: "direct",
    ConversationLabel: params.senderId,
    SenderId: params.senderId,
    Provider: "r2-relay-channel",
    Surface: "r2-relay-channel",
    MessageSid: params.messageId,
    Timestamp: params.timestamp,
    OriginatingChannel: "r2-relay-channel",
    OriginatingTo: `r2-relay-channel:${params.account.serverId}`,
    ...mediaPayload,
  });

  rememberConversationTarget({
    channel: "r2-relay-channel",
    accountId: params.account.accountId,
    conversationId: ctxPayload.From,
    threadId: null,
    peer: params.senderId,
    relayConversationId: route.sessionKey,
  });

  const conversationEntry = await readPublishedConversationEntry(route.sessionKey);
  const outboundMeta = {
    route: conversationEntry?.route ?? {
      agent_id: route.agentId,
      conversation_id: route.sessionKey,
      instance_id: null,
    } as RelayRoute,
  };
  const createStreamId = () => `stream-${params.messageId}-${Date.now()}`;
  const streamState = {
    streamId: createStreamId(),
    seq: 0,
    lastText: "",
    lastEmitAt: 0,
    active: false,
  };
  const partialIntervalMs = 2000;
  const partialMinGrowthChars = 120;

  const resetStream = () => {
    streamState.streamId = createStreamId();
    streamState.seq = 0;
    streamState.lastText = "";
    streamState.lastEmitAt = 0;
    streamState.active = false;
  };

  const normalizeStreamText = (text: string) => text.replace(/\r\n/g, "\n");

  const emitPartialSnapshot = async (text: string) => {
    const normalized = normalizeStreamText(text);
    if (!normalized.trim()) {
      return;
    }
    if (streamState.active && normalized === streamState.lastText) {
      return;
    }
    if (streamState.active && streamState.lastText && !normalized.startsWith(streamState.lastText)) {
      return;
    }
    if (!streamState.active) {
      streamState.streamId = createStreamId();
      streamState.seq = 0;
      streamState.lastText = "";
      streamState.lastEmitAt = 0;
      streamState.active = true;
    }
    streamState.seq += 1;
    streamState.lastText = normalized;
    streamState.lastEmitAt = Date.now();
    try {
      await params.service.sendMessage(params.senderId, {
        route: outboundMeta.route,
        content: { type: "text", text: normalized },
        delivery: {
          stream: {
            stream_id: streamState.streamId,
            seq: streamState.seq,
            state: "partial",
          },
        },
      });
      emitRelayDebug(params.log, `[${params.account.accountId}] sent relay partial reply snapshot`, {
        senderId: params.senderId,
        route: outboundMeta.route,
        streamId: streamState.streamId,
        streamSeq: streamState.seq,
        textLength: normalized.length,
      });
      touchRuntime(params.account.accountId, {
        lastOutboundAt: Date.now(),
        lastError: null,
      });
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      params.log?.error?.(`[${params.account.accountId}] failed to send relay partial reply snapshot: ${message}`, {
        senderId: params.senderId,
        route: outboundMeta.route,
        streamId: streamState.streamId,
        streamSeq: streamState.seq,
        textLength: normalized.length,
      });
      throw err;
    }
  };

  await core.channel.session.recordInboundSession({
    storePath,
    sessionKey: ctxPayload.SessionKey ?? route.sessionKey,
    ctx: ctxPayload,
    onRecordError: () => {},
  });
  schedulePublishedIdentityRefresh(params.service, params.account);

  if (params.messageId && params.senderId) {
    try {
      await sendProcessedConfirmation({
        account: params.account,
        service: params.service,
        targetPeer: params.senderId,
        targetMessageId: params.messageId,
        route: outboundMeta.route,
        log: params.log,
      });
    } catch (confirmErr) {
      params.log?.warn?.(`[${params.account.accountId}] failed to send processed confirmation: ${confirmErr instanceof Error ? confirmErr.message : String(confirmErr)}`, {
        senderId: params.senderId,
        messageId: params.messageId,
        route: outboundMeta.route,
      });
    }
  }

  const { onModelSelected, ...replyPipeline } = createChannelReplyPipeline({
    cfg: params.cfg as never,
    agentId: route.agentId,
    channel: "r2-relay-channel",
    accountId: params.account.accountId,
  });

  await core.channel.reply.dispatchReplyWithBufferedBlockDispatcher({
    ctx: ctxPayload,
    cfg: params.cfg as never,
    dispatcherOptions: {
      ...replyPipeline,
      deliver: async (payload) => {
        const text = normalizeStreamText(payload.text ?? "");
        const mediaUrls = resolveRelayPayloadMediaUrls(payload);
        emitRelayDebug(params.log, `[${params.account.accountId}] relay final payload received`, {
          senderId: params.senderId,
          route: outboundMeta.route,
          hasText: Boolean(text.trim()),
          mediaUrl: payload.mediaUrl ?? null,
          mediaUrls,
          rawMediaUrls: payload.mediaUrls ?? null,
          textHasMediaDirective: text.includes("MEDIA:"),
        });
        if (streamState.active && text.trim().length > 0) {
          streamState.lastText = text;
          streamState.lastEmitAt = Date.now();
        }

        const finalStream = streamState.active
          ? {
              stream_id: streamState.streamId,
              seq: streamState.seq + 1,
              state: "final" as const,
            }
          : undefined;

        try {
          await sendRelayPayloadMessage({
            cfg: params.cfg,
            to: params.senderId,
            payload: {
              ...payload,
              text,
              mediaUrls,
              mediaUrl: mediaUrls[0],
              channelData: payload.channelData,
            },
            accountId: params.account.accountId,
            log: params.log,
            source: "replyPipeline.final",
            meta: {
              route: outboundMeta.route,
              workspaceDir: resolveAgentWorkspaceDirFromConfig(params.cfg as Record<string, unknown>, route.agentId),
              stream: finalStream,
            },
          });
          emitRelayDebug(params.log, `[${params.account.accountId}] sent relay final reply`, {
            senderId: params.senderId,
            route: outboundMeta.route,
            textLength: text.length,
            hasChannelData: Boolean(payload.channelData && Object.keys(payload.channelData).length > 0),
            mediaCount: mediaUrls.length,
          });
          resetStream();
        } catch (err) {
          const message = err instanceof Error ? err.message : String(err);
          params.log?.error?.(`[${params.account.accountId}] failed to send relay final reply: ${message}`, {
            senderId: params.senderId,
            route: outboundMeta.route,
            textLength: text.length,
            hasChannelData: Boolean(payload.channelData && Object.keys(payload.channelData).length > 0),
            mediaCount: mediaUrls.length,
          });
          throw err;
        }
      },
      onError: (err) => {
        throw err instanceof Error ? err : new Error(String(err));
      },
    },
    replyOptions: {
      onModelSelected,
      onAssistantMessageStart: async () => {},
      onReasoningEnd: async () => {},
      onPartialReply: async (payload) => {
        const text = payload.text ?? "";
        const normalized = normalizeStreamText(text);
        if (!normalized.trim()) {
          return;
        }
        if (streamState.active && normalized === streamState.lastText) {
          return;
        }
        const now = Date.now();
        const growth = normalized.length - streamState.lastText.length;
        const enoughTimePassed = now - streamState.lastEmitAt >= partialIntervalMs;
        const enoughGrowth = growth >= partialMinGrowthChars;
        if (!enoughTimePassed && !enoughGrowth) {
          return;
        }
        await emitPartialSnapshot(normalized);
      },
    },
  });
}

export function formatInboundRelayBody(msg: {
  content?: {
    type?: string | null;
    text?: string | null;
    attachments?: { file_name?: string | null; kind?: string | null }[] | null;
    emoji?: string | null;
    target_msg_id?: string | null;
    remove?: boolean | null;
    approval_id?: string | null;
    decision?: string | null;
  } | null;
}): string {
  const content = msg.content ?? {};
  const contentType = content.type ?? "text";

  if (contentType === "reaction") {
    const emoji = content.emoji ?? "";
    const target = content.target_msg_id ?? "unknown";
    return content.remove
      ? `Reaction removed: ${emoji || "(cleared)"} on msg ${target}`
      : `Reaction added: ${emoji || "(empty)"} on msg ${target}`;
  }

  if (contentType === "approval_response") {
    const approvalId = content.approval_id?.trim();
    const decision = content.decision?.trim();
    return approvalId && decision ? `/approve ${approvalId} ${decision}` : "";
  }

  const body = (contentType === "text" ? content.text : null)?.trim() ?? "";
  if (body) return body;
  const atts = contentType === "text" ? content.attachments : null;
  if (atts && atts.length > 0) {
    if (atts.length === 1) {
      const att = atts[0];
      const label = att.file_name ?? (att.kind && att.kind !== "unknown" ? att.kind : "attachment");
      return `[Sent ${label}]`;
    }
    return `[Sent ${atts.length} attachments]`;
  }
  return body;
}

export function classifyInboundRelayMessageFailure(err: unknown): "error" {
  const message = err instanceof Error ? err.message : String(err);
  if (message.includes("AttachmentTooLarge")) {
    return "error";
  }
  if (message.includes("AttachmentNotFound")) {
    return "error";
  }
  return "error";
}

export function resolvePublishedServerLimits(limits: {
  maxImageBytes: number;
  maxVideoBytes: number;
  maxAudioBytes: number;
  maxDocumentBytes: number;
}): ServerLimits {
  return {
    inbound_attachment_max_bytes: {
      image: limits.maxImageBytes,
      video: limits.maxVideoBytes,
      audio: limits.maxAudioBytes,
      file: limits.maxDocumentBytes,
    },
    oversize_attachment_behavior: "reject",
  };
}

async function sendProcessedConfirmation(params: {
  account: ResolvedR2RelayAccount;
  service: Service;
  targetPeer: string;
  targetMessageId: string;
  route: RelayRoute;
  log?: RelayPollLog;
}): Promise<void> {
  emitRelayDebug(params.log, `[${params.account.accountId}] sending processed confirmation`, {
    targetPeer: params.targetPeer,
    targetMessageId: params.targetMessageId,
    route: params.route,
  });
  const result = await params.service.sendMessage(params.targetPeer, {
    route: params.route,
    content: {
      type: "reaction",
      target_msg_id: params.targetMessageId,
      emoji: "✅",
      remove: false,
    },
  });
  emitRelayDebug(params.log, `[${params.account.accountId}] processed confirmation sent`, {
    targetPeer: params.targetPeer,
    targetMessageId: params.targetMessageId,
    confirmationKey: result.key,
    confirmationMessageId: result.messageId,
    route: params.route,
  });
}

function resolveAgentWorkspaceDirFromConfig(cfg: Record<string, unknown>, agentId?: string | null): string {
  const agents = (cfg.agents ?? {}) as {
    defaults?: { workspace?: string };
    list?: Array<{ id?: string; workspace?: string }>;
  };
  const normalizedAgentId = agentId?.trim() || "main";
  const matched = agents.list?.find((entry) => entry?.id === normalizedAgentId)?.workspace?.trim();
  if (matched) {
    return path.resolve(matched);
  }
  const fallback = agents.defaults?.workspace?.trim();
  if (fallback) {
    return path.resolve(fallback);
  }
  return path.join(process.env.HOME ?? process.cwd(), ".openclaw", `workspace${normalizedAgentId === "main" ? "" : `-${normalizedAgentId}`}`);
}

function stageInboundMediaForAgentWorkspace(params: {
  workspaceDir: string;
  sourcePath: string;
  originalFileName?: string | null;
  buffer: Buffer;
}): string {
  const sourceBase = path.basename(params.sourcePath);
  const originalBase = params.originalFileName ? sanitizeWorkspaceMediaFileName(params.originalFileName) : "";
  const fileName = sourceBase || originalBase || `relay-inbound-${Date.now()}`;
  const mediaDir = path.join(params.workspaceDir, "media", "inbound");
  const workspacePath = path.join(mediaDir, fileName);
  fs.mkdirSync(mediaDir, { recursive: true });
  fs.writeFileSync(workspacePath, params.buffer, { mode: 0o600 });
  return workspacePath;
}

function sanitizeWorkspaceMediaFileName(value: string): string {
  return path.basename(value).replace(/[^\p{L}\p{N}._-]+/gu, "_").replace(/^_+|_+$/g, "").slice(0, 100);
}
