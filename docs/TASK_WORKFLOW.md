# Task Workflow

This file defines the default execution loop for coding work in this project.

## Goal

Enable autonomous feature and bug work without architecture drift across:

- `apps/ios/`
- `packages/relay-core/`
- `integrations/openclaw/`
- `integrations/hermes/`

## Default workflow

### 1. Read the owning code paths first

Before editing, inspect the concrete implementation paths involved.
Do not rely on stale assumptions from older root-level docs.

Minimum questions:

- what is the user-visible behavior?
- which layer owns it?
- is there a protocol boundary involved?
- is this iOS-only, integration-only, or a coordinated protocol change?

### 2. Identify the owning layer

Use these defaults:

#### ClawChat
- `apps/ios/ClawChat/Features/` — feature UI and view models
- `apps/ios/ClawChat/UI/` — reusable UI/navigation/theme
- `apps/ios/ClawChat/Domain/` — app models and repository contracts
- `apps/ios/ClawChat/Data/` — persistence and repository implementations
- `apps/ios/ClawChat/Services/` — relay transport, sync, and integration infrastructure

#### Relay and platform integrations
- `packages/relay-core/spec/` — executable wire contract and fixtures
- `integrations/openclaw/src/` — OpenClaw lifecycle and mapping
- `integrations/hermes/src/r2_relay_adapter/` — Hermes lifecycle and mapping
- vendored transport copies — runtime packaging only; verify with `tools/ci/check-vendored-core.sh`

### 3. Apply the smallest clean change

Prefer:

- extending an existing seam
- localizing behavior changes
- preserving current architecture direction

Avoid:

- opportunistic refactors unrelated to the task
- moving logic across layers without cause
- embedding transport/storage logic in SwiftUI views

### 4. Run the relevant checklist

#### If changing iOS UI behavior
- is the view still thin?
- did orchestration stay in the view model?
- did domain/infrastructure code stay out of the SwiftUI view?

#### If changing relay behavior
- are key prefixes and field names still aligned?
- do both plugin and iOS models still agree?
- did session routing behavior change?
- did discovery behavior change?

#### If changing the protocol
- update every affected implementation in the same commit
- update fixtures before or with code
- run the vendored-core drift check

### 5. Verify at the right level

#### Linux verification
Use for:
- TypeScript and Python build/check steps
- OpenClaw and Hermes compatibility tests
- docs updates
- static Swift inspection

#### macOS verification
Use for:
- `xcodebuild`
- XCTest
- simulator/device runs

Run commands from the monorepo root so local paths match GitHub Actions.

### 6. Update docs when truth changes

Update `docs/ARCHITECTURE_TRUTH.md` and/or `docs/WORKING_CONVENTIONS.md` when:

- source code changes effective architecture
- protocol truth changes
- a stale assumption is corrected
- a new durable convention is established

## Cross-component feature template

When a task touches both app and plugin, think in this order:

1. protocol contract
2. plugin behavior
3. app relay/service behavior
4. persistence/model effects
5. view model effects
6. UI surface changes
7. verification

## Completion checklist

Before closing a task, confirm:

- code follows current architecture
- docs are still accurate
- protocol drift was checked if relevant
- verification was run where practical
- any remaining macOS-only verification need is called out explicitly
