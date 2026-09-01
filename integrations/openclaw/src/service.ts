import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import {
  PreconditionFailedError,
  R2RelayTransport,
  type HeadDoc,
  type IdentityDoc,
  type InboxBatch,
  type RelayMessage,
  type RelayRetentionConfig,
  type SendMessageOptions,
  type SendMessageResult,
  type SweepRuleSummary,
} from "./relay-core/index.js";
import { R2Relay } from "./protocol.js";
import { R2Client } from "./r2client.js";

export const IDENTITY_REFRESH_INTERVAL_MS = 12 * 60 * 60 * 1000;

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function resolvePluginVersion(): string {
  try {
    const pkgPath = path.join(__dirname, "..", "package.json");
    const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8")) as { version?: string };
    const version = pkg.version?.trim();
    return version || "0.0.0";
  } catch {
    return "0.0.0";
  }
}

export const RELAY_PLUGIN_VERSION = resolvePluginVersion();

export interface ServiceConfig {
  endpoint: string;
  bucket: string;
  region?: string;
  accessKeyId?: string;
  secretAccessKey?: string;
  forcePathStyle?: boolean;
  peerId: string;
}

export interface InboxMessage {
  key: string;
  message: RelayMessage;
}

class R2ObjectStoreAdapter {
  constructor(private readonly client: R2Client) {}

  async putObject(
    key: string,
    body: Buffer | string,
    contentType?: string,
    tagging?: string,
    ifMatch?: string,
    ifNoneMatch?: string,
  ) {
    try {
      return await this.client.putObject(key, body, contentType, tagging, ifMatch, ifNoneMatch);
    } catch (err) {
      const value = err as { code?: string } | null;
      if (value?.code === "PreconditionFailed") {
        throw new PreconditionFailedError();
      }
      throw err;
    }
  }

  async getObject(key: string) {
    return await this.client.getObject(key);
  }

  async getJsonWithEtag(key: string) {
    return await this.client.getJsonWithEtag(key);
  }

  async deleteObject(key: string) {
    return await this.client.deleteObject(key);
  }

  async deleteObjects(keys: string[]) {
    return await this.client.deleteObjects(keys);
  }

  async listPrefixPage(prefix: string, continuationToken?: string, maxKeys?: number) {
    return await this.client.listPrefixPage(prefix, continuationToken, maxKeys);
  }
}

async function streamToUtf8(stream: unknown): Promise<string> {
  if (typeof stream === "string") {
    return stream;
  }
  if (!stream) {
    return "";
  }

  const body = stream as {
    transformToString?: () => Promise<string>;
    [Symbol.asyncIterator]?: () => AsyncIterator<unknown>;
  };

  if (typeof body.transformToString === "function") {
    return await body.transformToString();
  }

  if (typeof body[Symbol.asyncIterator] === "function") {
    const chunks: Buffer[] = [];
    for await (const chunk of body as AsyncIterable<unknown>) {
      chunks.push(Buffer.from(chunk as Uint8Array));
    }
    return Buffer.concat(chunks).toString("utf8");
  }

  return String(stream);
}

async function sleep(ms: number, abortSignal?: AbortSignal): Promise<void> {
  await new Promise<void>((resolve) => {
    const timer = setTimeout(resolve, ms);
    if (!abortSignal) {
      return;
    }
    const onAbort = () => {
      clearTimeout(timer);
      resolve();
    };
    if (abortSignal.aborted) {
      onAbort();
      return;
    }
    abortSignal.addEventListener("abort", onAbort, { once: true });
  });
}

export class Service {
  readonly client: R2Client;
  readonly relay: R2Relay;
  readonly cfg: ServiceConfig;
  private readonly transport: R2RelayTransport;

  constructor(cfg: ServiceConfig) {
    this.cfg = cfg;
    this.client = new R2Client(cfg);
    this.relay = new R2Relay({ bucket: cfg.bucket });
    this.transport = new R2RelayTransport({
      store: new R2ObjectStoreAdapter(this.client),
      keyspace: this.relay,
      peerId: cfg.peerId,
      sleep: (ms) => sleep(ms),
    });
  }

  async getPresignedUrl(key: string, expiresIn: number): Promise<string> {
    return this.client.getPresignedUrl(key, expiresIn);
  }

  async getAttachmentObject(key: string) {
    return this.client.getObject(key);
  }

  async publishIdentity(identity?: Partial<IdentityDoc>) {
    return await this.transport.publishIdentity({
      role: "server",
      software: { id: "openclaw", name: "OpenClaw", version: RELAY_PLUGIN_VERSION },
      protocol: { name: "r2-relay", version: 3 },
      capabilities: {
        messaging: { text: true, streaming: true, reactions: true, system_events: false },
        conversations: { list: true, create: false, reset: false, archive: false, threading: false },
        agents: { list: true, multiple: true, switch: true, per_agent_models: false },
        attachments: null,
        approvals: {
          exec: true,
          tool: true,
          custom: false,
        },
        extensions: null,
      },
      agents: [],
      conversations: [],
      limits: null,
      ...(identity ?? {}),
      peer: identity?.peer ?? this.cfg.peerId,
      last_seen: identity?.last_seen ?? Date.now(),
    });
  }

  async publishIdentify(identity?: Partial<IdentityDoc>) {
    return await this.publishIdentity(identity);
  }

  async getIdentity(peer: string): Promise<IdentityDoc | null> {
    const key = this.relay.makeIdentityKey(peer);
    try {
      const res = await this.client.getObject(key);
      if (!res || typeof res !== "object" || !("Body" in res) || !res.Body) {
        return null;
      }
      const body = await streamToUtf8((res as { Body: unknown }).Body);
      return JSON.parse(body) as IdentityDoc;
    } catch {
      return null;
    }
  }

  async sendMessage(to: string, options: SendMessageOptions): Promise<SendMessageResult> {
    return await this.transport.sendMessage(to, options);
  }

  async sendStreamingSnapshots(
    to: string,
    snapshots: string[],
    options: Omit<SendMessageOptions, "delivery">,
  ) {
    return await this.transport.sendStreamingSnapshots(to, snapshots, options);
  }

  async getHead(peer: string): Promise<HeadDoc | null> {
    return await this.transport.getHead(peer);
  }

  async getHeadState(peer: string): Promise<{ doc: HeadDoc; etag: string | null } | null> {
    return await this.transport.getHeadState(peer);
  }

  async readMessage(key: string): Promise<RelayMessage | null> {
    return await this.transport.readMessage(key);
  }

  async markMessageProcessed(
    key: string,
    patch: {
      processedAt?: number;
      processedBy?: string | null;
      state?: "pending" | "processing" | "done" | "error";
      error?: string | null;
    },
  ): Promise<RelayMessage | null> {
    return await this.transport.markMessageProcessed(key, patch);
  }

  async collectInboxMessages(selfId: string, lastSeenKey: string | null): Promise<InboxBatch> {
    return await this.transport.collectInboxMessages(selfId, lastSeenKey);
  }

  async sweepByKeyTimestamp(prefix: string, ttlDays: number, abortSignal?: AbortSignal): Promise<SweepRuleSummary> {
    return await this.transport.sweepByKeyTimestamp(prefix, ttlDays, abortSignal);
  }

  async sweepRetention(ttl: RelayRetentionConfig, abortSignal?: AbortSignal): Promise<SweepRuleSummary[]> {
    return await this.transport.sweepRetention(ttl, abortSignal);
  }

  async pollInbox(
    selfId: string,
    handler: (msg: RelayMessage, key: string) => Promise<void>,
    pollIntervalMs = 5000,
    backoffMax = 40000,
    deleteAfterProcessing = true,
    abortSignal?: AbortSignal,
  ) {
    return await this.transport.pollInbox(
      selfId,
      handler,
      pollIntervalMs,
      backoffMax,
      deleteAfterProcessing,
      abortSignal,
    );
  }
}
