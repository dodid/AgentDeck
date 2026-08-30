import assert from "node:assert/strict";
import { readFile, readdir } from "node:fs/promises";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import test from "node:test";
import { Ajv2020 } from "ajv/dist/2020.js";

const here = dirname(fileURLToPath(import.meta.url));
const specDir = resolve(here, "../../../spec");
const schema = JSON.parse(await readFile(join(specDir, "relay-contract-v3.schema.json"), "utf8"));
const validate = new Ajv2020({ allErrors: true }).compile(schema);

test("all canonical v3 fixtures conform to the executable schema", async () => {
  const fixtureDir = join(specDir, "fixtures");
  const fixtureNames = (await readdir(fixtureDir)).filter((name) => name.endsWith(".json"));

  for (const name of fixtureNames) {
    const fixture = JSON.parse(await readFile(join(fixtureDir, name), "utf8"));
    const documents = name === "inbox-chain.json"
      ? [fixture.head, ...fixture.messages.map((entry: { message: unknown }) => entry.message)]
      : [fixture];
    for (const document of documents) {
      assert.equal(validate(document), true, `${name}: ${JSON.stringify(validate.errors)}`);
    }
  }
});

test("schema rejects v2 message fields", () => {
  const legacy = {
    msg_id: "m1",
    from: "client",
    to: "server",
    ts_sent: 1,
    prev_key: null,
    route: { agent_id: "main" },
    type: "text",
    body: "legacy",
  };
  assert.equal(validate(legacy), false);
});

test("schema rejects identities for another protocol version", () => {
  const identity = {
    peer: "server",
    role: "server",
    display_name: "Server",
    last_seen: 1,
    protocol: { name: "r2-relay", version: 2 },
    software: { id: "test" },
    capabilities: {
      messaging: { text: true, streaming: false, reactions: false, system_events: false },
      conversations: { list: false, create: false, reset: false, archive: false, threading: false },
      agents: { list: false, multiple: false, switch: false, per_agent_models: false },
    },
    agents: [],
    conversations: [],
  };
  assert.equal(validate(identity), false);
});
