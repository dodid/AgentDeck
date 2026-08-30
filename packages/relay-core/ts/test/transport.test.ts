import { readFileSync } from "node:fs";
import * as path from "node:path";
import { test } from "node:test";
import assert = require("node:assert/strict");

import { InMemoryCheckpointStore, defaultCheckpointState, hasSeenMessage, rememberMessage } from "../src/checkpoint.js";
import { PreconditionFailedError } from "../src/errors.js";
import { RelayKeyspace } from "../src/keyspace.js";
import { R2RelayTransport } from "../src/transport.js";
import { RelayMessage } from "../src/types.js";

const FIXTURES_DIR = path.resolve(process.cwd(), "..", "spec", "fixtures");

class SequentialIds {
  private values: string[];

  constructor(values: string[]) {
    this.values = [...values];
  }

  next = (): string => {
    const value = this.values.shift();
    if (!value) {
      throw new Error("No more ids");
    }
    return value;
  };
}

class SequentialTimes {
  private values: number[];

  constructor(values: number[]) {
    this.values = [...values];
  }

  next = (): number => {
    const value = this.values.shift();
    if (value === undefined) {
      throw new Error("No more timestamps");
    }
    return value;
  };
}

class ObjectStoreStub {
  putCalls: Array<Record<string, unknown>> = [];
  objects = new Map<string, Record<string, unknown>>();
  headReads: Array<Record<string, unknown> | null> = [];
  listPages: Array<Record<string, unknown>> = [];
  failNextHeadWrites = 0;
  deletedObjects: string[] = [];

  async putObject(
    key: string,
    body: Buffer | string,
    contentType?: string,
    tagging?: string,
    ifMatch?: string,
    ifNoneMatch?: string,
  ): Promise<{ ETag: string }> {
    this.putCalls.push({ key, body, contentType, tagging, ifMatch, ifNoneMatch });
    if (key.startsWith("head/") && this.failNextHeadWrites > 0) {
      this.failNextHeadWrites -= 1;
      throw new PreconditionFailedError("PreconditionFailed");
    }

    let payload: unknown = body;
    if (typeof body === "string" && contentType === "application/json") {
      payload = JSON.parse(body);
    }
    const etag = `etag-${this.putCalls.length}`;
    this.objects.set(key, { payload, etag, contentType });
    return { ETag: etag };
  }

  async getJsonWithEtag(key: string): Promise<{ body: unknown; etag: string | null } | null> {
    if (this.headReads.length > 0) {
      return this.headReads.shift() as { body: Record<string, unknown>; etag: string | null } | null;
    }
    const record = this.objects.get(key);
    if (!record) {
      return null;
    }
    return {
      body: record.payload as Record<string, unknown>,
      etag: (record.etag as string) ?? null,
    };
  }

  async getObject(key: string): Promise<Record<string, unknown> | null> {
    const record = this.objects.get(key);
    if (!record) {
      return null;
    }
    return { payload: record.payload };
  }

  async listPrefixPage(
    _prefix: string,
    _continuationToken?: string,
    _maxKeys = 1000,
  ): Promise<{ contents: Array<Record<string, unknown>>; nextContinuationToken: string | null; isTruncated: boolean }> {
    if (this.listPages.length > 0) {
      return this.listPages.shift() as {
        contents: Array<Record<string, unknown>>;
        nextContinuationToken: string | null;
        isTruncated: boolean;
      };
    }
    return { contents: [], nextContinuationToken: null, isTruncated: false };
  }

  async deleteObject(key: string): Promise<{ deleted: string }> {
    this.deletedObjects.push(key);
    this.objects.delete(key);
    return { deleted: key };
  }

  async deleteObjects(keys: string[]): Promise<{ deleted: string[]; errors: unknown[] }> {
    this.deletedObjects.push(...keys);
    for (const key of keys) {
      this.objects.delete(key);
    }
    return { deleted: keys, errors: [] };
  }
}

async function noSleep(_seconds: number): Promise<void> {
  return undefined;
}

function loadFixture<T>(name: string): T {
  return JSON.parse(readFileSync(path.join(FIXTURES_DIR, name), "utf8")) as T;
}

const openClawRoute = {
  agent_id: "main",
  conversation_id: "agent:main:main",
};

test("sendMessage retries after head CAS failure", async () => {
  const store = new ObjectStoreStub();
  store.failNextHeadWrites = 1;
  const concurrentHead = {
    head_key: "msg/phone-1/9999999999800-existing.json",
    head_msg_id: "existing-msg",
    head_ts: 199,
  };
  store.headReads = [null, { body: concurrentHead, etag: "etag-concurrent" }];
  const ids = new SequentialIds(["first-key", "first-msg", "second-key", "second-msg"]);
  const keyspace = new RelayKeyspace({
    idFactory: ids.next,
    nowMsFactory: () => 123,
  });
  const transport = new R2RelayTransport({ store, keyspace, peerId: "server-one", sleep: noSleep });

  const result = await transport.sendMessage("phone-1", {
    route: openClawRoute,
    content: { type: "text", text: "hello there" },
  });

  assert.deepEqual(result, {
    key: "msg/phone-1/9999999999876-second-key.json",
    messageId: "second-msg",
  });
  assert.deepEqual(
    store.putCalls.map((call) => call.key),
    [
      "msg/phone-1/9999999999876-first-key.json",
      "head/phone-1.json",
      "msg/phone-1/9999999999876-second-key.json",
      "head/phone-1.json",
    ],
  );
  const secondMessage = JSON.parse(store.putCalls[2].body as string) as Record<string, unknown>;
  assert.equal(secondMessage.prev_key, concurrentHead.head_key);
  assert.deepEqual(secondMessage.route, openClawRoute);
});

test("collectInboxMessages returns oldest-first order from fixture chain", async () => {
  const fixture = loadFixture<{ head: Record<string, unknown>; messages: Array<{ key: string; message: Record<string, unknown> }> }>("inbox-chain.json");
  const store = new ObjectStoreStub();
  store.headReads = [{ body: fixture.head, etag: "etag-1" }];
  for (const item of fixture.messages) {
    store.objects.set(item.key, { payload: item.message, etag: "etag-msg" });
  }

  const transport = new R2RelayTransport({ store, keyspace: new RelayKeyspace(), peerId: "relay.hermes.local" });
  const batch = await transport.collectInboxMessages("clawchat-ios-alice", null);

  assert.deepEqual(batch.head, fixture.head);
  assert.equal(batch.checkpointHeadKey, fixture.head.head_key as string);
  assert.deepEqual(
    batch.messages.map((item: { key: string }) => item.key),
    fixture.messages.map((item) => item.key),
  );
});

test("collectInboxMessages returns the oldest unread chunk when backlog exceeds 500", async () => {
  const store = new ObjectStoreStub();
  const messages: Array<{ key: string; message: RelayMessage }> = [];

  for (let index = 1; index <= 600; index += 1) {
    const key = `msg/clawchat-ios-alice/backlog-${String(index).padStart(4, "0")}.json`;
    const previous = messages[index - 2]?.key ?? null;
    messages.push({
      key,
      message: {
        msg_id: `msg-${index}`,
        from: "relay.hermes.local",
        to: "clawchat-ios-alice",
        ts_sent: index,
        prev_key: previous,
        route: { agent_id: "main", conversation_id: "sess-1" },
        content: { type: "text", text: `message ${index}` },
        delivery: null,
        status: null,
      },
    });
  }

  store.headReads = [{
    body: {
      head_key: messages[messages.length - 1]!.key,
      head_msg_id: messages[messages.length - 1]!.message.msg_id,
      head_ts: messages[messages.length - 1]!.message.ts_sent,
    },
    etag: "etag-1",
  }];

  for (const item of messages) {
    store.objects.set(item.key, { payload: item.message, etag: `etag-${item.message.msg_id}` });
  }

  const transport = new R2RelayTransport({ store, keyspace: new RelayKeyspace(), peerId: "relay.hermes.local" });
  const batch = await transport.collectInboxMessages("clawchat-ios-alice", null);

  assert.equal(batch.messages.length, 500);
  assert.equal(batch.messages[0]?.message.msg_id, "msg-1");
  assert.equal(batch.messages[499]?.message.msg_id, "msg-500");
  assert.equal(batch.checkpointHeadKey, messages[499]!.key);
});

test("sendStreamingSnapshots emits partial then final messages", async () => {
  const partial = loadFixture<Record<string, unknown>>("message-stream-partial.json");
  const final = loadFixture<Record<string, unknown>>("message-stream-final.json");
  const store = new ObjectStoreStub();
  const ids = new SequentialIds([
    (partial.delivery as { stream: { stream_id: string } }).stream.stream_id,
    "partial-key",
    partial.msg_id as string,
    "final-key",
    final.msg_id as string,
  ]);
  const times = new SequentialTimes([partial.ts_sent as number, final.ts_sent as number]);
  const keyspace = new RelayKeyspace({ idFactory: ids.next, nowMsFactory: times.next });
  const transport = new R2RelayTransport({ store, keyspace, peerId: partial.from as string });

  const result = await transport.sendStreamingSnapshots(partial.to as string, [
    (partial.content as { text: string }).text,
    (final.content as { text: string }).text,
  ], {
    route: partial.route as typeof openClawRoute,
  });

  assert.equal(result.streamId, (partial.delivery as { stream: { stream_id: string } }).stream.stream_id);
  assert.equal(result.results.length, 2);

  const partialWrite = JSON.parse(store.putCalls[0].body as string) as Record<string, unknown>;
  const finalWrite = JSON.parse(store.putCalls[2].body as string) as Record<string, unknown>;
  const pDel = (partial.delivery as { stream: Record<string, unknown> }).stream;
  const fDel = (final.delivery as { stream: Record<string, unknown> }).stream;
  assert.equal((partialWrite.content as { type: string }).type, (partial.content as { type: string }).type);
  assert.equal((partialWrite.content as { text: string }).text, (partial.content as { text: string }).text);
  assert.equal((partialWrite.delivery as { stream: { seq: number } }).stream.seq, pDel.seq);
  assert.equal((partialWrite.delivery as { stream: { state: string } }).stream.state, pDel.state);
  assert.equal((finalWrite.content as { text: string }).text, (final.content as { text: string }).text);
  assert.equal((finalWrite.delivery as { stream: { seq: number } }).stream.seq, fDel.seq);
  assert.equal((finalWrite.delivery as { stream: { state: string } }).stream.state, fDel.state);
});

test("markMessageProcessed patches processed fields", async () => {
  const expected = loadFixture<Record<string, unknown>>("message-text.json");
  const message = { ...expected, status: null };
  const key = "msg/relay.openclaw.dev/8235971204999-9f2c1a7b.json";
  const store = new ObjectStoreStub();
  store.objects.set(key, { payload: message, etag: "etag-1" });
  const transport = new R2RelayTransport({ store, keyspace: new RelayKeyspace(), peerId: "relay.openclaw.dev" });

  const expStatus = expected.status as { processed_at: number; processed_by: string; state: string };
  const updated = await transport.markMessageProcessed(key, {
    processedAt: expStatus.processed_at,
    processedBy: expStatus.processed_by,
  });

  assert.equal(updated?.status?.processed_at, expStatus.processed_at);
  assert.equal(updated?.status?.processed_by, expStatus.processed_by);
  assert.equal(updated?.status?.state, expStatus.state);
});

test("publishIdentity preserves discovery payload shape", async () => {
  const identity = loadFixture<Record<string, unknown>>("identity-openclaw.json");
  const store = new ObjectStoreStub();
  const transport = new R2RelayTransport({
    store,
    keyspace: new RelayKeyspace({ nowMsFactory: () => identity.last_seen as number }),
    peerId: identity.peer as string,
  });

  const published = await transport.publishIdentity(identity);

  assert.deepEqual(published, identity);
  assert.deepEqual(store.objects.get(`identity/${identity.peer}.json`)!.payload, identity);
});

test("checkpoint helpers remember recent messages and msg ids", () => {
  let state = defaultCheckpointState();
  state = rememberMessage(state, { objectKey: "msg/one", msgId: "id-1" });
  state = rememberMessage(state, { objectKey: "msg/two", msgId: "id-2" });

  assert.equal(hasSeenMessage(state, { objectKey: "msg/one" }), true);
  assert.equal(hasSeenMessage(state, { msgId: "id-2" }), true);
  assert.deepEqual(state.recentObjectKeys, ["msg/two", "msg/one"]);
  assert.deepEqual(state.recentMessageIds, ["id-2", "id-1"]);
});

test("pollInbox does not checkpoint failed message", async () => {
  const fixture = loadFixture<{ messages: Array<{ key: string; message: Record<string, unknown> }> }>("inbox-chain.json");
  const firstItem = fixture.messages[0];
  const head = {
    head_key: firstItem.key,
    head_msg_id: firstItem.message.msg_id,
    head_ts: firstItem.message.ts_sent,
  };
  const store = new ObjectStoreStub();
  store.headReads = [{ body: head, etag: "etag-1" }];
  store.objects.set(firstItem.key, { payload: firstItem.message, etag: "etag-msg" });
  const checkpointStore = new InMemoryCheckpointStore();
  const transport = new R2RelayTransport({ store, keyspace: new RelayKeyspace(), peerId: "relay.hermes.local", checkpointStore, sleep: noSleep });

  await assert.rejects(
    () => transport.pollInbox("clawchat-ios-alice", async () => {
      throw new Error("boom");
    }, 1, 2, true),
    /boom/,
  );

  const state = checkpointStore.load();
  assert.equal(state.lastHeadKey, null);
  assert.deepEqual(state.recentObjectKeys, []);
  assert.deepEqual(store.deletedObjects, []);
});

test("sweepRetention combines key-timestamp and last-modified retention rules", async () => {
  const dayMs = 24 * 60 * 60 * 1000;
  const now = 2 * dayMs;
  const keyspace = new RelayKeyspace({ nowMsFactory: () => now });
  const oldMessageKey = keyspace.makeMsgKey("peer-a", 0, "old-msg");
  const newMessageKey = keyspace.makeMsgKey("peer-a", now - 1000, "new-msg");
  const store = new ObjectStoreStub();
  store.listPages = [
    {
      contents: [{ Key: oldMessageKey }, { Key: newMessageKey }],
      nextContinuationToken: null,
      isTruncated: false,
    },
    {
      contents: [{ Key: "identity/peer-a.json", LastModified: new Date(0) }],
      nextContinuationToken: null,
      isTruncated: false,
    },
  ];
  const transport = new R2RelayTransport({ store, keyspace, peerId: "relay.openclaw.dev" });

  const summaries = await transport.sweepRetention({ msg: 1, identity: 1 });

  assert.deepEqual(summaries, [
    { prefix: "msg/", scanned: 2, deleted: 1 },
    { prefix: "identity/", scanned: 1, deleted: 1 },
  ]);
  assert.deepEqual(store.deletedObjects, [oldMessageKey, "identity/peer-a.json"]);
});
