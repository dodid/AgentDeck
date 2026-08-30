# ClawChat

A SwiftUI agent client for connecting to OpenClaw and Hermes through the relay v3 protocol on Cloudflare R2.

This directory is the iOS application inside the ClawChat monorepo. It contains no signing credentials or user-specific Xcode state.

## What it is

ClawChat is an iPhone-first client that lets a user:
- connect to a relay configuration backed by Cloudflare R2
- discover OpenClaw and Hermes gateway sessions
- read chat transcripts
- send replies from the app
- use a guided onboarding flow for setup
- customize the reading experience with chat style, font, and appearance settings

## Architecture

- Domain: core models, repository contracts, use cases
- Data: persistence and repository implementations
- Services: R2 relay transport, sync, config parsing
- Features: screen-specific SwiftUI views and view models
- UI: reusable theme, navigation, and components

## Opening the project

Requirements:
- Xcode 16+
- iOS SDK with SwiftUI support

Open:

```bash
open ClawChat.xcodeproj
```

Then build and run the `ClawChat` app target in Xcode.

## Configuration model

The app expects the user to provide:
- R2 endpoint
- bucket name
- access key ID
- secret access key

Those values are entered through onboarding or settings and used for relay discovery plus message transport.
