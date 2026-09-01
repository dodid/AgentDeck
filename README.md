# AgentDeck — OpenClaw and Hermes on iPhone

AgentDeck is a fully open-source iOS client for [OpenClaw](https://openclaw.ai/)
and [Hermes Agent](https://hermes-agent.nousresearch.com/). It exchanges messages
through a relay v3 object-storage protocol, allowing an agent server to remain
behind its firewall while you keep relay data in your own Cloudflare R2 bucket.

The project includes the iOS app and the platform plugins that connect OpenClaw
and Hermes to the same relay. The complete source is available under the MIT
License.

## Why this exists

- **No ports open:** keep the agent server behind its firewall.
- **Your data stays yours:** relay objects live in your Cloudflare R2 bucket.
- **One app for two platforms:** use the same iOS client with OpenClaw or Hermes.
- **Open and inspectable:** the app, protocol, and integrations are available to
  review, build, and modify under the MIT License.

## Get AgentDeck

Choose the installation path that fits you:

- **Build it for free:** clone this repository, open `apps/ios/AgentDeck.xcodeproj`
  in Xcode, and run the app on a simulator. You can also deploy to your own
  device with your Apple development team.
- **Install from the App Store:** download the signed public release of AgentDeck
  directly from the App Store as a paid app. Search for **AgentDeck** in the App
  Store.

The App Store release and the source-built app use the same relay protocol and
features. The onboarding flow asks for an R2 endpoint, bucket, access key ID, and
secret access key.

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

## Connect an agent

Install one of the platform integrations on the machine running your agent:

- [OpenClaw plugin](integrations/openclaw/README.md) — install from ClawHub.
- [Hermes plugin](integrations/hermes/README.md) — install from PyPI.

Then configure the plugin and AgentDeck with the same Cloudflare R2 endpoint,
bucket, access key ID, and secret access key.

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

## Support and issues

Report bugs, request features, and discuss installation problems in the
[AgentDeck GitHub Issues](https://github.com/dodid/AgentDeck/issues). When
reporting a relay problem, include the platform integration, app version, and
redacted logs; never include R2 credentials or private relay data.

## Security

Never commit R2 credentials, Apple signing material, model-provider keys, local platform configuration, or SSH credentials. See [SECURITY.md](SECURITY.md) for vulnerability reporting.

## License

AgentDeck is available under the [MIT License](LICENSE).
