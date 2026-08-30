# CI and Releases

AgentDeck uses secretless GitHub-hosted CI for routine verification and Xcode Cloud for signed distribution.

## GitHub Actions

### Linux CI

`.github/workflows/ci.yml` runs on pull requests and `main`:

- repository safety and compatibility-manifest checks;
- vendored transport drift checks;
- relay-core TypeScript and Python tests;
- OpenClaw tests against the committed dependency version;
- Hermes tests against the commit in `compatibility.json`.

### iOS CI

`.github/workflows/ios.yml` runs unsigned builds and XCTest on a GitHub-hosted macOS runner.

### Upstream canary

`.github/workflows/upstream-canary.yml` runs daily against the current OpenClaw package and the Hermes default branch. A failure opens or updates a GitHub issue. The canary reports compatibility drift but does not modify code or deploy anything.

### Release-candidate validation

`.github/workflows/release-candidate.yml` is manually dispatched. It starts a disposable MinIO service, validates the selected platform integration, and runs unsigned iOS tests against the temporary S3-compatible endpoint. Test results and MinIO diagnostics are uploaded as workflow artifacts.

## Security boundaries

GitHub workflows use read-only repository permissions by default. Pull-request code receives no production credentials, Apple signing material, App Store Connect keys, model-provider keys, or persistent infrastructure access.

Workflows that execute contribution code use `pull_request`, never `pull_request_target`.

## Dependencies

- Lockfiles define the required pull-request baseline.
- Dependabot proposes GitHub Actions, npm, pip, and SwiftPM updates.
- Related AWS S3 JavaScript packages are grouped so their Smithy types remain aligned.
- The scheduled canary tests newer platform versions without changing lockfiles.

Dependency updates are merged only after the relevant checks pass.

## Distribution

Xcode Cloud owns signing and distribution. GitHub Actions does not store Apple credentials or produce signed applications.

The release sequence is:

1. Merge a commit with all required GitHub checks passing.
2. Confirm upstream canaries are green or that known failures are understood.
3. Run release-candidate validation for OpenClaw and Hermes.
4. Create an `ios-v*` tag.
5. Let Xcode Cloud archive and distribute the build to an internal TestFlight group.
6. Validate discovery, messaging, streaming, reactions, approvals, persistence, and attachments.
7. Submit the selected build to App Review manually.

Signed distribution remains a deliberate release action; dependency and canary workflows cannot publish an app.
