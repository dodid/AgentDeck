import test from "node:test";
import assert from "node:assert/strict";

import { shouldPublishIdentitySession } from "./session-publication.js";

test("identity publishes interactive conversations but not runtime execution sessions", () => {
  assert.equal(shouldPublishIdentitySession("agent:main:telegram:direct:user-1"), true);
  assert.equal(shouldPublishIdentitySession("agent:main:discord:channel:room-1:thread:topic-1"), true);

  assert.equal(shouldPublishIdentitySession("agent:main:cron:nightly"), false);
  assert.equal(shouldPublishIdentitySession("agent:main:subagent:worker-1"), false);
  assert.equal(shouldPublishIdentitySession("agent:main:acp:run-1"), false);
  assert.equal(shouldPublishIdentitySession("agent:main:dreaming-summary"), false);
});
