# Working Conventions

These conventions keep changes aligned across the iOS app, relay contract, OpenClaw integration, and Hermes integration in the monorepo.

## Guiding idea

Use harness-style discipline:

- prefer explicit constraints over memory
- prefer executable seams over vague architecture intentions
- prefer small verifiable changes over broad speculative rewrites
- keep source-of-truth docs current when drift is discovered

## Source-of-truth rule

When deciding how to implement something, use this order:

1. current source code
2. `docs/ARCHITECTURE_TRUTH.md`
3. this file
4. older design/spec docs at repo root

If an older doc conflicts with current code, do not silently follow the old doc.
Update the docs or call out the mismatch.

## Strict MVVM rules for ClawChat

### Views

SwiftUI views should:

- render state
- forward user intents
- own lightweight presentation-only concerns

SwiftUI views should not:

- talk directly to R2
- perform database work
- hold transport/business logic
- encode protocol decisions

### ViewModels

View models should:

- orchestrate feature behavior
- expose screen state
- call repositories/services through the app environment
- transform domain/application state into presentation state

View models should not:

- become dumping grounds for protocol/storage helpers
- reimplement database or transport layers inline

### Domain

Domain types should hold app concepts and contracts:

- models
- repository protocols
- shared semantics that outlive any one screen

### Data and Services

These layers own:

- persistence
- relay transport
- sync/polling
- protocol encoding/decoding
- repository implementations

## Feature placement rules

### iOS app

For a new UI feature, default placement is:

- `Features/<Feature>/<Feature>View.swift`
- `Features/<Feature>/<Feature>ViewModel.swift`
- local presentation helpers in the same feature folder

Only promote code into `Domain/`, `Data/`, `Services/`, or `UI/` when it is genuinely cross-feature or infrastructural.

### Plugin

For plugin work:

- protocol and key-shape changes start in `packages/relay-core/spec/` and must remain aligned with `integrations/openclaw/src/protocol.ts`
- relay send/receive behavior belongs in `integrations/openclaw/src/service.ts`
- OpenClaw plugin lifecycle/integration belongs in `integrations/openclaw/src/channel.ts`
- config behavior belongs in `integrations/openclaw/src/config.ts`

Do not scatter wire-shape literals across many files when a shared protocol/helper location exists.

## Dual-native relay boundary guardrails

For relay architecture work:

- keep each integration directory self-contained for runtime packaging
- keep OpenClaw host-native concerns out of Hermes code paths
- keep Hermes host-mapping concerns out of OpenClaw code paths
- preserve product-neutral ClawChat domain models where possible

Interpretation:

- vendored relay transport code should focus on protocol, key layout, R2 transport, head updates, and checkpoint primitives
- `integrations/openclaw/` owns OpenClaw-native plugin lifecycle, runtime integration, and channel behavior
- `integrations/hermes/` owns Hermes-native adapter behavior, plugin registration, and Hermes conversation mapping
- `packages/relay-core/spec/` owns the shared protocol fixtures and contract narrative used to keep platforms aligned
- ClawChat should retain richer relay metadata such as peer-kind and session routing details instead of collapsing them into host-specific labels too early

## Cross-codebase contract rule

The relay wire contract must be treated as shared infrastructure.

Current canonical anchors:

- plugin message and identity contract: `integrations/openclaw/src/protocol.ts`
- iOS message contract: `apps/ios/ClawChat/Services/Relay/RelayMessageModels.swift`
- iOS discovery and identity/session decoding: `apps/ios/ClawChat/Services/Relay/RelayDiscoveryModels.swift`

When protocol behavior changes, review both sides in the same task.

Checklist:

- object key prefixes still aligned?
- field names still aligned?
- optional vs required semantics still aligned?
- session routing semantics still aligned?
- streaming fields still aligned?
- reaction fields still aligned?
- identity/session/model discovery fields still aligned?
- `agents[]` entrypoints and `conversations[]` active chats still aligned?
- approval request/response payloads still aligned?

## Default task loop

For feature or bug work, follow this order:

1. inspect the relevant code paths
2. identify the owning layer
3. make the smallest clean change
4. verify locally where possible
5. update docs if the architectural truth changed
6. summarize what changed and any follow-up risk

## Verification matrix

### Linux

Use Linux for:

- editing all source
- plugin verification/build steps
- architectural/doc maintenance
- static inspection of Swift code

### macOS host

Use macOS for:

- `xcodebuild`
- XCTest
- simulator/device runs
- UI validation

Run commands from the monorepo root so workflow paths match local verification.

## Drift-prevention rule

When a task reveals stale docs, hidden assumptions, or an unclear boundary, prefer to add or update a lightweight guardrail document rather than relying on memory.

## Non-goals

- no automatic deployment or direct-to-main repair commits
- no large speculative refactors without need
- no mixing transport logic into SwiftUI views
- no protocol changes on only one side unless explicitly doing staged compatibility work
