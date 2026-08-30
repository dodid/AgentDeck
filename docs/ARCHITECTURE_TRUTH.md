# Architecture Truth

_Last updated from the clean monorepo refactor on 2026-08-29._

This document records the current project architecture as implemented in source, not just as described in older design docs.

## Repository model

The maintained source is one monorepo. Cross-component protocol changes are committed and tested atomically. Previous component repositories are historical archives and are not runtime dependencies or CI inputs.

- Linux is authoritative for TypeScript, Python, OpenClaw, Hermes, schema, and disposable object-store checks.
- macOS is authoritative for Xcode, XCTest, and simulator validation.
- Xcode Cloud is the intended signing and TestFlight/App Store distribution boundary.
- Personal Ubuntu and R2 environments are outside scheduled automation.

## Project components

### 1. iOS app: `apps/ios/`

Current structure from source:

- `apps/ios/ClawChat/App/` — app bootstrap and composition
- `apps/ios/ClawChat/Domain/` — domain models and repository protocols
- `apps/ios/ClawChat/Data/` — repository implementations, persistence, stores
- `apps/ios/ClawChat/Services/` — relay transport and sync services
- `apps/ios/ClawChat/Features/` — screen-level SwiftUI views and view models
- `apps/ios/ClawChat/UI/` — shared navigation/theme UI

### 2. OpenClaw plugin: `integrations/openclaw/`

Current structure from source:

- `integrations/openclaw/src/channel.ts` — OpenClaw plugin entrypoint and runtime integration
- `integrations/openclaw/src/service.ts` — relay service logic and identity publication
- `integrations/openclaw/src/protocol.ts` — wire-level key builders and shared protocol types
- `integrations/openclaw/src/r2client.ts` — R2 client behavior
- `integrations/openclaw/src/config.ts` — plugin config resolution
- `integrations/openclaw/src/runtime.ts` — OpenClaw runtime access helpers
- `integrations/openclaw/src/target.ts` — outbound target parsing/formatting
- `integrations/openclaw/src/checkpoint-store.ts` — checkpoint persistence
- `integrations/openclaw/src/relay-core/` — vendored transport primitives packaged with the plugin

### 3. Hermes adapter: `integrations/hermes/`

Current structure from source:

- `integrations/hermes/src/r2_relay_adapter/adapter.py` — Hermes adapter entrypoint, polling loop, and host event mapping
- `integrations/hermes/src/r2_relay_adapter/service.py` — relay service logic and identity publication
- `integrations/hermes/src/r2_relay_adapter/protocol.py` — wire-level key builders and shared protocol types
- `integrations/hermes/src/r2_relay_adapter/client.py` — R2 client behavior
- `integrations/hermes/src/r2_relay_adapter/checkpoint_store.py` — checkpoint persistence
- `integrations/hermes/src/r2_relay_adapter/hermes_plugin.py` — Hermes plugin registration
- `integrations/hermes/src/r2_relay_adapter/relay_core/` — vendored transport primitives packaged with the adapter

## Relay transport architecture truth

Current source uses a self-contained dual-native packaging layout inside one repository:

- `integrations/openclaw/` contains its own vendored relay transport in `src/relay-core/`
- `integrations/hermes/` contains its own vendored relay transport in `src/r2_relay_adapter/relay_core/`
- `packages/relay-core/` remains the protocol/spec reference, not a runtime package dependency of either integration
- `tools/ci/check-vendored-core.sh` enforces byte-for-byte drift checks in CI

Current host-owned layers are:

- `integrations/openclaw/` as the OpenClaw-native channel plugin layer
- `integrations/hermes/` as the Hermes-owned adapter layer

Current boundary rules already implied by source:

- OpenClaw-specific runtime lifecycle, routing, webhook, cron, and channel behaviors live in `integrations/openclaw/`
- Hermes-specific adapter lifecycle and conversation mapping live in `integrations/hermes/`
- protocol evolution must stay coordinated across the vendored plugin transports, `packages/relay-core/spec/`, and the iOS relay models

## Current composition truth in ClawChat

`AppEnvironment.makeDefault()` is the main composition root.

It currently wires:

- `DefaultConnectionRepository`
- `DefaultSettingsRepository`
- `DefaultDeviceRepository`
- `AppDatabase`
- `DefaultChatRepository`
- `DefaultDiscoveryRepository`
- `SyncActivityStore`
- `RelaySyncEngine`
- `DefaultSyncRepository`
- `ChatAppearanceController`
- `SubscriptionController`

## ClawChat domain preservation truth

Current source preserves v3 relay metadata in app models and persistence, including:

- routes composed of `agent_id`, optional `conversation_id`, and optional `instance_id`
- sender/peer distinctions such as `sender_kind` and `sender_value`
- identity agent, conversation, model, source, and capability metadata

ClawChat domain models stay product-neutral while retaining platform-native route metadata for OpenClaw, Hermes, and future relay platforms.

### Dependency shape

Current high-level flow:

- Views bind to feature view models
- Feature view models depend on `AppEnvironment`
- `AppEnvironment` exposes repository abstractions and runtime helpers
- `RelaySyncEngine` handles relay send/sync behavior
- `RelayMessagingService` and `RelayDiscoveryService` talk to R2 storage
- `AppDatabase` persists sessions/messages/message attachments and derived state

## Current MVVM truth in ClawChat

The app is already close to a layered MVVM architecture.

### Observed feature pattern

Example feature directories:

- `Features/ChatDetail/`
- `Features/ChatList/`
- `Features/Onboarding/`
- `Features/Settings/`
- `Features/ConnectionEditor/`

Typical feature structure:

- `...View.swift` — SwiftUI rendering
- `...ViewModel.swift` — screen orchestration and state
- supporting presentation helpers in the same feature folder when needed

### Important current seam

`ChatDetailViewModel` performs orchestration, local send initiation, transcript updates, and sync triggering.
That is acceptable as current application-layer behavior, but future feature work should keep transport details inside repositories/services rather than leaking them into views.

## Current relay protocol truth from source

The canonical protocol is currently represented in:

- plugin: `integrations/openclaw/src/protocol.ts`
- iOS app: `apps/ios/ClawChat/Services/Relay/RelayMessageModels.swift`

### Canonical object prefixes from current code

From actual source implementation, the current key layout is:

- `identity/{peer}.json`
- `head/{peer}.json`
- `msg/{recipient}/{revTs}-{id}.json`
- `att/{recipient}/{revTs}-{messageId}-{zeroPaddedIndex}{-name}`

### Important mismatch with older docs

Older design material references layouts like:

- `identify/{peer}.json`
- `inbox/{peer}/head.json`
- `inbox/{peer}/msg/...`

Those are **not** the current code-level convention.
For implementation work, the canonical convention is the one in source:

- `identity/`
- `head/`
- `msg/`
- `att/`

## Discovery truth

Current discovery behavior in the iOS app:

- `RelayDiscoveryService` lists objects under `identity/`
- it filters `identity/*.json`
- it decodes server identities and maps them into `GatewaySection`
- it treats stale identities as older than 12 hours
- `DefaultDiscoveryRepository` throttles automatic foreground discovery refreshes to avoid frequent R2 reads while still allowing explicit user-initiated refreshes to bypass the throttle

Current plugin behavior:

- `Service.publishIdentity()` writes `identity/{peer}.json`
- plugin identity docs are published as relay contract v3 documents with `protocol.version = 3`
- identity payloads include grouped capabilities, first-class `agents[]`, and active `conversations[]`
- agent entrypoints are advertised through `AgentDescriptor.default_route`; only real active chats appear in `conversations[]`
- OpenClaw conversation publication intentionally excludes cron-owned native sessions such as `cron:<jobId>` and `agent:<agentId>:cron:<jobId>` so mobile clients only see user-facing chats
- Hermes publishes a single discovery conversation today, but it now advertises optional configured model availability and conversation title through the same identity contract used by the app

## Messaging truth

### iOS app outbound

Current outbound send flow:

1. feature view model initiates send
2. local message is created in the chat repository/database
3. `RelaySyncEngine.sendExistingLocalMessage(...)` resolves target and device profile
4. `RelayMessagingService.sendMessage(...)` appends a relay message via CAS-style head update
5. local DB is marked sent or failed
6. if local draft attachments are present, originals are uploaded to R2 before relay message commit
7. uploaded attachment refs replace pending local draft rows in the DB before send completes
8. sync is triggered to refresh state

### iOS app inbound

Current inbound flow:

1. sync engine loads the device inbox head
2. relay messages are collected from the linked chain
3. database ingests inbox entries, including `content.attachments[]`
4. attachment rows are persisted in `message_attachments`
5. transcript presentation maps attachment metadata into UI view-data
6. lazy preview/download fetches can load attachment objects from R2 on demand
7. affected transcripts are republished to the UI

### Plugin outbound

Current plugin outbound behavior is owned by `Service.sendMessage(...)` plus the channel outbound adapter in `integrations/openclaw/src/channel.ts`.
It uses:

- `head/{peer}.json` for the current head
- `msg/{peer}/...` message objects
- `att/{peer}/...` attachment objects for outbound media payloads
- CAS retry on head updates
- v3 `RelayRoute { agent_id, conversation_id, instance_id }`
- v3 discriminated `content` unions plus optional `delivery.stream` and `status`
- per-recipient send serialization through `sendLanes`
- payload-aware outbound delivery for `ReplyPayload.mediaUrl` / `mediaUrls`
- the shared OpenClaw outbound media loader path for `media://...`, hosted plugin media, approved local paths, and remote URLs before R2 attachment upload

## Integration truth between app and relay hosts

The executable v3 contract is `packages/relay-core/spec/relay-contract-v3.schema.json`; canonical examples live beside it in `spec/fixtures/`. Messages use a required route plus a discriminated `content` union. Platform blobs and flat v2 message fields are not accepted.

The most important cross-codebase contract points are message/content fields, attachment descriptors, route identity, capabilities, streams, reactions, approvals, object keys, and identity discovery.

Current canonical anchors remain:

- `integrations/openclaw/src/protocol.ts`
- `apps/ios/ClawChat/Services/Relay/RelayMessageModels.swift`
- `apps/ios/ClawChat/Services/Relay/RelayDiscoveryModels.swift`

Additional conforming implementation:

- `integrations/hermes/src/r2_relay_adapter/protocol.py`

The current Hermes adapter and OpenClaw plugin should both conform to the same relay wire contract.
Any change to the wire contract should be treated as a coordinated plugin + app change, and any matching Hermes adapter implementation should be reviewed in the same task when affected.

## Verification truth

### Can be verified from Linux VM

- TypeScript/plugin code edits
- plugin builds/checks
- repo docs and structure changes
- protocol alignment review

### Requires macOS host

- Xcode build
- XCTest
- iOS simulator/device validation
- UI verification

## Architecture maintenance rule

If source code changes the effective architecture or protocol, update this file in the same task when practical.
