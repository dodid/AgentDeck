# AgentDeck

AgentDeck is an open-source iOS client for OpenClaw and Hermes. It exchanges messages through a relay v3 object-storage protocol, allowing an agent server to remain behind its firewall while the user keeps relay data in their own Cloudflare R2 bucket.

## Features

- Discover agents and conversations published by OpenClaw or Hermes.
- Send and receive text, streaming responses, reactions, approvals, and attachments.
- Store R2 credentials in the iOS Keychain.
- Keep local chat history in an on-device SQLite database.
- Connect without exposing the agent server directly to the internet.

## Repository layout

- `apps/ios/` — AgentDeck SwiftUI app and XCTest suite
- `packages/relay-core/` — executable relay v3 schema, fixtures, and shared transport references
- `integrations/openclaw/` — OpenClaw channel plugin
- `integrations/hermes/` — Hermes adapter
- `docs/` — architecture, CI, and release documentation

## Getting started

To run the iOS app, open `apps/ios/AgentDeck.xcodeproj` in Xcode and select the `AgentDeck` scheme. The onboarding flow asks for an R2 endpoint, bucket, access key ID, and secret access key.

Platform setup instructions are available in:

- [OpenClaw integration](integrations/openclaw/README.md)
- [Hermes integration](integrations/hermes/README.md)

## Development

The normal checks are credential-free:

```sh
tools/ci/check-vendored-core.sh
(cd packages/relay-core/ts && npm ci && npm test)
(cd packages/relay-core/python && python3 -m pytest -q)
(cd integrations/openclaw && npm ci && npm test)
```

Hermes compatibility tests require a Hermes source checkout. GitHub Actions checks out the tested revision automatically; local runs set `PYTHONPATH` to a Hermes checkout.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution and verification guidance.

## Security

Never commit R2 credentials, Apple signing material, model-provider keys, local platform configuration, or SSH credentials. See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## License

AgentDeck is available under the [MIT License](LICENSE).
