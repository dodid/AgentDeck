export interface RelayTarget {
  peer: string;
  conversationId: string | null;
}

const RESERVED_VALUE_CHARS = /[=,]/;

export function parseRelayTarget(raw: string): RelayTarget {
  const input = raw.trim();
  if (!input) {
    throw new Error("Missing relay target");
  }

  if (!input.includes("=")) {
    return {
      peer: input,
      conversationId: null,
    };
  }

  const pairs = input.split(",");
  let peer: string | null = null;
  let conversationId: string | null = null;

  for (const pair of pairs) {
    const trimmed = pair.trim();
    if (!trimmed) {
      continue;
    }

    const eqIndex = trimmed.indexOf("=");
    if (eqIndex <= 0) {
      throw new Error(`Invalid relay target segment: ${trimmed}`);
    }

    const key = trimmed.slice(0, eqIndex).trim().toLowerCase();
    const value = trimmed.slice(eqIndex + 1).trim();
    if (!value) {
      throw new Error(`Missing relay target value for ${key}`);
    }
    if (RESERVED_VALUE_CHARS.test(value)) {
      throw new Error(`Relay target values cannot contain ',' or '=' (${key})`);
    }

    if (key === "peer") {
      peer = value;
      continue;
    }
    if (key === "conversation") {
      conversationId = value;
      continue;
    }

    throw new Error(`Unsupported relay target key: ${key}`);
  }

  if (!peer) {
    throw new Error("Relay target must include peer=<peer>");
  }
  if (!conversationId) {
    throw new Error("Relay target must include conversation=<conversationId>");
  }

  return { peer, conversationId };
}

export function formatRelayTargetHint(): string {
  return "peer=<peer>,conversation=<conversationId>";
}
