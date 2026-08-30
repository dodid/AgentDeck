# AGENTS.md

## Project boundaries

- Follow MVVM in `apps/ios/AgentDeck/`: views render state, view models orchestrate features, and services/repositories own transport and persistence.
- Keep OpenClaw-specific behavior in `integrations/openclaw/` and Hermes-specific behavior in `integrations/hermes/`.
- Treat `packages/relay-core/spec/relay-contract-v3.schema.json` and its fixtures as the executable relay contract.

## Protocol changes

Coordinate relay changes across the schema, fixtures, TypeScript and Python reference transports, both platform integrations, and `apps/ios/AgentDeck/Services/Relay/RelayMessageModels.swift`.

Run `tools/ci/check-vendored-core.sh` after shared transport changes.

## Security

- Never commit production credentials, signing material, model-provider keys, SSH credentials, or private relay data.
- Pull-request and scheduled tests must remain credential-free.
- GitHub Actions uses disposable MinIO credentials and unsigned simulator builds; signing belongs to Xcode Cloud.

## Verification

- Linux CI covers schema, TypeScript, Python, OpenClaw, and Hermes behavior.
- macOS CI covers Xcode builds, XCTest, and simulator behavior.
- Upstream-latest checks belong in the scheduled canary workflow, not deterministic pull-request jobs.
