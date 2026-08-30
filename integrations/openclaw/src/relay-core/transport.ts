import { CASRetryExceededError, PreconditionFailedError } from "./errors.js";
import { defaultCheckpointState, hasSeenMessage, InMemoryCheckpointStore, rememberMessage, type CheckpointStore } from "./checkpoint.js";
import { extractTimestampFromRelayKey, RelayKeyspace } from "./keyspace.js";
import { ObjectStore } from "./object-store.js";
import {
  HeadDoc,
  IdentityDoc,
  InboxBatch,
  InboxMessage,
  RelayMessage,
  RelayMessageStatus,
  RelayTextContent,
  RelayRetentionConfig,
  SendMessageOptions,
  SendMessageResult,
  SweepRuleSummary,
} from "./types.js";

async function readBodyAsText(body: unknown): Promise<string> {
  if (typeof body === "string") {
    return body;
  }
  if (!body) {
    return "";
  }
  const value = body as {
    transformToString?: () => Promise<string>;
    [Symbol.asyncIterator]?: () => AsyncIterator<unknown>;
  };
  if (typeof value.transformToString === "function") {
    return await value.transformToString();
  }
  if (typeof value[Symbol.asyncIterator] === "function") {
    const chunks: Buffer[] = [];
    for await (const chunk of value as AsyncIterable<unknown>) {
      chunks.push(Buffer.from(chunk as Uint8Array));
    }
    return Buffer.concat(chunks).toString("utf8");
  }
  return String(body);
}

export interface RelayTransportOptions {
  store: ObjectStore;
  keyspace?: RelayKeyspace;
  peerId: string;
  checkpointStore?: CheckpointStore;
  sleep?: (ms: number) => Promise<void>;
}

export class R2RelayTransport {
  readonly store: ObjectStore;
  readonly keyspace: RelayKeyspace;
  readonly peerId: string;
  readonly checkpointStore: CheckpointStore;
  readonly sleep: (ms: number) => Promise<void>;
  private readonly sendLanes = new Map<string, Promise<SendMessageResult>>();

  constructor(options: RelayTransportOptions) {
    this.store = options.store;
    this.keyspace = options.keyspace ?? new RelayKeyspace();
    this.peerId = options.peerId;
    this.checkpointStore = options.checkpointStore ?? new InMemoryCheckpointStore(defaultCheckpointState());
    this.sleep = options.sleep ?? ((ms) => new Promise((resolve) => setTimeout(resolve, ms)));
  }

  async publishIdentity(identity?: Partial<IdentityDoc>): Promise<IdentityDoc> {
    const doc: IdentityDoc = {
      display_name: this.peerId,
      role: "server",
      last_seen: this.keyspace.nowMsFactory(),
      protocol: { name: "r2-relay", version: 3 },
      software: { id: "unknown" },
      capabilities: {
        messaging: { text: true, streaming: false, reactions: false, system_events: false },
        conversations: { list: false, create: false, reset: false, archive: false, threading: false },
        agents: { list: false, multiple: false, switch: false, per_agent_models: false },
      },
      limits: null,
      agents: [],
      conversations: [],
      ...(identity ?? {}),
      peer: identity?.peer ?? this.peerId,
    };
    await this.store.putObject(this.keyspace.makeIdentityKey(doc.peer), JSON.stringify(doc), "application/json");
    return doc;
  }

  async getHeadState(peer: string): Promise<{ doc: HeadDoc; etag: string | null } | null> {
    const result = await this.store.getJsonWithEtag(this.keyspace.makeHeadKey(peer));
    return result ? { doc: result.body as HeadDoc, etag: result.etag } : null;
  }

  async getHead(peer: string): Promise<HeadDoc | null> {
    return (await this.getHeadState(peer))?.doc ?? null;
  }

  async readMessage(key: string): Promise<RelayMessage | null> {
    const response = await this.store.getObject(key);
    if (!response) {
      return null;
    }
    if (typeof response === "object" && response !== null && "payload" in response) {
      const payload = (response as { payload: unknown }).payload;
      if (typeof payload === "string") {
        return JSON.parse(payload) as RelayMessage;
      }
      return payload as RelayMessage;
    }
    if (typeof response === "object" && response !== null && "Body" in response) {
      return JSON.parse(await readBodyAsText((response as { Body: unknown }).Body)) as RelayMessage;
    }
    if (typeof response === "string") {
      return JSON.parse(response) as RelayMessage;
    }
    return response as RelayMessage;
  }

  async sendMessage(
    to: string,
    options: SendMessageOptions,
  ): Promise<SendMessageResult> {
    const previous = this.sendLanes.get(to) ?? Promise.resolve({ key: "", messageId: "" });
    const current = previous.catch(() => ({ key: "", messageId: "" })).then(() => this.sendMessageUnlocked(to, options));
    this.sendLanes.set(to, current);
    try {
      return await current;
    } finally {
      if (this.sendLanes.get(to) === current) {
        this.sendLanes.delete(to);
      }
    }
  }

  private async sendMessageUnlocked(
    to: string,
    options: SendMessageOptions,
  ): Promise<SendMessageResult> {
    const now = this.keyspace.nowMsFactory();
    const headKey = this.keyspace.makeHeadKey(to);
    for (let attempt = 0; attempt < 8; attempt += 1) {
      const currentHead = await this.getHeadState(to);
      const prevKey = currentHead?.doc.head_key ?? null;
      const key = this.keyspace.makeMsgKey(to, now);
      const msgId = this.keyspace.shortUuid();
      const msg: RelayMessage = {
        msg_id: msgId,
        from: this.peerId,
        to,
        ts_sent: now,
        prev_key: prevKey,
        route: options.route,
        content: options.content,
        delivery: options.delivery ?? null,
        status: null,
        size: options.content.type === "text"
          ? Buffer.byteLength((options.content as RelayTextContent).text ?? "")
          : null,
      };
      const newHead: HeadDoc = {
        head_key: key,
        head_msg_id: msgId,
        head_ts: now,
      };
      await this.store.putObject(key, JSON.stringify(msg), "application/json", undefined, undefined, "*");
      try {
        if (!currentHead?.doc) {
          await this.store.putObject(headKey, JSON.stringify(newHead), "application/json", undefined, undefined, "*");
        } else {
          if (!currentHead.etag) {
            throw new Error("Missing head ETag for CAS update");
          }
          await this.store.putObject(headKey, JSON.stringify(newHead), "application/json", undefined, currentHead.etag, undefined);
        }
        return { key, messageId: msgId };
      } catch (err: unknown) {
        if (!(err instanceof PreconditionFailedError)) {
          throw err;
        }
        await this.sleep(20);
      }
    }
    throw new CASRetryExceededError();
  }

  async sendStreamingSnapshots(
    to: string,
    snapshots: string[],
    options: { route: SendMessageOptions["route"]; streamId?: string | null; attachments?: RelayTextContent["attachments"] },
  ): Promise<{ streamId: string; results: SendMessageResult[] }> {
    const streamId = options.streamId ?? this.keyspace.shortUuid();
    const results: SendMessageResult[] = [];
    const nonEmpty = snapshots.filter((s) => (s ?? "").trim());
    for (let index = 0; index < nonEmpty.length; index += 1) {
      const text = nonEmpty[index] ?? "";
      const result = await this.sendMessage(to, {
        route: options.route,
        content: {
          type: "text",
          text,
          ...(options.attachments?.length ? { attachments: options.attachments } : {}),
        },
        delivery: {
          stream: {
            stream_id: streamId,
            seq: index + 1,
            state: index === nonEmpty.length - 1 ? "final" : "partial",
          },
        },
      });
      results.push(result);
    }
    return { streamId, results };
  }

  async markMessageProcessed(
    key: string,
    patch: {
      processedAt?: number;
      processedBy?: string | null;
      state?: RelayMessageStatus["state"];
      error?: string | null;
    },
  ): Promise<RelayMessage | null> {
    const msg = await this.readMessage(key);
    if (!msg) {
      return null;
    }
    const updated: RelayMessage = {
      ...msg,
      status: {
        state: patch.state ?? "done",
        processed_at: patch.processedAt ?? this.keyspace.nowMsFactory(),
        processed_by: patch.processedBy ?? this.peerId,
        error: patch.error ?? null,
      },
    };
    await this.store.putObject(key, JSON.stringify(updated), "application/json");
    return updated;
  }

  async collectInboxMessages(selfId: string, lastSeenKey: string | null): Promise<InboxBatch> {
    const head = await this.getHead(selfId);
    if (!head?.head_key || head.head_key === lastSeenKey) {
      return { head, messages: [], checkpointHeadKey: lastSeenKey };
    }
    let current: string | null = head.head_key;
    const window: InboxMessage[] = [];
    const visitedKeys = new Set<string>();
    while (current && current !== lastSeenKey) {
      if (visitedKeys.has(current)) {
        break;
      }
      visitedKeys.add(current);
      const msg = await this.readMessage(current);
      if (!msg) {
        break;
      }
      window.push({ key: current, message: msg });
      if (window.length > 500) {
        window.shift();
      }
      current = msg.prev_key ?? null;
    }
    window.reverse();
    return {
      head,
      messages: window,
      checkpointHeadKey: window[window.length - 1]?.key ?? lastSeenKey,
    };
  }

  async sweepByKeyTimestamp(prefix: string, ttlDays: number, abortSignal?: AbortSignal): Promise<SweepRuleSummary> {
    const cutoffTs = this.keyspace.nowMsFactory() - ttlDays * 24 * 60 * 60 * 1000;
    let continuationToken: string | undefined;
    let scanned = 0;
    let deleted = 0;
    while (!abortSignal?.aborted) {
      const page = await this.store.listPrefixPage(prefix, continuationToken, 1000);
      const toDelete: string[] = [];
      for (const item of page.contents) {
        const key = item.Key;
        if (!key) continue;
        scanned += 1;
        const ts = extractTimestampFromRelayKey(key);
        if (ts !== null && ts < cutoffTs) {
          toDelete.push(key);
        }
      }
      if (toDelete.length > 0) {
        await this.store.deleteObjects(toDelete);
        deleted += toDelete.length;
      }
      if (!page.isTruncated || !page.nextContinuationToken) {
        break;
      }
      continuationToken = page.nextContinuationToken;
    }
    return { prefix, scanned, deleted };
  }

  async sweepByLastModified(prefix: string, ttlDays: number, abortSignal?: AbortSignal): Promise<SweepRuleSummary> {
    const cutoffTs = this.keyspace.nowMsFactory() - ttlDays * 24 * 60 * 60 * 1000;
    let continuationToken: string | undefined;
    let scanned = 0;
    let deleted = 0;
    while (!abortSignal?.aborted) {
      const page = await this.store.listPrefixPage(prefix, continuationToken, 1000);
      const toDelete: string[] = [];
      for (const item of page.contents) {
        const key = item.Key;
        if (!key) continue;
        scanned += 1;
        const lastModified = item.LastModified?.getTime?.() ?? null;
        if (lastModified !== null && lastModified < cutoffTs) {
          toDelete.push(key);
        }
      }
      if (toDelete.length > 0) {
        await this.store.deleteObjects(toDelete);
        deleted += toDelete.length;
      }
      if (!page.isTruncated || !page.nextContinuationToken) {
        break;
      }
      continuationToken = page.nextContinuationToken;
    }
    return { prefix, scanned, deleted };
  }

  async sweepRetention(ttl: RelayRetentionConfig, abortSignal?: AbortSignal): Promise<SweepRuleSummary[]> {
    const summaries: SweepRuleSummary[] = [];
    if ((ttl.msg ?? 0) > 0) {
      summaries.push(await this.sweepByKeyTimestamp("msg/", ttl.msg as number, abortSignal));
    }
    if ((ttl.att ?? 0) > 0) {
      summaries.push(await this.sweepByKeyTimestamp("att/", ttl.att as number, abortSignal));
    }
    if ((ttl.identity ?? 0) > 0) {
      summaries.push(await this.sweepByLastModified("identity/", ttl.identity as number, abortSignal));
    }
    if ((ttl.head ?? 0) > 0) {
      summaries.push(await this.sweepByLastModified("head/", ttl.head as number, abortSignal));
    }
    return summaries;
  }

  async pollInbox(
    selfId: string,
    handler: (msg: RelayMessage, key: string) => Promise<void>,
    pollIntervalMs = 5000,
    backoffMax = 40000,
    deleteAfterProcessing = true,
    abortSignal?: AbortSignal,
  ): Promise<void> {
    let interval = pollIntervalMs;
    let state = await this.checkpointStore.load();
    while (!abortSignal?.aborted) {
      const batch = await this.collectInboxMessages(selfId, state.lastHeadKey);
      if (batch.messages.length > 0) {
        for (const item of batch.messages) {
          if (hasSeenMessage(state, { msgId: item.message.msg_id, objectKey: item.key })) {
            state = { ...state, lastHeadKey: item.key };
            await this.checkpointStore.save(state);
            continue;
          }
          await handler(item.message, item.key);
          state = rememberMessage(state, { msgId: item.message.msg_id, objectKey: item.key, at: item.message.ts_sent });
          state = { ...state, lastHeadKey: item.key, lastPollAt: this.keyspace.nowMsFactory() };
          await this.checkpointStore.save(state);
          if (deleteAfterProcessing) {
            await this.store.deleteObject(item.key);
          }
        }
        interval = pollIntervalMs;
        await this.sleep(interval);
        continue;
      }
      state = { ...state, lastPollAt: this.keyspace.nowMsFactory() };
      await this.checkpointStore.save(state);
      await this.sleep(interval);
      if (!batch.head?.head_key) {
        interval = Math.min(interval * 2, backoffMax);
      }
    }
  }
}
