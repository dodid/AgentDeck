# Canonical Shared Relay Contract — v3

Status: current, production contract
Date: 2026-08-29

This document defines the v3 Cloudflare R2 object contract shared by ClawChat, OpenClaw, Hermes, and future agent platforms. v3 is a clean break from v2: the wire model is redesigned so that both OpenClaw (multi-agent, multi-channel, multi-tenant) and Hermes (single-agent, multi-platform, multi-source) are first-class with no “native_” escape hatches and no platform-specific blobs in the routing surface.

This is the only supported relay contract. Implementations do not contain downgrade or migration paths.

## Design Principles

1. **One field, one meaning.** No field is overloaded by platform.
2. **Decomposed addressing.** Routing names structured fields rather than packing meaning into one opaque string.
3. **First-class agents.** Agents are named entities in the identity doc, not inferred from a session-key prefix.
4. **Routing vs description split.** The route carries the minimum needed to address a conversation. All display/native metadata lives on the conversation descriptor.
5. **Sum types over flat nullable fields.** Message content is a discriminated union.
6. **Platform-neutral envelope.** Neither platform gets `native_*` fields or a private `platform_data` blob.

## Object Prefixes and Keys

The v3 object key layout is:

- `identity/<peer>.json`
- `head/<recipient>.json`
- `msg/<recipient>/<rev_ts>-<suffix>.json`
- `att/<recipient>/<rev_ts>-<safe_message_id>-<index_2d>[-<safe_name>]`

`MAX_MS = 9999999999999`, `rev_ts = zfill_13(MAX_MS - ts_ms)`.

`msg/` and `att/` keys embed reverse timestamps. `identity/` and `head/` keys do not.

## Route — `RelayRoute`

The route is the minimum address needed to identify a conversation on a server. It has exactly three fields:

| Field | Type | Required | Meaning |
|---|---|---|---|
| `agent_id` | string | yes | Logical assistant within the server. OpenClaw: configured agent id (`main`, `coding`, …). Hermes: usually `main`. |
| `conversation_id` | string \| null | no | Server-scoped, server-issued, opaque conversation handle. Clients store and echo it; never parse it. Omit to address the agent's default chat. |
| `instance_id` | string \| null | no | Server-issued runtime/transcript identifier for the current conversation epoch. Changes when the server resets context (`/new`, `/reset`, idle expiry, daily reset). |

### Send vs Receive Semantics

| Field | Client → Server send | Server → Client receive |
|---|---|---|
| `agent_id` | Required. Picks the target agent. | Echo of resolved agent. |
| `conversation_id` | Optional. Omit to start a default chat with the agent. Echo when continuing an existing conversation. | Required when known. Server-resolved, stable. |
| `instance_id` | Optional. Echo last-known for diagnostics. | Required when known. Clients diff against last-known to detect reset. |

Clients reconcile conversations by `(gateway_peer, agent_id, conversation_id)`. `instance_id` changes do not change identity; they only signal that the server reset the transcript.

### What `conversation_id` is not

- Not a session key the client may parse for UI semantics.
- Not the same as `instance_id`. Reset issues a new `instance_id`; `conversation_id` stays.
- Not the same as a thread id. Native threads belong to `ConversationSource.thread_id`.

## Message — `RelayMessage`

```ts
interface RelayMessage {
  msg_id: string;
  from: string;
  to: string;
  ts_sent: number;
  prev_key: string | null;

  route: RelayRoute;
  content: RelayContent;

  delivery?: RelayDelivery | null;
  status?: RelayMessageStatus | null;
}
```

`msg_id`, `from`, `to`, `ts_sent`, and `prev_key` form the peer envelope and linked inbox chain.

## Content — `RelayContent`

Discriminated union by `type`. Adding a new variant is a backward-compatible extension; clients ignore unknown `type` values.

```ts
type RelayContent =
  | RelayTextContent
  | RelayReactionContent
  | RelayApprovalRequestContent
  | RelayApprovalResponseContent
  | RelaySystemContent;

interface RelayTextContent {
  type: "text";
  text: string;
  attachments?: AttachmentRef[];
}

interface RelayReactionContent {
  type: "reaction";
  target_msg_id: string;
  emoji: string;
  remove?: boolean;
}

interface RelayApprovalRequestContent {
  type: "approval_request";
  approval_id: string;
  approval_kind: "exec" | "tool" | "custom";
  title: string;
  body?: string | null;
  allowed_decisions: string[];
  metadata?: Record<string, unknown> | null;
}

interface RelayApprovalResponseContent {
  type: "approval_response";
  approval_id: string;
  decision: string;
  metadata?: Record<string, unknown> | null;
}

interface RelaySystemContent {
  type: "system";
  event: string;
  data?: Record<string, unknown> | null;
}
```

`system` is the escape hatch for events that don’t yet warrant a typed variant. Future platform-specific approvals or events should be promoted to typed variants before becoming load-bearing.

## Delivery — `RelayDelivery`

Delivery is orthogonal to content. A streamed assistant text reply is `content.type = "text"` plus `delivery.stream`.

```ts
interface RelayDelivery {
  stream?: {
    stream_id: string;
    seq: number;
    state: "partial" | "final";
  } | null;
}
```

Reactions and approval messages are never streamed.

## Status — `RelayMessageStatus`

```ts
interface RelayMessageStatus {
  state: "pending" | "processing" | "done" | "error";
  processed_at?: number | null;
  processed_by?: string | null;
  error?: string | null;
}
```

Replaces v2 flat `processed_*` fields.

## Identity Document — `IdentityDoc`

Stored at `identity/<peer>.json`.

```ts
interface IdentityDoc {
  peer: string;
  role: "server" | "client";
  display_name: string;
  last_seen: number;

  protocol: { name: "r2-relay"; version: 3 };
  software: { id: string; name?: string | null; version?: string | null };

  capabilities: RelayCapabilities;
  limits?: ServerLimits | null;

  agents: AgentDescriptor[];
  conversations: ConversationDescriptor[];
}
```

`software.id` carries `openclaw`, `hermes`, or any future server id. v2’s `software_id`/`software_name`/`software_version` flat fields collapse here.

`protocol.version` replaces v2 `relay_protocol_versions[]`. v3 servers publish `3`; clients reject unsupported versions explicitly.

### Capabilities — `RelayCapabilities`

Grouped, shallow (two levels max).

```ts
interface RelayCapabilities {
  messaging: {
    text: boolean;
    streaming: boolean;
    reactions: boolean;
    system_events: boolean;
  };
  conversations: {
    list: boolean;
    create: boolean;
    reset: boolean;
    archive: boolean;
    threading: boolean;
  };
  agents: {
    list: boolean;
    multiple: boolean;
    switch: boolean;
    per_agent_models: boolean;
  };
  attachments?: {
    supported: boolean;
    kinds: AttachmentKind[];
    max_bytes_by_kind?: Partial<Record<AttachmentKind, number>>;
    oversize_behavior?: "reject" | "drop" | "link" | "summarize";
  } | null;
  approvals?: {
    exec: boolean;
    tool: boolean;
    custom: boolean;
  } | null;
  extensions?: Record<string, unknown> | null;
}
```

`extensions` is an open object for forward-compat server hints; clients must tolerate unknown keys.

### Agents — `AgentDescriptor`

```ts
interface AgentDescriptor {
  id: string;
  display_name?: string | null;
  description?: string | null;
  is_default: boolean;

  /** Route to start a fresh chat with this agent. conversation_id is omitted. */
  default_route: RelayRoute;

  models?: { available: ModelDescriptor[]; default?: string | null } | null;
  capabilities?: Partial<RelayCapabilities> | null;
}

interface ModelDescriptor {
  id: string;
  label?: string | null;
  provider?: string | null;
}
```

Agents are first-class. ClawChat lists agents directly; it does not parse `agent:<id>` prefixes from session keys.

`default_route` lets a client start a chat with any advertised agent before any conversation exists.

### Conversations — `ConversationDescriptor`

```ts
interface ConversationDescriptor {
  id: string;                    // identity-doc row id (= route.conversation_id)
  route: RelayRoute;             // route to address this conversation
  display_title?: string | null;
  updated_at?: number | null;
  source?: ConversationSource | null;
}
```

`ConversationDescriptor` lists real conversations the server is currently maintaining. Entrypoint chats are addressed via `AgentDescriptor.default_route`; they do not appear here until they have content.

### Conversation Source — `ConversationSource`

Native context for display. The route carries no display strings; everything lives here.

```ts
interface ConversationSource {
  channel: string;                          // "r2_relay" | "slack" | "discord" | "telegram" | "local" | ...
  chat_kind?: "dm" | "group" | "channel" | "thread" | null;

  account_id?: string | null;               // workspace/org id
  account_display?: string | null;

  space_id?: string | null;                 // guild / team scope
  space_display?: string | null;

  chat_id?: string | null;                  // native chat container id
  chat_display?: string | null;

  participant_id?: string | null;           // counterparty user id
  participant_display?: string | null;

  thread_id?: string | null;                // native thread/topic id
  thread_display?: string | null;

  sharing?: "private" | "shared" | "per-user" | null;
}
```

## Attachments — `AttachmentRef`

Attachment references use the following v3 shape:

```ts
type AttachmentKind = "image" | "video" | "audio" | "file" | "unknown";

interface AttachmentRef {
  id: string;
  key: string;
  file_name: string | null;
  content_type: string | null;
  size: number | null;
  sha256: string | null;
  kind: AttachmentKind;
  width: number | null;
  height: number | null;
  duration_ms: number | null;
  preview_image_key: string | null;
  preview_image_type: string | null;
  preview_size: number | null;
}
```

## Server Limits — `ServerLimits`

```ts
interface ServerLimits {
  inbound_attachment_max_bytes?: {
    image: number;
    video: number;
    audio: number;
    file: number;
  } | null;
  oversize_attachment_behavior?: "reject" | "drop" | "link" | "summarize" | null;
}
```

`capabilities.attachments` advertises general support; `limits` supplies the server's concrete inbound enforcement values when configured.

## Chain Semantics

Inbox ordering is a linked, compare-and-swap head chain:

- `head/<recipient>.json` points at the newest message object.
- Each message links backward with `prev_key`.
- Readers traverse from head to older messages until they reach the previous checkpoint, a null `prev_key`, a missing object, a duplicate key, or an implementation cap.
- Returned inbox batches are ordered oldest to newest.

## Platform Mappings

### OpenClaw

| OpenClaw concept | v3 location |
|---|---|
| Configured agent id (`main`, `coding`) | `route.agent_id` |
| `buildAgentPeerSessionKey(...)` output | `route.conversation_id` (opaque) |
| Runtime session UUID | `route.instance_id` |
| Channel (slack, discord, r2_relay, …) | `source.channel` |
| `accountId` | `source.account_id` |
| `peerKind` (direct/group/channel) | `source.chat_kind` |
| Peer id | `source.chat_id` (group/channel) or `source.participant_id` (DM) |
| `:thread:{id}` suffix | `source.thread_id` (folded into `conversation_id`) |
| `dmScope` policy | Reflected in `conversation_id` differences; opaque to client |
| Exec approval `platform_data` blob (v2) | `content.type = "approval_request"` |

### Hermes

| Hermes concept | v3 location |
|---|---|
| Single agent (today: `main`) | `route.agent_id` |
| `SessionEntry.session_key` | `route.conversation_id` |
| `SessionEntry.session_id` | `route.instance_id` |
| `Platform.value` (telegram, discord, slack, …) | `source.channel` |
| `SessionSource.chat_type` | `source.chat_kind` |
| `chat_id` / `chat_name` | `source.chat_id` / `source.chat_display` |
| `user_id` / `user_name` | `source.participant_id` / `source.participant_display` |
| `guild_id` | `source.space_id` |
| `thread_id` (forum topic, Discord thread) | `source.thread_id` |
| `shared_multi_user_session` | `source.sharing = "shared"` |

## What v3 Removes vs. v2

Removed from the route:

- `platform`
- `native_thread_id`
- `native_agent_id`

Removed from messages:

- `type` (replaced by `content.type`)
- `body` (replaced by `RelayTextContent.text`)
- `reaction_target_msg_id`, `reaction_emoji`, `reaction_remove` (replaced by `RelayReactionContent`)
- `stream_id`, `stream_seq`, `stream_state` (replaced by `delivery.stream`)
- `platform_data` (replaced by typed `content` variants)
- flat `processed_*` fields (replaced by `RelayMessageStatus`)

Removed from identity:

- `software_id`/`software_name`/`software_version` flat fields (collapsed into `software`)
- `relay_protocol_versions[]` (collapsed into `protocol.version`)
- `capabilities[]` string array (replaced by `RelayCapabilities`)
- `platform_capabilities` (subsumed by `capabilities.extensions` and typed content variants)

Removed from `IdentityConversationDoc`:

- `platform` (redundant with `IdentityDoc.software.id`)
- `chat_type` (moved to `ConversationSource.chat_kind`)

## Compatibility

v3 servers do not emit earlier flat fields and v3 clients do not consume them. Compatibility is explicit through `protocol.version`:

- v3 server publishes `protocol = { name: "r2-relay", version: 3 }`.
- v3 client refuses to talk v2-shaped peers and surfaces a setup error.

There is no in-band negotiation; the protocol version is part of the discovery document and either matches or doesn't.

## Reset Detection (informative)

```pseudo
on receive(message):
  session = lookup(gateway_peer, route.agent_id, route.conversation_id)
  if route.instance_id and session.last_instance_id and
     route.instance_id != session.last_instance_id:
    insert_reset_divider(session)
  if route.instance_id:
    session.last_instance_id = route.instance_id
```

The server is authoritative for `instance_id`. Clients echo the last-known value on send for diagnostic correlation only; the server may overwrite it on the next reply.

## Open Questions

- Multi-agent Hermes is not in scope today but the contract already supports it via `agents[]`.
- `archive` lifecycle on conversations is reserved for the future; v3 servers may emit only currently-active conversations.
- `extensions` namespace conventions (per-software prefix?) are not formalized; defer until a real consumer needs it.
