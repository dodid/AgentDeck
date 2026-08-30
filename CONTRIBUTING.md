# Contributing to AgentDeck

Contributions are welcome. Keep changes focused, preserve the protocol boundary, and include tests for behavior that can regress.

## Prerequisites

- Node.js 22 or later
- Python 3.12 or later
- Xcode with an iOS 18 or later simulator for iOS work

## Architecture rules

The iOS app follows MVVM:

- SwiftUI views render state and forward user actions.
- Feature view models own screen state and orchestration.
- Domain models and repository protocols live in `apps/ios/AgentDeck/Domain/`.
- Persistence and repository implementations live in `apps/ios/AgentDeck/Data/`.
- Relay transport, sync, and infrastructure live in `apps/ios/AgentDeck/Services/`.
- Shared UI, navigation, and theming live in `apps/ios/AgentDeck/UI/`.

Platform-specific behavior belongs in its integration:

- OpenClaw behavior: `integrations/openclaw/`
- Hermes behavior: `integrations/hermes/`
- Host-neutral contract and fixtures: `packages/relay-core/`

## Relay protocol changes

Relay v3 is a coordinated contract. A wire-format change may require updates to:

- `packages/relay-core/spec/`
- `packages/relay-core/ts/`
- `packages/relay-core/python/`
- `integrations/openclaw/src/protocol.ts`
- `integrations/hermes/src/r2_relay_adapter/protocol.py`
- `apps/ios/AgentDeck/Services/Relay/RelayMessageModels.swift`

Run `tools/ci/check-vendored-core.sh` after changing shared transport code. Update the executable JSON Schema and canonical fixtures whenever the wire contract changes.

## Verification

Run checks for every component affected by a change:

```sh
tools/ci/check-no-sensitive-files.sh
tools/ci/check-vendored-core.sh
node tools/ci/check-compatibility-manifest.mjs
(cd packages/relay-core/ts && npm ci && npm test)
(cd packages/relay-core/python && python3 -m pytest -q)
(cd integrations/openclaw && npm ci && npm test)
```

For Hermes, install the development dependencies and point `PYTHONPATH` to a Hermes source checkout:

```sh
cd integrations/hermes
python3 -m pip install -e '.[dev]'
PYTHONPATH=/path/to/hermes-agent python3 -m pytest -q
```

For iOS changes, run the `AgentDeck` scheme’s tests in Xcode or use:

```sh
cd apps/ios
xcodebuild test \
  -project AgentDeck.xcodeproj \
  -scheme AgentDeck \
  -skipPackagePluginValidation \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO
```

Choose an installed simulator name if `iPhone 17` is unavailable.

## Pull requests

- Explain the user-visible or protocol behavior being changed.
- Keep credentials and private infrastructure out of code, fixtures, logs, and screenshots.
- Include tests or explain why a change cannot be tested automatically.
- Update public documentation when behavior, architecture, setup, or compatibility changes.
- Do not use `pull_request_target` to execute contribution code.
