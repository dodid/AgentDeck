import { createDefaultChannelRuntimeState } from "openclaw/plugin-sdk/status-helpers";
import { hasSeenMessage, rememberMessage, saveCheckpointState, type RelayCheckpointState } from "./checkpoint-store.js";
import type { ResolvedR2RelayAccount } from "./config.js";
import type { AttachmentRef, RelayMessage } from "./protocol.js";
import { Service } from "./service.js";

export type RelayRuntimeState = Omit<
  ReturnType<typeof createDefaultChannelRuntimeState>,
  "running" | "lastStartAt" | "lastStopAt" | "lastError"
> & {
  running: boolean;
  lastStartAt: number | null;
  lastStopAt: number | null;
  lastError: string | null;
  serverId: string | null;
  endpoint: string | null;
  bucket: string | null;
  lastPollAt: number | null;
  checkpointHeadKey: string | null;
  lastInboundAt: number | null;
  lastOutboundAt: number | null;
};

export type RelayPollLog = {
  info?: (message: string, meta?: Record<string, unknown>) => void;
  debug?: (message: string, meta?: Record<string, unknown>) => void;
  warn?: (message: string, meta?: Record<string, unknown>) => void;
  error?: (message: string, meta?: Record<string, unknown>) => void;
};

export interface DispatchInboundMessageParams {
  cfg: Record<string, unknown>;
  account: ResolvedR2RelayAccount;
  service: Service;
  log?: RelayPollLog;
  senderId: string;
  text: string;
  timestamp: number;
  messageId: string;
  route: RelayMessage["route"];
  attachments?: AttachmentRef[];
}

export interface PollRelayInboxParams {
  cfg: Record<string, unknown>;
  account: ResolvedR2RelayAccount;
  service: Service;
  abortSignal?: AbortSignal;
  log?: RelayPollLog;
  setStatus: (patch: unknown) => void;
  state: RelayCheckpointState;
  syncPublishedIdentity: (service: Service, account: ResolvedR2RelayAccount, force?: boolean) => Promise<void>;
  dispatchInboundMessage: (params: DispatchInboundMessageParams) => Promise<void>;
  formatInboundRelayBody: (msg: RelayMessage) => string;
  classifyInboundRelayMessageFailure: (err: unknown) => "error";
}

const activeServices = new Map<string, Service>();
const runtimeSnapshots = new Map<string, RelayRuntimeState>();

export function createDefaultRuntimeState(accountId: string): RelayRuntimeState {
  return createDefaultChannelRuntimeState(accountId, {
    serverId: null,
    endpoint: null,
    bucket: null,
    lastPollAt: null,
    checkpointHeadKey: null,
    lastInboundAt: null,
    lastOutboundAt: null,
  });
}

export function getRuntimeSnapshot(accountId: string): RelayRuntimeState | undefined {
  return runtimeSnapshots.get(accountId);
}

export function setRuntimeSnapshot(accountId: string, snapshot: RelayRuntimeState): void {
  runtimeSnapshots.set(accountId, snapshot);
}

export function touchRuntime(accountId: string, patch: Partial<RelayRuntimeState>): void {
  const current = runtimeSnapshots.get(accountId) ?? createDefaultRuntimeState(accountId);
  runtimeSnapshots.set(accountId, {
    ...current,
    ...patch,
  });
}

export function getOrCreateService(account: ResolvedR2RelayAccount): Service {
  const existing = activeServices.get(account.accountId);
  if (existing) {
    return existing;
  }

  const created = new Service({
    endpoint: account.endpoint,
    bucket: account.bucket,
    region: account.region,
    accessKeyId: account.accessKeyId,
    secretAccessKey: account.secretAccessKey,
    forcePathStyle: account.forcePathStyle,
    peerId: account.serverId,
  });
  activeServices.set(account.accountId, created);
  return created;
}

export function clearService(accountId: string): void {
  activeServices.delete(accountId);
}

export function redactEndpoint(endpoint: string): string {
  try {
    const url = new URL(endpoint);
    return `${url.protocol}//${url.host}`;
  } catch {
    return endpoint;
  }
}

export function emitRelayDebug(log: RelayPollLog | undefined, message: string, meta?: Record<string, unknown>) {
  if (log?.debug) {
    log.debug(message, meta);
    return;
  }
  if (log?.info) {
    log.info(message, meta);
    return;
  }
  if (meta) {
    console.log(message, JSON.stringify(meta));
    return;
  }
  console.log(message);
}

function summarizeRelayMessageForLog(msg: {
  msg_id?: string | null;
  from?: string | null;
  to?: string | null;
  route?: { agent_id?: string | null; conversation_id?: string | null } | null;
  content?: { type?: string | null } | null;
  status?: { state?: string | null } | null;
}) {
  return {
    msgId: msg.msg_id ?? null,
    contentType: msg.content?.type ?? "text",
    from: msg.from ?? null,
    to: msg.to ?? null,
    agentId: msg.route?.agent_id ?? null,
    conversationId: msg.route?.conversation_id ?? null,
    statusState: msg.status?.state ?? null,
  };
}

export async function pollRelayInbox(params: PollRelayInboxParams): Promise<void> {
  const {
    cfg,
    account,
    service,
    abortSignal,
    log,
    setStatus,
    syncPublishedIdentity,
    dispatchInboundMessage,
    formatInboundRelayBody,
    classifyInboundRelayMessageFailure,
  } = params;
  let interval = account.pollIntervalMs;
  let state = params.state;

  while (!abortSignal?.aborted) {
    try {
      const pollStartedAt = Date.now();
      const wakeGapThresholdMs = Math.max(120_000, interval * 5);
      if (state.lastPollAt && pollStartedAt - state.lastPollAt >= wakeGapThresholdMs) {
        log?.info?.(`[${account.accountId}] detected long poll gap; refreshing published identity`, {
          lastPollAt: state.lastPollAt,
          pollStartedAt,
          gapMs: pollStartedAt - state.lastPollAt,
          wakeGapThresholdMs,
        });
        await syncPublishedIdentity(service, account, true);
      }

      const batch = await service.collectInboxMessages(account.serverId, state.lastHeadKey);
      const now = Date.now();
      state = { ...state, lastPollAt: now };
      touchRuntime(account.accountId, {
        lastPollAt: now,
        checkpointHeadKey: state.lastHeadKey,
      });
      setStatus({
        accountId: account.accountId,
        lastPollAt: now,
        checkpointHeadKey: state.lastHeadKey,
      });

      if (batch.messages.length > 0) {
        let batchFailed = false;

        for (const item of batch.messages) {
          if (abortSignal?.aborted) {
            break;
          }

          const msg = item.message;
          try {
            emitRelayDebug(log, `[${account.accountId}] evaluating inbound relay message`, {
              objectKey: item.key,
              ...summarizeRelayMessageForLog(msg),
            });
            if (msg.from === account.serverId) {
              emitRelayDebug(log, `[${account.accountId}] skipping self-authored relay message`, {
                objectKey: item.key,
                ...summarizeRelayMessageForLog(msg),
              });
              await service.markMessageProcessed(item.key, {
                state: "done",
                processedBy: account.serverId,
              });
              state = rememberMessage(state, {
                msgId: msg.msg_id,
                objectKey: item.key,
                at: msg.ts_sent,
              });
              state = { ...state, lastHeadKey: item.key };
              continue;
            }
            if (msg.to !== account.serverId) {
              emitRelayDebug(log, `[${account.accountId}] skipping relay message addressed to different peer`, {
                objectKey: item.key,
                expectedTo: account.serverId,
                ...summarizeRelayMessageForLog(msg),
              });
              state = { ...state, lastHeadKey: item.key };
              continue;
            }
            if (hasSeenMessage(state, { msgId: msg.msg_id, objectKey: item.key })) {
              emitRelayDebug(log, `[${account.accountId}] skipping already-seen relay message`, {
                objectKey: item.key,
                ...summarizeRelayMessageForLog(msg),
              });
              state = { ...state, lastHeadKey: batch.checkpointHeadKey };
              continue;
            }

            let processedState: "done" | "error" = "done";
            try {
              await dispatchInboundMessage({
                cfg,
                account,
                service,
                log,
                text: formatInboundRelayBody(msg),
                senderId: msg.from,
                timestamp: msg.ts_sent || Date.now(),
                messageId: msg.msg_id,
                route: msg.route,
                attachments: (msg.content?.type === "text" ? msg.content.attachments : null) ?? [],
              });

              emitRelayDebug(log, `[${account.accountId}] dispatched inbound relay message to gateway`, {
                objectKey: item.key,
                ...summarizeRelayMessageForLog(msg),
              });
            } catch (messageErr) {
              const message = messageErr instanceof Error ? messageErr.message : String(messageErr);
              processedState = classifyInboundRelayMessageFailure(messageErr);
              touchRuntime(account.accountId, { lastError: message });
              setStatus({ accountId: account.accountId, lastError: message });
              log?.error?.(
                `[${account.accountId}] relay inbound handling failed for ${item.key}: ${message}`,
                {
                  ...summarizeRelayMessageForLog(msg),
                  objectKey: item.key,
                  processedState,
                },
              );
            }

            try {
              await service.markMessageProcessed(item.key, {
                state: processedState,
                processedBy: account.serverId,
              });
            } catch (markErr) {
              log?.warn?.(
                `[${account.accountId}] failed to persist processed state for ${item.key}: ${markErr instanceof Error ? markErr.message : String(markErr)}`,
              );
            }

            state = rememberMessage(state, {
              msgId: msg.msg_id,
              objectKey: item.key,
              at: msg.ts_sent,
            });
            state = { ...state, lastHeadKey: item.key };
            touchRuntime(account.accountId, {
              lastInboundAt: msg.ts_sent || Date.now(),
              checkpointHeadKey: state.lastHeadKey,
              lastError: processedState === "done" ? null : getRuntimeSnapshot(account.accountId)?.lastError ?? null,
            });
            setStatus({
              accountId: account.accountId,
              lastInboundAt: msg.ts_sent || Date.now(),
              checkpointHeadKey: state.lastHeadKey,
              lastError: processedState === "done" ? null : getRuntimeSnapshot(account.accountId)?.lastError ?? null,
            });
          } catch (messageErr) {
            const message = messageErr instanceof Error ? messageErr.message : String(messageErr);
            touchRuntime(account.accountId, { lastError: message });
            setStatus({ accountId: account.accountId, lastError: message });
            log?.error?.(`[${account.accountId}] relay inbound handling failed for ${item.key}: ${message}`);
            batchFailed = true;
            break;
          }
        }

        if (!batchFailed) {
          state = {
            ...state,
            lastHeadKey: batch.checkpointHeadKey ?? state.lastHeadKey,
          };
        }
        await saveCheckpointState(state, account.accountId);
        touchRuntime(account.accountId, {
          checkpointHeadKey: state.lastHeadKey,
          lastPollAt: state.lastPollAt,
          lastInboundAt: state.lastInboundAt,
        });
        setStatus({
          accountId: account.accountId,
          checkpointHeadKey: state.lastHeadKey,
          lastPollAt: state.lastPollAt,
          lastInboundAt: state.lastInboundAt,
        });
        if (!batchFailed) {
          interval = account.pollIntervalMs;
        }
      }

      await syncPublishedIdentity(service, account);
      await sleep(interval, abortSignal);
      if (!batch.head?.head_key) {
        interval = Math.min(interval * 2, account.backoffMaxMs);
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : String(err);
      touchRuntime(account.accountId, { lastError: message });
      setStatus({ accountId: account.accountId, lastError: message });
      log?.error?.(`[${account.accountId}] relay poll failed: ${message}`);
      await saveCheckpointState(state, account.accountId);
      await sleep(interval, abortSignal);
      interval = Math.min(interval * 2, account.backoffMaxMs);
    }
  }

  await saveCheckpointState(state, account.accountId);
}

export async function runSweeperLoop(params: {
  account: ResolvedR2RelayAccount;
  service: Service;
  abortSignal?: AbortSignal;
  log?: RelayPollLog;
}): Promise<void> {
  await sleep(60_000, params.abortSignal);
  while (!params.abortSignal?.aborted) {
    try {
      const summaries = await params.service.sweepRetention(params.account.ttl, params.abortSignal);
      const summaryText = summaries.map((item) => `${item.prefix} scanned=${item.scanned} deleted=${item.deleted}`).join("; ");
      params.log?.info?.(`[${params.account.accountId}] relay sweeper complete${summaryText ? `: ${summaryText}` : ""}`);
    } catch (err) {
      params.log?.warn?.(`[${params.account.accountId}] relay sweeper failed: ${err instanceof Error ? err.message : String(err)}`);
    }
    await sleep(24 * 60 * 60 * 1000, params.abortSignal);
  }
}

function sleep(ms: number, abortSignal?: AbortSignal): Promise<void> {
  if (ms <= 0) {
    return Promise.resolve();
  }
  return new Promise((resolve) => {
    const timer = setTimeout(() => {
      abortSignal?.removeEventListener("abort", onAbort);
      resolve();
    }, ms);
    const onAbort = () => {
      clearTimeout(timer);
      abortSignal?.removeEventListener("abort", onAbort);
      resolve();
    };
    abortSignal?.addEventListener("abort", onAbort, { once: true });
  });
}
