# Maintenance Automation

## Goal

Keep ClawChat compatible with current OpenClaw and Hermes releases without placing personal infrastructure or production credentials in the maintenance path. Automated repairs are proposed as pull requests and never deploy directly.

## Environment boundaries

### GitHub-hosted CI

GitHub Actions is the routine compatibility laboratory. It uses only committed source, public upstream repositories, disposable MinIO credentials, and unsigned simulator builds.

It must never receive:

- Apple signing certificates or App Store Connect credentials
- personal, staging, or production R2 credentials
- SSH access to the personal Ubuntu host
- production model-provider credentials

### Xcode Cloud

Xcode Cloud is the intended signing and distribution boundary. It should use automatic signing and publish release candidates to internal TestFlight. GitHub Actions does not produce a signed application.

### Personal Ubuntu staging

The personal Ubuntu machine is reserved for long-lived personal platforms, explicit release staging, and interactive development. It is not a GitHub runner, a nightly test target, or an automatic deployment destination.

Personal, staging, and development instances must use separate directories, state, and R2 buckets or credentials.

## Implemented workflows

### `.github/workflows/ci.yml`

Runs on pull requests and `main`:

- rejects tracked credential-bearing and machine-local files;
- checks TypeScript and Python vendored transport drift;
- validates the relay v3 schema and fixtures through the relay-core suites;
- builds and tests the OpenClaw integration against its committed dependency lock;
- runs the Hermes adapter against the known-good Hermes revision recorded in the workflow.

All jobs use GitHub-hosted Ubuntu and require no secrets.

### `.github/workflows/ios.yml`

Runs unsigned Xcode builds and XCTest on a GitHub-hosted macOS simulator when iOS or relay-contract paths change. XCTest covers v3 decoding, persistence across database reopen, Keychain/UserDefaults separation, and deterministic relay behavior.

### `.github/workflows/upstream-canary.yml`

Runs daily against `openclaw@latest` and the current Hermes default branch. A failure creates or updates one GitHub issue with links to the failing run. Canary failures provide early warning but do not rewrite lockfiles or deploy code.

### `.github/workflows/release-candidate.yml`

Runs only through manual dispatch. Each platform gets a separate macOS matrix job that:

1. starts native disposable MinIO;
2. builds/tests current OpenClaw or Hermes compatibility;
3. runs unsigned iOS XCTest against that real S3-compatible endpoint;
4. uploads `.xcresult` and MinIO diagnostics.

This proves that the iOS AWS client and the selected platform remain viable on one release runner. It does not replace the final personal app-to-platform staging check because the current automated scenario does not drive a complete agent turn through the app UI.

## Pull-request security policy

- Set default workflow permissions to read-only.
- Use `pull_request`, not `pull_request_target`, for code execution.
- Do not expose secrets to fork pull requests or Dependabot jobs.
- Protect `main` and require Linux CI plus relevant iOS CI.
- Require maintainer review for `.github/workflows/`, relay schemas, Xcode project settings, and security policy changes.
- Enable GitHub secret scanning, push protection, CodeQL, and Dependabot before making the repository public.

## Dependency policy

- Committed lockfiles define the required PR baseline.
- Scheduled canaries deliberately install current upstream versions without changing lockfiles.
- Dependabot may open dependency PRs for GitHub Actions, npm, pip, and SwiftPM.
- Start with human-reviewed merges. Auto-merge only narrow patch updates after the workflow has proved reliable.

## Automated repair loop

1. A scheduled canary opens or updates the upstream-compatibility issue.
2. A coding agent may read the repository and failure artifacts and propose a bounded repair branch.
3. The repair PR runs the same secretless CI as every external contribution.
4. Branch protection and CODEOWNERS require normal review before merge.
5. Distribution or personal staging remains a separate explicit action.

The repair agent does not need Apple, R2, model-provider, or Ubuntu credentials.

## Release flow

1. Required PR checks pass against committed dependencies.
2. The latest OpenClaw and Hermes canary is green or its failure has been understood.
3. The manual release-candidate matrix passes with disposable MinIO.
4. Xcode Cloud creates an automatically signed internal TestFlight build.
5. The candidate is tested personally against isolated staging R2 and staging OpenClaw/Hermes instances.
6. The App Store release is submitted manually.
7. Personal platform instances are upgraded independently when desired.

The personal staging checklist should cover discovery, send/receive, restart persistence, streaming, reactions, approvals, and representative attachments.

## Current trust boundary

The app stores R2 secret material in Keychain and non-secret connection metadata in UserDefaults. Relay messages are not cryptographically signed, so R2 credentials and bucket policy remain the trust boundary: any principal with object-write permission can forge a peer message. Use separate buckets and least-privilege credentials for personal, staging, and development environments.
