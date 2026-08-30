import { createHash } from "node:crypto";
import * as fs from "node:fs/promises";
import * as path from "node:path";

import type { RelayCheckpointState } from "./types.js";

const RECENT_MESSAGE_IDS_LIMIT = 200;

export const DEFAULT_CHECKPOINT_STATE: RelayCheckpointState = {
  lastHeadKey: null,
  recentMessageIds: [],
  recentObjectKeys: [],
  lastPollAt: null,
  lastInboundAt: null,
};

export function defaultCheckpointState(): RelayCheckpointState {
  return {
    lastHeadKey: DEFAULT_CHECKPOINT_STATE.lastHeadKey,
    recentMessageIds: [...DEFAULT_CHECKPOINT_STATE.recentMessageIds],
    recentObjectKeys: [...DEFAULT_CHECKPOINT_STATE.recentObjectKeys],
    lastPollAt: DEFAULT_CHECKPOINT_STATE.lastPollAt,
    lastInboundAt: DEFAULT_CHECKPOINT_STATE.lastInboundAt,
  };
}

export function normalizeCheckpointState(data?: Partial<RelayCheckpointState> | null): RelayCheckpointState {
  const raw = data ?? {};
  return {
    lastHeadKey: typeof raw.lastHeadKey === "string" ? raw.lastHeadKey : null,
    recentMessageIds: Array.isArray(raw.recentMessageIds)
      ? raw.recentMessageIds.filter((value): value is string => typeof value === "string").slice(0, RECENT_MESSAGE_IDS_LIMIT)
      : [],
    recentObjectKeys: Array.isArray(raw.recentObjectKeys)
      ? raw.recentObjectKeys.filter((value): value is string => typeof value === "string").slice(0, RECENT_MESSAGE_IDS_LIMIT)
      : [],
    lastPollAt: typeof raw.lastPollAt === "number" ? raw.lastPollAt : null,
    lastInboundAt: typeof raw.lastInboundAt === "number" ? raw.lastInboundAt : null,
  };
}

export interface CheckpointStore {
  load(): Promise<RelayCheckpointState> | RelayCheckpointState;
  save(state: RelayCheckpointState): Promise<void> | void;
}

export class InMemoryCheckpointStore implements CheckpointStore {
  private state: RelayCheckpointState;

  constructor(state?: Partial<RelayCheckpointState>) {
    this.state = normalizeCheckpointState(state);
  }

  load(): RelayCheckpointState {
    return normalizeCheckpointState(this.state);
  }

  save(state: RelayCheckpointState): void {
    this.state = normalizeCheckpointState(state);
  }
}

export class FileCheckpointStore implements CheckpointStore {
  readonly filePath: string;

  constructor(filePath: string) {
    this.filePath = filePath;
  }

  async load(): Promise<RelayCheckpointState> {
    return loadCheckpointStateFromFile(this.filePath);
  }

  async save(state: RelayCheckpointState): Promise<void> {
    await saveCheckpointStateToFile(this.filePath, state);
  }
}

export async function loadCheckpointStateFromFile(filePath: string): Promise<RelayCheckpointState> {
  try {
    const raw = await fs.readFile(filePath, "utf8");
    return normalizeCheckpointState(JSON.parse(raw) as Partial<RelayCheckpointState>);
  } catch {
    return defaultCheckpointState();
  }
}

export async function saveCheckpointStateToFile(filePath: string, state: RelayCheckpointState): Promise<void> {
  await fs.mkdir(path.dirname(filePath), { recursive: true });
  const normalized = normalizeCheckpointState(state);
  const serialized = JSON.stringify(normalized, null, 2);
  const tempPath = `${filePath}.${createHash("sha1").update(serialized).digest("hex")}.tmp`;
  await fs.writeFile(tempPath, serialized, "utf8");
  await fs.rename(tempPath, filePath);
}

export function rememberMessage(
  state: RelayCheckpointState,
  params: { msgId?: string | null; objectKey?: string | null; at?: number | null },
): RelayCheckpointState {
  const normalized = normalizeCheckpointState(state);
  const recentMessageIds = params.msgId
    ? [params.msgId, ...normalized.recentMessageIds.filter((value) => value !== params.msgId)].slice(0, RECENT_MESSAGE_IDS_LIMIT)
    : normalized.recentMessageIds;
  const recentObjectKeys = params.objectKey
    ? [params.objectKey, ...normalized.recentObjectKeys.filter((value) => value !== params.objectKey)].slice(0, RECENT_MESSAGE_IDS_LIMIT)
    : normalized.recentObjectKeys;
  return {
    ...normalized,
    recentMessageIds,
    recentObjectKeys,
    lastInboundAt: params.at ?? normalized.lastInboundAt ?? Date.now(),
  };
}

export function hasSeenMessage(
  state: RelayCheckpointState,
  params: { msgId?: string | null; objectKey?: string | null },
): boolean {
  const normalized = normalizeCheckpointState(state);
  return Boolean(
    (params.msgId && normalized.recentMessageIds.includes(params.msgId)) ||
      (params.objectKey && normalized.recentObjectKeys.includes(params.objectKey)),
  );
}
