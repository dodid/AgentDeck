import { randomBytes } from "node:crypto";

export const MAX_MS = 9999999999999;
const SAFE_FRAGMENT_RE = /[^a-zA-Z0-9._-]/g;

export function sanitizeFragment(value: string | null | undefined): string {
  return String(value ?? "").replace(SAFE_FRAGMENT_RE, "");
}

export function padRevTs(ts: number): string {
  return String(MAX_MS - Math.trunc(ts)).padStart(13, "0");
}

export function extractTimestampFromRelayKey(key: string): number | null {
  const name = key.split("/").pop()?.trim() ?? "";
  const match = name.match(/^(\d{13})-/);
  if (!match) {
    return null;
  }
  const reversed = Number(match[1]);
  if (!Number.isFinite(reversed)) {
    return null;
  }
  return MAX_MS - reversed;
}

export interface RelayKeyspaceOptions {
  bucket?: string;
  idFactory?: () => string;
  nowMsFactory?: () => number;
}

export class RelayKeyspace {
  readonly bucket: string;
  readonly idFactory: () => string;
  readonly nowMsFactory: () => number;

  constructor(options: RelayKeyspaceOptions = {}) {
    this.bucket = options.bucket ?? "";
    this.idFactory = options.idFactory ?? (() => randomBytes(4).toString("hex"));
    this.nowMsFactory = options.nowMsFactory ?? (() => Date.now());
  }

  padRevTs(ts: number): string {
    return padRevTs(ts);
  }

  shortUuid(): string {
    return this.idFactory();
  }

  makeMsgKey(recipient: string, nowMs?: number, suffix?: string): string {
    const ts = nowMs ?? this.nowMsFactory();
    return `msg/${recipient}/${this.padRevTs(ts)}-${suffix ?? this.shortUuid()}.json`;
  }

  makeAttKey(recipient: string, messageId: string, index: number, name?: string, nowMs?: number): string {
    const ts = nowMs ?? this.nowMsFactory();
    const safeMessageId = sanitizeFragment(messageId);
    const safeIndex = String(index).padStart(2, "0");
    const safeName = sanitizeFragment(name);
    const suffix = safeName ? `-${safeName}` : "";
    return `att/${recipient}/${this.padRevTs(ts)}-${safeMessageId}-${safeIndex}${suffix}`;
  }

  makeHeadKey(recipient: string): string {
    return `head/${recipient}.json`;
  }

  makeIdentityKey(peer: string): string {
    return `identity/${peer}.json`;
  }

  makeIdentifyKey(peer: string): string {
    return this.makeIdentityKey(peer);
  }
}

export class R2Relay extends RelayKeyspace {}
