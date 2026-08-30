# Dual-Native Relay Architecture Plan (Archived)

> Historical v2 planning document. It is not implementation guidance. The current v3 architecture is documented in `ARCHITECTURE_TRUTH.md` and the executable contract in `r2-relay-core/spec/relay-contract-v3.schema.json`.

Status: implemented and superseded by current source
Date: 2026-05-21

## Problem

The relay transport behavior must remain available inside each plugin repo so packaging and deployment stay self-contained.
At the same time, the wire contract must stay consistent across OpenClaw, Hermes, and ClawChat.

Current self-contained transport locations are:

- `r2-relay-channel/src/relay-core/`
- `r2-relay-adapter/src/r2_relay_adapter/relay_core/`

The protocol reference remains in:

- `r2-relay-core/spec/`

## Decision

Adopt a dual-native relay architecture with self-contained plugin transports and one shared protocol/spec source of truth.

Decision summary:

- keep `r2-relay-channel` as the OpenClaw-native channel plugin
- keep `r2-relay-adapter` as the Hermes-native adapter
- keep their transport implementations vendored locally for packaging and deployment
- keep `r2-relay-core` as the protocol/spec contract reference instead of a required runtime package
- keep Hermes integration patch-based for now
- keep OpenClaw integration as a native channel plugin
- preserve the existing ClawChat/OpenClaw relay wire contract while preventing protocol drift across repos

## Shared vs host-specific boundaries

### Shared protocol/spec core: `r2-relay-core`

Owns:

- relay contract documentation
- protocol fixtures and examples
- canonical key-shape and field-name expectations used for cross-platform reviews

Must not own:

- OpenClaw runtime/plugin lifecycle code
- Hermes adapter wiring or BasePlatformAdapter code
- package-install requirements for either plugin
- product-specific UI/domain presentation policy

### OpenClaw host layer: `r2-relay-channel`

Owns:

- channel plugin lifecycle
- OpenClaw runtime access and configuration resolution
- OpenClaw-native outbound/inbound mapping
- identity publication details tied to OpenClaw session inventory

### Hermes host layer: `r2-relay-adapter`

Owns:

- Hermes adapter lifecycle and polling integration
- patch-based installation into Hermes
- Hermes-native event/thread/session mapping
- identity publication details tied to Hermes host behavior

### ClawChat app boundary

ClawChat should remain product-neutral where possible while preserving richer relay metadata needed by both hosts, including:

- peer-kind distinctions
- platform route fields such as `route.platform`, `route.conversation_id`, `route.native_thread_id`, and `route.native_agent_id`
- richer identity conversation metadata used for discovery and transcript routing

## Phased implementation order

1. Document the target architecture and boundaries in `docs/`.
2. Define the exact responsibilities that move from `r2-relay-channel` and `r2-relay-adapter` into `r2-relay-core`.
3. Extract or re-home the reusable relay transport layer without changing host-owned integration responsibilities.
4. Repoint `r2-relay-channel` to the shared core while preserving native plugin behavior.
5. Repoint `r2-relay-adapter` to the shared core while preserving patch-based Hermes integration.
6. Verify wire-contract parity and behavioral parity across ClawChat, OpenClaw, and Hermes.

Implementation outcome on 2026-05-21:

1. The transport/runtime dependency on `r2-relay-core` was removed from both plugin packages.
2. Transport primitives were vendored into each plugin repo.
3. `r2-relay-core/` was retained as the protocol/spec reference for coordinated cross-platform changes.

## Risks and tradeoffs

- extracting too much into shared code could blur the host boundary and make both integrations harder to evolve
- extracting too little would leave costly duplication in place
- the shared core may be constrained by cross-language or packaging realities
- preserving compatibility slows aggressive cleanup, but avoids protocol drift across the deployed app and hosts
- Hermes patch-based integration remains operationally heavier than a first-class native integration, but it is the lowest-risk near-term approach

## Consequences

Expected benefits:

- self-contained plugin packaging for both OpenClaw and Hermes
- clearer ownership boundaries between protocol spec and host runtime code
- easier coordinated protocol evolution across ClawChat, OpenClaw, and Hermes

Expected constraint:

- dual-native behavior remains intentional; the goal is shared protocol truth, not a single merged runtime package
