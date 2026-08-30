# ClawChat

ClawChat is an iOS client for agent platforms connected through the relay v3 object-storage protocol. The repository contains the app, the executable relay contract, and native integrations for OpenClaw and Hermes.

## Repository layout

- `apps/ios/` — SwiftUI iOS app and XCTest suite
- `packages/relay-core/` — relay v3 schema, fixtures, and shared TypeScript/Python transport references
- `integrations/openclaw/` — OpenClaw channel plugin
- `integrations/hermes/` — Hermes adapter
- `docs/` — maintained architecture and workflow documentation

## Development

The normal checks are intentionally credential-free:

```sh
tools/ci/check-vendored-core.sh
(cd packages/relay-core/ts && npm ci && npm test)
(cd packages/relay-core/python && python -m pytest -q)
(cd integrations/openclaw && npm ci && npm test)
(
  cd integrations/hermes
  PYTHONPATH=/path/to/hermes-agent python -m pytest -q
)
```

Hermes compatibility tests intentionally import the real upstream platform registry. GitHub Actions checks out the tested revision automatically; local runs must point `PYTHONPATH` at a Hermes source checkout.

Run iOS builds and XCTest on macOS with Xcode. See `docs/WORKING_CONVENTIONS.md` and `docs/MAINTENANCE_AUTOMATION.md` for the authoritative development and release workflow.

## Security

Never commit R2 credentials, Apple signing material, model-provider keys, local platform configuration, or SSH credentials. See `SECURITY.md` for reporting instructions and `config/examples/` for safe configuration templates when they are added.

## License

ClawChat is available under the MIT License. See `LICENSE`.
