import { createHash, randomBytes } from "node:crypto";
import {
  CreateBucketCommand,
  DeleteObjectsCommand,
  GetObjectCommand,
  HeadBucketCommand,
  ListObjectsV2Command,
  PutObjectCommand,
  S3Client,
} from "@aws-sdk/client-s3";

const MAX_MS = 9999999999999;

function sanitizeFragment(value) {
  return String(value ?? "").replace(/[^a-zA-Z0-9._-]/g, "");
}

function padRevTs(ts) {
  return String(MAX_MS - Math.trunc(ts)).padStart(13, "0");
}

function shortId() {
  return randomBytes(5).toString("hex");
}

async function bodyToString(body) {
  if (!body) return "";
  if (typeof body.transformToString === "function") {
    return await body.transformToString();
  }
  const chunks = [];
  for await (const chunk of body) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString("utf8");
}

async function bodyToBuffer(body) {
  if (!body) return Buffer.alloc(0);
  if (typeof body.transformToByteArray === "function") {
    return Buffer.from(await body.transformToByteArray());
  }
  const chunks = [];
  for await (const chunk of body) {
    chunks.push(Buffer.from(chunk));
  }
  return Buffer.concat(chunks);
}

export class RelayTestClient {
  constructor({ endpoint, bucket, accessKeyId, secretAccessKey, region = "us-east-1" }) {
    this.bucket = bucket;
    this.s3 = new S3Client({
      endpoint,
      region,
      forcePathStyle: true,
      credentials: {
        accessKeyId,
        secretAccessKey,
      },
    });
  }

  makeIdentityKey(peer) {
    return `identity/${peer}.json`;
  }

  makeHeadKey(peer) {
    return `head/${peer}.json`;
  }

  makeMsgKey(recipient, ts = Date.now(), suffix = shortId()) {
    return `msg/${recipient}/${padRevTs(ts)}-${sanitizeFragment(suffix)}.json`;
  }

  makeAttKey(recipient, messageId, index, name, ts = Date.now()) {
    const safeName = sanitizeFragment(name);
    return `att/${recipient}/${padRevTs(ts)}-${sanitizeFragment(messageId)}-${String(index).padStart(2, "0")}${safeName ? `-${safeName}` : ""}`;
  }

  async ensureBucket() {
    try {
      await this.s3.send(new HeadBucketCommand({ Bucket: this.bucket }));
    } catch {
      await this.s3.send(new CreateBucketCommand({ Bucket: this.bucket }));
    }
  }

  async putJson(key, value) {
    await this.s3.send(new PutObjectCommand({
      Bucket: this.bucket,
      Key: key,
      Body: `${JSON.stringify(value, null, 2)}\n`,
      ContentType: "application/json",
    }));
  }

  async putObject(key, body, contentType = "application/octet-stream") {
    await this.s3.send(new PutObjectCommand({
      Bucket: this.bucket,
      Key: key,
      Body: body,
      ContentType: contentType,
    }));
  }

  async getJson(key) {
    const res = await this.s3.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
    return JSON.parse(await bodyToString(res.Body));
  }

  async getObjectBuffer(key) {
    const res = await this.s3.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
    return await bodyToBuffer(res.Body);
  }

  async tryGetJson(key) {
    try {
      return await this.getJson(key);
    } catch {
      return null;
    }
  }

  async listKeys(prefix = "") {
    const keys = [];
    let ContinuationToken;
    do {
      const page = await this.s3.send(new ListObjectsV2Command({
        Bucket: this.bucket,
        Prefix: prefix,
        ContinuationToken,
      }));
      for (const item of page.Contents ?? []) {
        if (item.Key) keys.push(item.Key);
      }
      ContinuationToken = page.NextContinuationToken;
    } while (ContinuationToken);
    return keys.sort();
  }

  async deletePrefix(prefix) {
    const keys = await this.listKeys(prefix);
    for (let index = 0; index < keys.length; index += 1000) {
      const batch = keys.slice(index, index + 1000);
      if (batch.length === 0) continue;
      await this.s3.send(new DeleteObjectsCommand({
        Bucket: this.bucket,
        Delete: {
          Objects: batch.map((Key) => ({ Key })),
          Quiet: true,
        },
      }));
    }
  }

  async publishClientIdentity(peer) {
    const identity = {
      peer,
      display_name: "AgentDeck E2E",
      role: "client",
      last_seen: Date.now(),
      protocol: { name: "r2-relay", version: 3 },
      software: {
        id: "agentdeck-e2e",
        name: "AgentDeck E2E Test Client",
        version: "0.0.0-ci",
      },
      capabilities: {
        messaging: { text: true, streaming: true, reactions: true, system_events: false },
        conversations: { list: false, create: false, reset: false, archive: false, threading: false },
        agents: { list: false, multiple: false, switch: false, per_agent_models: false },
        attachments: {
          supported: true,
          kinds: ["image", "video", "audio", "file", "unknown"],
          max_bytes_by_kind: null,
          oversize_behavior: "reject",
        },
        approvals: null,
        extensions: null,
      },
      limits: null,
      agents: [],
      conversations: [],
    };
    await this.putJson(this.makeIdentityKey(peer), identity);
    return identity;
  }

  async appendMessage({ from, to, body, route, type = "text", attachments = [] }) {
    const previousHead = await this.tryGetJson(this.makeHeadKey(to));
    const now = Date.now();
    const messageId = `e2e-${shortId()}`;
    const key = this.makeMsgKey(to, now, messageId);
    const message = {
      msg_id: messageId,
      from,
      to,
      ts_sent: now,
      prev_key: previousHead?.head_key ?? null,
      route,
      content: type === "reaction"
        ? {
            type: "reaction",
            target_msg_id: "placeholder",
            emoji: body ?? "",
            remove: false,
          }
        : {
            type: "text",
            text: body ?? "",
            attachments: attachments.length > 0 ? attachments : undefined,
          },
      delivery: null,
      status: null,
      size: body ? Buffer.byteLength(body) : 0,
    };
    await this.putJson(key, message);
    await this.putJson(this.makeHeadKey(to), {
      head_key: key,
      head_msg_id: messageId,
      head_ts: now,
    });
    return { key, messageId, message };
  }

  async appendReaction({ from, to, targetMessageId, emoji, remove = false, route }) {
    const result = await this.appendMessage({
      from,
      to,
      body: remove ? "" : emoji,
      route,
      type: "reaction",
    });
    const message = {
      ...result.message,
      content: {
        type: "reaction",
        target_msg_id: targetMessageId,
        emoji,
        remove,
      },
    };
    await this.putJson(result.key, message);
    return { ...result, message };
  }

  async appendAttachmentMessage({
    from,
    to,
    body,
    route,
    fileName,
    contentType,
    data,
    kind,
    width = null,
    height = null,
    durationMs = null,
  }) {
    const messageId = `e2e-${shortId()}`;
    const key = this.makeAttKey(to, messageId, 0, fileName);
    const buffer = Buffer.isBuffer(data) ? data : Buffer.from(data);
    const sha256 = createHash("sha256").update(buffer).digest("hex");
    await this.putObject(key, buffer, contentType);
    return await this.appendMessage({
      from,
      to,
      body,
      route,
      attachments: [{
        id: `${messageId}-att-0`,
        key,
        file_name: fileName,
        content_type: contentType,
        size: buffer.length,
        sha256,
        kind: kind ?? inferAttachmentKind(contentType),
        width,
        height,
        duration_ms: durationMs,
        preview_image_key: null,
        preview_image_type: null,
        preview_size: null,
      }],
    });
  }

  async collectChain(peer, stopAtKey = null) {
    const head = await this.tryGetJson(this.makeHeadKey(peer));
    const messages = [];
    const seen = new Set();
    let current = head?.head_key ?? null;
    while (current && current !== stopAtKey && !seen.has(current)) {
      seen.add(current);
      const message = await this.tryGetJson(current);
      if (!message) break;
      messages.push({ key: current, message });
      current = message.prev_key ?? null;
    }
    messages.reverse();
    return { head, messages };
  }

  async dumpObjects() {
    const keys = await this.listKeys("");
    const objects = {};
    for (const key of keys) {
      if (!key.endsWith(".json")) {
        objects[key] = "<binary>";
        continue;
      }
      try {
        objects[key] = await this.getJson(key);
      } catch {
        objects[key] = "<unreadable-json>";
      }
    }
    return objects;
  }
}

function inferAttachmentKind(contentType) {
  const lower = String(contentType ?? "").toLowerCase();
  if (lower.startsWith("image/")) return "image";
  if (lower.startsWith("video/")) return "video";
  if (lower.startsWith("audio/")) return "audio";
  if (lower) return "file";
  return "unknown";
}

export async function waitFor(description, fn, { timeoutMs = 120_000, intervalMs = 1000 } = {}) {
  const started = Date.now();
  let lastError;
  while (Date.now() - started < timeoutMs) {
    try {
      const result = await fn();
      if (result) return result;
    } catch (err) {
      lastError = err;
    }
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  const suffix = lastError ? ` Last error: ${lastError instanceof Error ? lastError.message : String(lastError)}` : "";
  throw new Error(`Timed out waiting for ${description}.${suffix}`);
}
