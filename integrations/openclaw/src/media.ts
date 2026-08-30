import fs from "node:fs";
import {
  MAX_AUDIO_BYTES,
  MAX_DOCUMENT_BYTES,
  MAX_IMAGE_BYTES,
  MAX_VIDEO_BYTES,
  kindFromMime,
  type OutboundMediaAccess,
} from "openclaw/plugin-sdk/media-runtime";
import { loadOutboundMediaFromUrl } from "openclaw/plugin-sdk/outbound-media";
import type { ResolvedR2RelayAccount } from "./config.js";
import type { AttachmentRef } from "./protocol.js";
import type { Service } from "./service.js";
import { emitRelayDebug, type RelayPollLog } from "./lifecycle.js";

export function resolveRelayPayloadMediaUrls(payload: {
  mediaUrl?: string | null;
  mediaUrls?: string[] | null;
}): string[] {
  const urls = [
    ...(payload.mediaUrls ?? []),
    ...(payload.mediaUrl ? [payload.mediaUrl] : []),
  ];
  const seen = new Set<string>();
  return urls
    .map((url) => url?.trim())
    .filter((url): url is string => Boolean(url))
    .filter((url) => {
      if (seen.has(url)) {
        return false;
      }
      seen.add(url);
      return true;
    });
}

export async function buildRelayAttachments(params: {
  account: ResolvedR2RelayAccount;
  service: Service;
  targetPeer: string;
  mediaUrls: string[];
  workspaceDir?: string | null;
  mediaAccess?: OutboundMediaAccess;
  mediaLocalRoots?: readonly string[];
  mediaReadFile?: (filePath: string) => Promise<Buffer>;
  log?: RelayPollLog;
  source?: string;
}): Promise<{ attachments: AttachmentRef[]; failures: string[] }> {
  const attachments: AttachmentRef[] = [];
  const failures: string[] = [];
  if (params.mediaUrls.length === 0) {
    return { attachments, failures };
  }

  const relay = params.service.relay;
  const messageId = relay.shortUuid();
  const nowMs = Date.now();
  const maxBytes = Math.max(MAX_IMAGE_BYTES, MAX_VIDEO_BYTES, MAX_AUDIO_BYTES, MAX_DOCUMENT_BYTES);
  for (let i = 0; i < params.mediaUrls.length; i++) {
    const rawUrl = params.mediaUrls[i];
    const attKey = relay.makeAttKey(params.targetPeer, messageId, i + 1, undefined, nowMs);
    try {
      const resolvedUrl = isLocalMediaPath(rawUrl)
        ? resolveExistingLocalMediaReference(rawUrl, params.workspaceDir?.trim() || process.cwd())
        : rawUrl.trim();
      if (isLocalMediaPath(rawUrl)) {
        emitRelayDebug(params.log, `[${params.account.accountId}] resolving local outbound relay media`, {
          source: params.source ?? "unknown",
          rawUrl,
          resolvedPath: resolvedUrl instanceof URL ? resolvedUrl.toString() : resolvedUrl,
          workspaceDir: params.workspaceDir?.trim() || process.cwd(),
          cwd: process.cwd(),
        });
      } else {
        emitRelayDebug(params.log, `[${params.account.accountId}] fetching remote outbound relay media`, {
          source: params.source ?? "unknown",
          mediaUrl: rawUrl,
        });
      }
      const media = await loadOutboundMediaFromUrl(
        resolvedUrl instanceof URL ? resolvedUrl.toString() : resolvedUrl,
        {
          maxBytes,
          mediaAccess: params.mediaAccess,
          mediaLocalRoots: params.mediaLocalRoots,
          mediaReadFile: params.mediaReadFile,
        },
      );
      const buffer = media.buffer;
      const fileName = media.fileName ?? null;
      const contentType = normalizeAttachmentContentType(
        media.contentType,
        inferContentTypeFromFileName(fileName),
        fileName,
      );

      const dimensions = inferImageDimensions(buffer, contentType);
      emitRelayDebug(params.log, `[${params.account.accountId}] uploading outbound relay attachment`, {
        source: params.source ?? "unknown",
        attKey,
        fileName,
        contentType,
        size: buffer.length,
        width: dimensions?.width ?? null,
        height: dimensions?.height ?? null,
      });
      await params.service.client.putObject(attKey, buffer, contentType, undefined, undefined, "*");
      attachments.push({
        id: `att-${messageId}-${i + 1}`,
        key: attKey,
        file_name: fileName,
        content_type: contentType,
        size: buffer.length,
        sha256: null,
        kind: inferKindFromMediaType(contentType),
        width: dimensions?.width ?? null,
        height: dimensions?.height ?? null,
        duration_ms: null,
        preview_image_key: null,
        preview_image_type: null,
        preview_size: null,
      });
      emitRelayDebug(params.log, `[${params.account.accountId}] outbound relay attachment uploaded`, {
        source: params.source ?? "unknown",
        attKey,
        fileName,
      });
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      failures.push(`${rawUrl}: ${message}`);
      params.log?.error?.(`[${params.account.accountId}] failed preparing outbound relay attachment`, {
        source: params.source ?? "unknown",
        mediaUrl: rawUrl,
        error: message,
      });
    }
  }

  return { attachments, failures };
}

export function resolveExistingLocalMediaReference(value: string, workspaceDir: string): string | URL {
  const trimmed = value.trim();
  if (trimmed.toLowerCase().startsWith("file://")) {
    const url = new URL(trimmed);
    return new URL(`file://${resolveExistingFilePrefix(url.pathname)}`);
  }

  const absolute = isAbsolutePath(trimmed)
    ? trimmed
    : resolvePath(workspaceDir, trimmed);
  return resolveExistingFilePrefix(absolute);
}

function resolveExistingFilePrefix(value: string): string {
  const original = value.trim();
  let candidate = original;
  while (candidate.length > 1) {
    try {
      const stat = fs.statSync(candidate);
      if (stat.isFile()) {
        return candidate;
      }
    } catch {
      // keep trimming at whitespace boundaries only
    }

    const next = candidate.replace(/\s+\S+\s*$/, "").trimEnd();
    if (!next || next === candidate) {
      break;
    }
    candidate = next;
  }
  return original;
}

export function describeLocalMediaReference(value: string): string {
  const trimmed = value.trim();
  return pathBasename(trimmed) || trimmed;
}

function inferImageDimensions(buffer: Buffer, contentType?: string | null): { width: number; height: number } | null {
  const lower = contentType?.toLowerCase() ?? "";
  try {
    if (lower === "image/png" && buffer.length >= 24 && buffer.readUInt32BE(0) === 0x89504e47) {
      return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) };
    }
    if ((lower === "image/jpeg" || lower === "image/jpg") && buffer.length >= 4 && buffer[0] === 0xff && buffer[1] === 0xd8) {
      let offset = 2;
      while (offset + 9 < buffer.length) {
        if (buffer[offset] !== 0xff) {
          offset += 1;
          continue;
        }
        const marker = buffer[offset + 1];
        const length = buffer.readUInt16BE(offset + 2);
        if (length < 2) {
          break;
        }
        const isStartOfFrame = (marker >= 0xc0 && marker <= 0xc3) || (marker >= 0xc5 && marker <= 0xc7) || (marker >= 0xc9 && marker <= 0xcb) || (marker >= 0xcd && marker <= 0xcf);
        if (isStartOfFrame && offset + 8 < buffer.length) {
          return { width: buffer.readUInt16BE(offset + 7), height: buffer.readUInt16BE(offset + 5) };
        }
        offset += 2 + length;
      }
      return null;
    }
    if (lower === "image/gif" && buffer.length >= 10 && buffer.toString("ascii", 0, 3) === "GIF") {
      return { width: buffer.readUInt16LE(6), height: buffer.readUInt16LE(8) };
    }
    if (lower === "image/webp" && buffer.length >= 30 && buffer.toString("ascii", 0, 4) === "RIFF" && buffer.toString("ascii", 8, 12) === "WEBP") {
      const chunk = buffer.toString("ascii", 12, 16);
      if (chunk === "VP8X" && buffer.length >= 30) {
        return {
          width: 1 + buffer.readUIntLE(24, 3),
          height: 1 + buffer.readUIntLE(27, 3),
        };
      }
      if (chunk === "VP8 " && buffer.length >= 30) {
        return {
          width: buffer.readUInt16LE(26) & 0x3fff,
          height: buffer.readUInt16LE(28) & 0x3fff,
        };
      }
      if (chunk === "VP8L" && buffer.length >= 25) {
        const bits = buffer.readUInt32LE(21);
        return {
          width: (bits & 0x3fff) + 1,
          height: ((bits >> 14) & 0x3fff) + 1,
        };
      }
    }
  } catch {
    return null;
  }
  return null;
}

function inferKindFromMediaType(type?: string | null): AttachmentRef["kind"] {
  const kind = kindFromMime(type);
  switch (kind) {
    case "image":
      return "image";
    case "video":
      return "video";
    case "audio":
      return "audio";
    default:
      return "file";
  }
}

function isLocalMediaPath(value: string): boolean {
  const lower = value.toLowerCase();
  if (lower.startsWith("http://") || lower.startsWith("https://") || lower.startsWith("data:")) {
    return false;
  }
  if (lower.startsWith("media:")) {
    return false;
  }
  if (lower.startsWith("file://")) {
    return true;
  }
  return isAbsolutePath(value) || value.startsWith("./") || value.startsWith("../");
}

function inferContentTypeFromFileName(fileName?: string | null): string {
  const ext = pathExtname(fileName ?? "").toLowerCase();
  switch (ext) {
    case ".jpg":
    case ".jpeg":
      return "image/jpeg";
    case ".png":
      return "image/png";
    case ".gif":
      return "image/gif";
    case ".webp":
      return "image/webp";
    case ".heic":
      return "image/heic";
    case ".heif":
      return "image/heif";
    case ".mp4":
      return "video/mp4";
    case ".mov":
      return "video/quicktime";
    case ".webm":
      return "video/webm";
    case ".mp3":
      return "audio/mpeg";
    case ".m4a":
      return "audio/mp4";
    case ".wav":
      return "audio/wav";
    case ".ogg":
      return "audio/ogg";
    case ".pdf":
      return "application/pdf";
    case ".txt":
      return "text/plain";
    case ".json":
      return "application/json";
    case ".zip":
      return "application/zip";
    default:
      return "application/octet-stream";
  }
}

export function normalizeAttachmentContentType(
  primary?: string | null,
  fallback?: string | null,
  fileName?: string | null,
): string {
  const primaryTrimmed = primary?.trim();
  if (primaryTrimmed) return primaryTrimmed;
  const fallbackTrimmed = fallback?.trim();
  if (fallbackTrimmed) return fallbackTrimmed;
  return inferContentTypeFromFileName(fileName);
}

export function resolveInboundAttachmentBestEffortMaxBytes(
  attachment: AttachmentRef,
  defaultMaxBytes: number,
): number {
  if (typeof attachment.size === "number" && Number.isFinite(attachment.size) && attachment.size > 0) {
    return Math.max(defaultMaxBytes, Math.min(attachment.size + 1024 * 1024, 64 * 1024 * 1024));
  }
  return Math.max(defaultMaxBytes, 64 * 1024 * 1024);
}

function isImageAttachment(attachment: AttachmentRef): boolean {
  if (attachment.kind === "image") {
    return true;
  }
  return Boolean(attachment.content_type?.toLowerCase().startsWith("image/"));
}

function isVideoAttachment(attachment: AttachmentRef): boolean {
  if (attachment.kind === "video") {
    return true;
  }
  return Boolean(attachment.content_type?.toLowerCase().startsWith("video/"));
}

function isAudioAttachment(attachment: AttachmentRef): boolean {
  if (attachment.kind === "audio") {
    return true;
  }
  return Boolean(attachment.content_type?.toLowerCase().startsWith("audio/"));
}

export function resolveInboundAttachmentMaxBytes(attachment: AttachmentRef): number {
  if (isImageAttachment(attachment)) return MAX_IMAGE_BYTES;
  if (isVideoAttachment(attachment)) return MAX_VIDEO_BYTES;
  if (isAudioAttachment(attachment)) return MAX_AUDIO_BYTES;
  return MAX_DOCUMENT_BYTES;
}

export function formatAttachmentContext(attachments?: AttachmentRef[]): string | null {
  if (!attachments || attachments.length === 0) return null;
  const lines = attachments.map((att, i) => {
    const parts: string[] = [`[Attachment ${i + 1}]`];
    if (att.file_name) parts.push(`name: ${att.file_name}`);
    if (att.content_type) parts.push(`type: ${att.content_type}`);
    if (att.kind && att.kind !== "unknown") parts.push(`kind: ${att.kind}`);
    if (att.size) parts.push(`size: ${att.size} bytes`);
    if (att.width && att.height) parts.push(`dimensions: ${att.width}x${att.height}`);
    if (att.duration_ms) parts.push(`duration: ${(att.duration_ms / 1000).toFixed(1)}s`);
    return parts.join(", ");
  });
  return lines.join("\n");
}

function pathBasename(value: string): string {
  return value.split(/[\\/]/).pop() ?? value;
}

function pathExtname(value: string): string {
  const base = pathBasename(value);
  const index = base.lastIndexOf(".");
  return index >= 0 ? base.slice(index) : "";
}

function isAbsolutePath(value: string): boolean {
  return value.startsWith("/") || /^[A-Za-z]:[\\/]/.test(value);
}

function resolvePath(base: string, relative: string): string {
  const normalizedBase = base.replace(/[\\/]+$/, "");
  const parts = `${normalizedBase}/${relative}`.split(/[\\/]+/);
  const resolved: string[] = [];
  for (const part of parts) {
    if (!part || part === ".") {
      continue;
    }
    if (part === "..") {
      resolved.pop();
      continue;
    }
    resolved.push(part);
  }
  return `${normalizedBase.startsWith("/") ? "/" : ""}${resolved.join("/")}`;
}
