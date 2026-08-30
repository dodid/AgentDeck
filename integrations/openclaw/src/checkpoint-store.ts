import path from "node:path";
import { DEFAULT_ACCOUNT_ID } from "openclaw/plugin-sdk/account-id";
import {
  defaultCheckpointState,
  hasSeenMessage,
  loadCheckpointStateFromFile,
  rememberMessage,
  saveCheckpointStateToFile,
  type RelayCheckpointState,
} from "./relay-core/index.js";
import { getRelayRuntime } from "./runtime.js";
import { PLUGIN_ID } from "./config.js";

function stateFilePath(accountId = DEFAULT_ACCOUNT_ID): string {
  const baseDir = getRelayRuntime().state.resolveStateDir();
  return path.join(baseDir, "plugins", PLUGIN_ID, `${accountId}.json`);
}

export async function loadCheckpointState(accountId = DEFAULT_ACCOUNT_ID): Promise<RelayCheckpointState> {
  return await loadCheckpointStateFromFile(stateFilePath(accountId));
}

export async function saveCheckpointState(
  state: RelayCheckpointState,
  accountId = DEFAULT_ACCOUNT_ID,
): Promise<void> {
  await saveCheckpointStateToFile(stateFilePath(accountId), state);
}

export {
  defaultCheckpointState,
  hasSeenMessage,
  rememberMessage,
  type RelayCheckpointState,
};
