# AgentDeck for iOS

AgentDeck is an iPhone-first SwiftUI client for OpenClaw and Hermes through the relay v3 protocol.

AgentDeck is fully open source under the MIT License. Build and run it for free
from this repository, or install the signed public release as a paid app from
the App Store. To install the public release, search for **AgentDeck** in the
App Store.

## Why this exists

- **No ports open:** the agent server can stay behind its firewall.
- **Your data stays yours:** relay data remains in your Cloudflare R2 bucket.
- **One mobile client:** use the same app with either OpenClaw or Hermes.
- **Fully open source:** inspect, build, and modify the app under the MIT License.

## Requirements

- Xcode with the iOS 18 SDK or later
- A Cloudflare R2 bucket and S3-compatible credentials
- An OpenClaw or Hermes relay integration configured for the same bucket

## Run the app

Open the project:

```sh
open AgentDeck.xcodeproj
```

Select the `AgentDeck` scheme and an iOS simulator or device. Signing is unnecessary for simulator builds; device builds require your own Apple development team.

For a release installation, use the App Store. For a free self-built
installation, use Xcode and the project above.

The onboarding flow requests:

- R2 endpoint
- bucket name
- access key ID
- secret access key

Secret values are stored in Keychain. Non-secret connection metadata and app preferences are stored separately.

## Source layout

- `AgentDeck/App/` — application bootstrap and dependency composition
- `AgentDeck/Domain/` — models and repository contracts
- `AgentDeck/Data/` — persistence and repository implementations
- `AgentDeck/Services/` — relay transport, sync, billing, and device services
- `AgentDeck/Features/` — SwiftUI screens and view models
- `AgentDeck/UI/` — shared navigation and theme components
- `AgentDeckTests/` — unit, persistence, and relay-contract tests

## Support

Report issues and feature requests in the
[AgentDeck GitHub Issues](https://github.com/dodid/AgentDeck/issues).
