# Automated Confidence Matrix

AgentDeck uses layered tests so a green release gate proves both deterministic behavior and compatibility with current platform releases.

| Capability | Pull request | Upstream canary | Release candidate |
| --- | --- | --- | --- |
| Relay v3 schema and fixtures | TypeScript and Python contract tests | Same tests against latest integrations | Required |
| Ordering, CAS, checkpoints, retention | Shared-core unit tests | Installed integration tests | Required |
| Identity and discovery | iOS and adapter component tests | Installed gateway publishes identity | iOS discovers real gateway |
| Text, streaming, reactions, approvals | App orchestration and adapter component tests | Deterministic runtime round trip | iOS-to-platform round trip |
| Attachments | Metadata, persistence, upload/download component tests | Runtime upload/download | Bidirectional app round trip |
| Fresh plugin install | Packaged artifact lifecycle test | Latest platform lifecycle test | Required |
| Plugin upgrade | Previous-package fixture to current package | Previous compatible platform/plugin to candidate | Required |
| Uninstall/reinstall | Packaged artifact lifecycle test | Latest platform | Diagnostic gate |
| Fresh iOS install | XCTest bootstrap plus simulator install smoke | Current Xcode | Clean simulator run |
| iOS upgrade and persistence | Named migration baseline and reopen tests | Current Xcode | Simulator reinstall preserves app data |
| Real model response | Not required | Optional credentialed job | Optional pre-release staging signal |

## Gate semantics

- Pull-request jobs are pinned, credential-free, and deterministic.
- Daily canaries install integrations into current OpenClaw and Hermes rather than only importing their APIs.
- Release-candidate validation uses disposable object storage and requires each app/platform lane to exchange canonical relay objects.
- A real model response is an additional integration signal. It cannot be a deterministic correctness dependency because provider availability and model output are external variables.
- Passing canaries may propose compatibility-manifest updates. Generated source repairs always require review.

## Required lifecycle assertions

Every platform lifecycle harness must prove:

1. The distributable package installs into a clean platform home.
2. The platform discovers and enables the plugin.
3. Configuration validation and identity publication succeed.
4. Installing the candidate over a previous package preserves configuration and checkpoint state.
5. The upgraded gateway restarts and exchanges relay messages.
6. Uninstall removes plugin registration; reinstall returns the integration to a healthy state.

The iOS lifecycle lane must prove clean bootstrap, persisted database reopening, the named database migration baseline, and simulator reinstall without container data loss. Every future schema change must add an upgrade fixture from the preceding released schema before it can be treated as covered.

The iOS component suite also covers onboarding and returning-install routing, connection replacement and local-data cleanup, discovery refresh recovery, composer send/failure behavior, backfill pagination, persistence, and relay protocol handling. Photo/speech system pickers, App Store distribution processing, and provider model quality remain platform- or provider-owned behavior; they are smoke signals rather than deterministic release assertions.
