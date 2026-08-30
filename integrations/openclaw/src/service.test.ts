import test from "node:test";
import assert from "node:assert/strict";

import { Service } from "./service.js";

test("service sweepRetention delegates retention ownership to shared transport core", async () => {
  const service = new Service({
    endpoint: "https://example.r2.cloudflarestorage.com",
    bucket: "relay-bucket",
    peerId: "relay.openclaw.dev",
  });

  const expected = [
    { prefix: "msg/", scanned: 2, deleted: 1 },
    { prefix: "identity/", scanned: 1, deleted: 1 },
  ];
  const calls: Array<Record<string, unknown>> = [];

  Object.defineProperty(service, "transport", {
    value: {
      sweepRetention: async (ttl: Record<string, unknown>, abortSignal?: AbortSignal) => {
        calls.push({ ttl, aborted: abortSignal?.aborted ?? false });
        return expected;
      },
    },
  });

  const ttl = { msg: 7, identity: 1 };
  const summaries = await service.sweepRetention(ttl);

  assert.deepEqual(summaries, expected);
  assert.deepEqual(calls, [{ ttl, aborted: false }]);
});
