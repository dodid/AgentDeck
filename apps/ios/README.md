# AgentDeck for iOS

AgentDeck is an iPhone-first SwiftUI client for OpenClaw and Hermes through the relay v3 protocol.

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
