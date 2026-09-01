import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import {
  DEFAULT_POLL_INTERVAL_MS,
  MAX_POLL_INTERVAL_MS,
  MIN_POLL_INTERVAL_MS,
  normalizePollIntervalMs,
  resolveR2RelayAccount,
} from "./config.js";

test("poll interval defaults to 3 seconds and clamps to the supported range", () => {
  assert.equal(DEFAULT_POLL_INTERVAL_MS, 3_000);
  assert.equal(normalizePollIntervalMs(undefined), 3_000);
  assert.equal(normalizePollIntervalMs(1_000), MIN_POLL_INTERVAL_MS);
  assert.equal(normalizePollIntervalMs(90_000), MAX_POLL_INTERVAL_MS);
});

test("invalid optional poll interval does not invalidate relay credentials", (t) => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "r2-relay-config-"));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  const configFile = path.join(directory, "r2relay.config.json");
  fs.writeFileSync(configFile, JSON.stringify({
    endpoint: "https://example.r2.cloudflarestorage.com",
    bucket: "relay-bucket",
    accessKeyId: "access-key",
    secretAccessKey: "secret-key",
    serverId: "relay-server",
    pollIntervalMs: "invalid",
  }));

  const account = resolveR2RelayAccount({
    cfg: {
      channels: {
        "r2-relay-channel": { enabled: true, configFile },
      },
    } as never,
  });

  assert.equal(account.configured, true);
  assert.equal(account.pollIntervalMs, DEFAULT_POLL_INTERVAL_MS);
});
