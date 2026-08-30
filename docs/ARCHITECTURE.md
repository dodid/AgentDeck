# AgentDeck Architecture

AgentDeck is a monorepo containing an iOS client, a host-neutral relay contract, and native integrations for OpenClaw and Hermes.

## Components

### iOS app

`apps/ios/AgentDeck/` follows MVVM and separates responsibilities by layer:

- `App/` composes dependencies through `AppEnvironment.makeDefault()`.
- `Domain/` contains application models and repository protocols.
- `Data/` contains SQLite persistence, credential stores, and repository implementations.
- `Services/` contains R2 transport, discovery, messaging, sync, attachments, billing, and speech services.
- `Features/` contains screen views and view models.
- `UI/` contains shared navigation and theme components.

R2 credentials are stored in Keychain. Messages, sessions, attachment metadata, and derived presentation state are stored locally with GRDB.

### Relay contract

`packages/relay-core/` contains:

- the normative relay v3 Markdown specification;
- an executable JSON Schema;
- canonical fixtures;
- TypeScript and Python reference transports.

The protocol uses these object prefixes:

- `identity/{peer}.json`
- `head/{peer}.json`
- `msg/{recipient}/{reverseTimestamp}-{id}.json`
- `att/{recipient}/{reverseTimestamp}-{messageId}-{index}-{name}`

Messages form an inbox chain through `prev_key`. Writers upload an immutable message object and conditionally update the recipient head. Compare-and-swap retries prevent concurrent writers from losing messages.

### OpenClaw integration

`integrations/openclaw/` is an OpenClaw channel plugin. It publishes gateway identity, polls relay inboxes, maps relay routes to OpenClaw sessions, sends responses, and uploads supported outbound media as relay attachments.

OpenClaw lifecycle, cron, webhook, session, and channel behavior stays inside this integration.

### Hermes integration

`integrations/hermes/` is a Hermes user plugin and Python adapter. It maps Hermes conversations and events to the same relay v3 identity, routing, message, stream, reaction, approval, and attachment model.

Hermes lifecycle and conversation mapping stay inside this integration.

## Shared transport packaging

Each host integration vendors the small reference transport it ships with:

- OpenClaw: `integrations/openclaw/src/relay-core/`
- Hermes: `integrations/hermes/src/r2_relay_adapter/relay_core/`

`tools/ci/check-vendored-core.sh` verifies that vendored files match `packages/relay-core/`. This keeps installation self-contained while making protocol drift visible in CI.

## Discovery

Platforms publish `identity/{peer}.json` documents containing protocol version, platform metadata, capabilities, agents, and active conversations. AgentDeck lists identities from the bucket and maps agents and conversations into its navigation model.

Routes use `agent_id` with optional `conversation_id` and `instance_id`. AgentDeck preserves these fields rather than encoding platform-specific assumptions into session titles.

## Messaging

### Outbound from iOS

1. The feature view model creates a local message.
2. Attachments are uploaded before the message is committed.
3. `RelaySyncEngine` resolves the target and calls the relay messaging service.
4. The service appends a relay message through the recipient’s CAS-protected head.
5. The local database records success or failure and republishes the transcript.

### Inbound to iOS

1. The sync engine reads the device inbox head.
2. It walks unread message objects through `prev_key`.
3. Messages and attachment metadata are persisted.
4. Transcript presentation maps stored records into view data.
5. Attachment content is downloaded lazily when needed.

## Contract coordination

The executable schema is the canonical wire contract. Protocol changes must be coordinated across:

- `packages/relay-core/spec/`
- TypeScript and Python reference transports
- OpenClaw protocol bindings
- Hermes protocol bindings
- AgentDeck relay models

Flat v2 fields and platform-specific routing blobs are not accepted by relay v3.

## Trust model

Relay documents are not end-to-end signed. Bucket access policy and R2 credentials are therefore the primary trust boundary: any principal with object-write permission can forge relay objects.

Use least-privilege credentials, limit access to the required bucket, rotate exposed keys promptly, and use separate buckets or credentials for unrelated environments.
