# AGENTS.md

## Source of truth

Use this order when guidance disagrees:

1. current source code
2. `docs/ARCHITECTURE_TRUTH.md`
3. `docs/WORKING_CONVENTIONS.md`
4. older design documents

## Architecture

- Keep the iOS app in `apps/ios/` strict MVVM. Views render state and forward intents; orchestration belongs in view models.
- Keep domain contracts in `apps/ios/ClawChat/Domain/`, persistence in `apps/ios/ClawChat/Data/`, and relay infrastructure in `apps/ios/ClawChat/Services/`.
- `AppEnvironment.makeDefault()` is the iOS composition root.
- Keep OpenClaw-specific behavior in `integrations/openclaw/` and Hermes-specific behavior in `integrations/hermes/`.
- Treat `packages/relay-core/spec/relay-contract-v3.schema.json` and its fixtures as the executable relay contract.

## Relay contract rule

For protocol changes, inspect and update all coordinated implementations:

- `packages/relay-core/spec/`
- `packages/relay-core/ts/`
- `packages/relay-core/python/`
- `integrations/openclaw/src/protocol.ts`
- `integrations/hermes/src/r2_relay_adapter/protocol.py`
- `apps/ios/ClawChat/Services/Relay/RelayMessageModels.swift`

Run `tools/ci/check-vendored-core.sh` after shared transport changes.

## Credentials

- Pull-request and scheduled compatibility tests must remain credential-free.
- Never add Apple signing material, App Store Connect keys, personal R2 credentials, model-provider keys, or Ubuntu SSH credentials to the repository.
- CI uses disposable MinIO and test identities. Personal Ubuntu and production R2 are manual staging boundaries.
- Distribution signing belongs to Xcode Cloud, not GitHub Actions.

## Verification

- Linux is authoritative for TypeScript, Python, OpenClaw, Hermes, schema, and disposable MinIO checks.
- macOS is authoritative for Xcode builds, XCTest, and simulator validation.
- Keep ordinary PR checks deterministic. Upstream-latest checks belong in the scheduled canary workflow.
