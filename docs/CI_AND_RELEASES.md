# CI and Releases

AgentDeck uses secretless GitHub-hosted CI for routine verification and Xcode Cloud for signed distribution.

## GitHub Actions

### Linux CI

`.github/workflows/ci.yml` runs on pull requests and `main`:

- repository safety and compatibility-manifest checks;
- vendored transport drift checks;
- relay-core TypeScript and Python tests;
- OpenClaw tests against the committed dependency version, followed by packaged fresh-install, upgrade, uninstall, and reinstall checks;
- Hermes tests against the commit in `compatibility.json`, followed by the same packaged lifecycle checks in an isolated Hermes home.

### iOS CI

`.github/workflows/ios.yml` runs unsigned builds and XCTest serially on a GitHub-hosted macOS runner. It then installs the built app into a clean simulator, reinstalls it over the existing container to prove upgrade persistence, and uninstalls/reinstalls it to prove a clean bootstrap.

### Upstream canary

`.github/workflows/upstream-canary.yml` runs daily against the current OpenClaw package and the Hermes default branch. Each lane exercises a real packaged installation and a deterministic relay round trip through disposable MinIO. A failure opens or updates a GitHub issue. When both lanes pass, the scheduled run may update the tested revisions on a review-only compatibility pull request; it cannot merge or deploy the change.

### Release-candidate validation

`.github/workflows/release-candidate.yml` is manually dispatched. It starts a disposable MinIO service, validates the selected installed platform integration, runs the iOS contract suite against the platform-produced relay objects, and checks simulator install/upgrade behavior. Test results and redacted diagnostics are uploaded as workflow artifacts.

### Optional model-backed E2E

`.github/workflows/model-e2e.yml` runs twice weekly and on demand. If the repository Actions secret `OPENROUTER_API_KEY` exists, it sends text and attachment turns through the latest OpenClaw runtime and validates the Hermes relay adapter plus a real Hermes model turn. Set the repository Actions variable (preferred) or secret `OPENROUTER_MODEL` to an OpenRouter model identifier such as `openai/gpt-5.2-chat` or `openrouter/openai/gpt-5.2-chat`. The OpenClaw lane adds the `openrouter/` provider prefix when absent, while the Hermes lane removes it when present. A configured API key without a model is an error. If the API-key secret is absent, these optional jobs report a skip without weakening deterministic required checks.

## Security boundaries

GitHub workflows use read-only repository permissions by default. Pull-request code receives no production credentials, Apple signing material, App Store Connect keys, model-provider keys, or persistent infrastructure access.

Workflows that execute contribution code use `pull_request`, never `pull_request_target`. The scheduled compatibility updater has narrowly scoped write permission and only creates or refreshes a pull request after both upstream canaries pass.

## Dependencies

- Lockfiles define the required pull-request baseline.
- Dependabot proposes GitHub Actions, npm, pip, and SwiftPM updates.
- Related AWS S3 JavaScript packages are grouped so their Smithy types remain aligned.
- The scheduled canary tests newer platform versions and proposes reviewed lockfile and compatibility updates only after those tests pass.

Dependency updates are merged only after the relevant checks pass.

## Distribution

Xcode Cloud owns iOS signing and distribution. GitHub Actions publishes the
platform packages to their official registries; it does not store Apple signing
material.

The release sequence is:

1. Merge a commit with all required GitHub checks passing.
2. Confirm upstream canaries are green or that known failures are understood.
3. Run release-candidate validation for OpenClaw and Hermes.
4. Create a `plugins-v*` tag to publish the OpenClaw and Hermes packages.
5. Verify installation from ClawHub and PyPI in clean environments.
6. Create an `ios-v*` tag and let Xcode Cloud archive and distribute the app to TestFlight.
7. Validate discovery, messaging, streaming, reactions, approvals, persistence, and attachments.
8. Submit the selected iOS build to App Review manually.

End users install the OpenClaw integration from ClawHub and the Hermes integration
from PyPI. GitHub remains the source and CI host, not an end-user installation
endpoint. Signed iOS distribution remains a deliberate release action.

### Release credentials

The `release` environment used by `.github/workflows/plugin-release.yml` must
provide `NPM_TOKEN` and `CLAWHUB_TOKEN`. Configure PyPI trusted publishing for
this repository and workflow so the PyPI job uses GitHub's OIDC token and needs
no PyPI secret. Protect the `release` environment with required approval.

The first ClawHub publication and its trusted-publisher configuration are manual
registry setup. After that, a `plugins-v*` tag runs validation, publishes the npm
and ClawHub OpenClaw artifacts, and publishes the Hermes wheel and source
distribution to PyPI.
