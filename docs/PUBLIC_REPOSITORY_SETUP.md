# Public Repository Setup

This is the one-time publication and hosted-CI checklist for ClawChat. The safe sequence is:

1. revoke old credentials and inspect the clean local repository;
2. push it to a **private** GitHub repository first;
3. make all hosted checks pass and configure repository protections;
4. connect Xcode Cloud without exporting Apple credentials;
5. change the repository visibility to public only after the checks below pass.

The private-first step is a review gate, not a permanent architecture requirement. Routine CI remains secretless after publication.

## 1. Record the values you will use

Choose these values before starting. Examples in this document use placeholders; do not copy the angle brackets into commands.

| Value | Example | Notes |
| --- | --- | --- |
| GitHub owner | `<OWNER>` | Your GitHub user or organization. |
| Repository name | `clawchat` | The examples assume this name. |
| Maintainer login | `<MAINTAINER>` | Must be a valid GitHub login with repository access. |
| Apple team | `<APPLE_TEAM>` | The team enrolled in the Apple Developer Program. |
| Bundle ID | `com.candiapps.ClawChat` | Verify it matches the app target and App Store Connect record. |
| Internal TestFlight group | `ClawChat Internal` | Create this before enabling distribution. |

Before publication, replace every `@dodid` entry in `.github/CODEOWNERS` if that is not the correct maintainer login. An invalid owner silently defeats the intended ownership policy.

## 2. Revoke credentials before inspecting files

A credential that has appeared in any local configuration, copied terminal output, chat, log, or previous repository must be treated as exposed even if Git ignored the file.

For the existing R2 environment:

1. Open the Cloudflare dashboard using your normal browser session.
2. Create a replacement access key with access limited to the required bucket and operations.
3. Update the private runtime configuration that uses the old key.
4. Verify the replacement works.
5. Revoke the old key.
6. Remove old values from local shell history, saved logs, and ignored configuration copies where practical.

Do not paste either key into an issue, commit, GitHub Actions variable, this guide, or a command whose output will be retained. Revocation is the important action: deleting a leaked string from Git history does not make the credential safe again.

Apple signing assets do not need to be exported for this repository. Xcode Cloud manages signing through the Apple Developer account connection.

## 3. Inspect the local repository

Run these commands from the new monorepo, not from the shared parent directory:

```sh
cd /Users/ww/workspace/clawchat/monorepo
git status --short
git remote -v
git log --oneline --decorate --all
find . -type d -name .git -print
tools/ci/check-no-sensitive-files.sh
tools/ci/check-vendored-core.sh
node tools/ci/check-compatibility-manifest.mjs
```

Expected results:

- `git status --short` prints nothing;
- `git remote -v` prints nothing before the first publication;
- the log contains only the intentionally clean monorepo history;
- `find` prints only `./.git`;
- all three repository checks exit successfully.

Inspect commit identity before publishing. Every author and committer email in Git history becomes public metadata:

```sh
git log --all --format='%h %an <%ae> | committed by %cn <%ce>'
```

If you do not want a personal address published, enable **Keep my email addresses private** in GitHub email settings and use the GitHub-provided no-reply address for this repository. Set it before making more commits:

```sh
git config user.name '<PUBLIC_NAME>'
git config user.email '<GITHUB_NOREPLY_ADDRESS>'
```

The current repository was intentionally created with a short, unpublished history. If an unpublished commit has the wrong identity, amend it before pushing:

```sh
git commit --amend --reset-author --no-edit
```

For more than one affected commit, do not improvise a history rewrite. Create another clean import with the desired public identity or use a reviewed history-rewrite procedure, then scan the result again.

Review exactly what Git will publish:

```sh
git ls-files
git grep -nEI '(BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY|AKIA[0-9A-Z]{16})' -- . ':!docs/PUBLIC_REPOSITORY_SETUP.md'
```

The grep should produce no output. It is a narrow sanity check, not a complete secret scanner.

Install and run an independent history and working-tree scanner:

```sh
brew install gitleaks
gitleaks git . --redact --no-banner
gitleaks dir . --redact --no-banner
```

Investigate every finding. Do not add a baseline merely to make a real credential finding disappear. If a secret was committed, revoke it first, then rebuild or rewrite the unpublished repository history and scan again.

Keep the previous component repositories private. Do not merge their histories into the public monorepo, because old commits can contain files that are absent from the clean import.

## 4. Run the local checks

Run the cross-platform checks on the clean commit:

```sh
(cd packages/relay-core/ts && npm ci && npm test)
(cd packages/relay-core/python && python -m pip install -e '.[dev]' && python -m pytest -q)
(cd integrations/openclaw && npm ci && npm test)
```

Hermes tests need a local Hermes checkout. Point `PYTHONPATH` at that checkout and keep Hermes state in a disposable directory:

```sh
(
  cd integrations/hermes
  HERMES_HOME="$(mktemp -d)" \
  PYTHONPATH=/absolute/path/to/hermes-agent \
  python -m pytest -q
)
```

On macOS, also run the iOS test command documented in `docs/WORKING_CONVENTIONS.md`. If Swift package resolution cannot complete locally, stop before publication or rely on the first private GitHub-hosted iOS run and inspect its complete result bundle.

## 5. Create the GitHub repository privately

### GitHub CLI path

Authenticate and confirm that `gh` is using the intended account:

```sh
gh auth status
```

From the monorepo directory, create and push the repository:

```sh
gh repo create <OWNER>/clawchat --private --source=. --remote=origin --push
```

This command creates external state and uploads the complete local Git history. Re-run the inspections above before executing it.

### GitHub website path

Alternatively:

1. On GitHub, select **New repository**.
2. Choose the intended owner and enter `clawchat`.
3. Select **Private** initially.
4. Do **not** initialize the repository with a README, `.gitignore`, or license; those files already exist locally.
5. Create the repository.
6. Run the commands GitHub shows for “push an existing repository,” normally:

   ```sh
   git remote add origin git@github.com:<OWNER>/clawchat.git
   git push -u origin main
   ```

Confirm the remote after pushing:

```sh
git remote -v
git ls-remote --heads origin main
```

## 6. Validate the first GitHub Actions runs

Open **Actions** in the private repository. The initial push should run both **Linux CI** and **iOS CI**. Open every job rather than relying only on the workflow summary.

The checks intended for `main` protection are:

- `repository-safety`
- `relay-typescript`
- `relay-python`
- `openclaw-pinned`
- `hermes-pinned`
- `iOS build and XCTest`

GitHub only offers status checks that it has seen recently when configuring a ruleset, so wait for this first run before creating the ruleset. The iOS workflow deliberately has no path filter: a required workflow that is skipped due to path filtering can leave a pull request permanently waiting for a check.

If the Actions tab says workflows are disabled, enable them for this repository. Do not approve or run unfamiliar fork code during this private bootstrap.

## 7. Configure GitHub Actions permissions

Go to **Settings → Actions → General**:

1. Under **Actions permissions**, allow GitHub-authored and verified marketplace actions, or use the organization’s stricter allow-list if one already exists. The current workflows use actions maintained by GitHub.
2. Under **Workflow permissions**, select **Read repository contents and packages permissions**.
3. Clear **Allow GitHub Actions to create and approve pull requests**.
4. Under fork pull-request workflow approval, choose **Require approval for all external contributors**.
5. Save.

Some fork controls appear only after the repository is public. If GitHub does not show that setting while the repository is private, make it the first setting you configure immediately after changing visibility.

The scheduled canary has a narrowly scoped job-level `issues: write` permission so it can report an upstream failure. No workflow needs repository secrets.

Never change a workflow to run untrusted pull-request code under `pull_request_target`. That event has access to the base repository context and is the wrong trust boundary for these tests.

## 8. Enable repository security features

Go to **Settings → Security → Code security and analysis** (the labels can vary slightly between personal and organization repositories) and enable:

1. Dependabot alerts;
2. Dependabot security updates;
3. secret scanning;
4. push protection for secret scanning;
5. CodeQL default setup for every detected supported language;
6. private vulnerability reporting after the repository becomes public.

The repository already contains Dependabot version-update configuration. The host settings above are still required for alerts, security updates, and secret protection.

Review **Security → Code scanning** after CodeQL’s first run. A failing security scan must be investigated; do not dismiss a finding solely to make the branch green.

## 9. Configure `CODEOWNERS`

Edit `.github/CODEOWNERS` before enabling enforcement and replace `@dodid` if needed. Commit that change through the private repository.

The file marks these trust boundaries:

- Actions workflows;
- the relay protocol specification;
- the Xcode project;
- the iOS relay implementation;
- the security policy.

`CODEOWNERS` documents ownership by itself, but it enforces review only when the branch ruleset requires code-owner review. A solo maintainer cannot approve their own pull request, so choose one of these modes deliberately:

- **Solo mode:** require pull requests and checks, but require zero approvals and do not require code-owner review. `CODEOWNERS` remains documentation and automatically requests review if another maintainer is later added.
- **Team mode:** require at least one approval, require code-owner review, and dismiss stale approvals when protected files change.

Start in solo mode unless a second trusted maintainer is actually available.

## 10. Protect `main` with a ruleset

Go to **Settings → Rules → Rulesets → New ruleset → New branch ruleset**:

1. Name it `Protect main`.
2. Set enforcement to **Active**.
3. Target the default branch, or include only `main`.
4. Do not add GitHub Actions, Dependabot, or external contributors to the bypass list. If you add an administrator emergency bypass, choose **For pull requests only** and use it only for recovery.
5. Enable **Restrict deletions**.
6. Enable **Block force pushes**.
7. Enable **Require a pull request before merging**.
8. In solo mode, set required approvals to `0`. In team mode, use at least `1` and require code-owner review.
9. Enable **Require status checks to pass**.
10. Select the six checks listed in section 6.
11. Enable **Require branches to be up to date before merging** if the extra rerun is acceptable. This is safer; disabling it reduces CI use.
12. Save the ruleset.

Do not require the scheduled **Upstream canary** or manual **Release candidate validation** workflows for ordinary pull requests. They do not run on the pull-request event and would block every merge.

After saving, verify protection with a harmless branch and pull request. Direct pushes to `main` should be rejected and the pull request should not merge until all six checks pass.

## 11. Configure Xcode Cloud without GitHub secrets

Prerequisites:

- active Apple Developer Program membership;
- a valid App ID and App Store Connect app record for the bundle ID;
- automatic signing enabled for the ClawChat target;
- an Apple role allowed to create the app and Xcode Cloud workflow;
- GitHub admin permission for the repository, or organization-owner help for the initial connection.

On the Mac:

1. Pull the private GitHub repository and open `apps/ios/ClawChat.xcodeproj` in the current Xcode release.
2. Select the ClawChat target, open **Signing & Capabilities**, select `<APPLE_TEAM>`, and confirm **Automatically manage signing** is enabled.
3. Confirm the shared `ClawChat` scheme builds, tests, and has the Archive action enabled under **Product → Scheme → Edit Scheme**.
4. Open the Report navigator, select the **Cloud** tab, and click **Get Started**.
5. Select the ClawChat product and verify that Xcode chose the `ClawChat` scheme.
6. Grant Xcode Cloud access to only this GitHub repository when GitHub offers repository selection.
7. Associate or create the App Store Connect app record.
8. Start the first build from `main`.

Keep the first workflow simple and name it `Main Verification`:

- start on changes to `main`;
- optionally start on pull requests targeting `main` if you want Xcode Cloud results in addition to GitHub-hosted iOS CI;
- use Build and Test actions;
- test on one current iPhone simulator initially;
- do not distribute builds;
- do not add secrets or custom scripts.

GitHub-hosted iOS CI already tests every pull request, so running `Main Verification` only after merges to `main` is the lowest-maintenance choice.

After the first successful Xcode Cloud build, create a second workflow in Xcode (**Cloud → Manage Workflows**) or App Store Connect (**app → Xcode Cloud → Manage Workflows**) named `Internal TestFlight`:

- start when a Git tag matching `ios-v*` is created;
- perform a clean Archive action using the ClawChat scheme;
- distribute only to the `ClawChat Internal` TestFlight group;
- enable **Restrict Editing** in the workflow’s General settings;
- do not configure automatic App Store submission.

No Apple certificate, private key, provisioning profile, Apple ID password, or App Store Connect API key belongs in GitHub Actions. If a future Xcode Cloud custom script needs a token, store it as an Xcode Cloud secret environment variable with redaction enabled, not in GitHub or the repository.

## 12. Exercise the maintenance workflows

From **Actions**, manually run **Upstream canary** once. It tests current OpenClaw and current Hermes using disposable hosted runners. On failure it opens or updates a single repository issue.

Then run **Release candidate validation** with `platform = all`. It uses:

- a temporary MinIO process and per-run bucket on the GitHub macOS runner;
- public upstream source/package downloads;
- unsigned simulator tests;
- no personal R2, Apple, SSH, or Ubuntu-machine credentials.

Only create a release tag after all required checks and the release-candidate workflow pass:

```sh
git switch main
git pull --ff-only
git tag -a ios-v0.1.0 -m 'ClawChat 0.1.0 internal candidate'
git push origin ios-v0.1.0
```

That tag starts the restricted Xcode Cloud workflow and sends the signed build to the internal TestFlight group. Test it personally against the isolated staging deployment before manually submitting a build for App Review.

## 13. Make the repository public

Before changing visibility, verify all of the following:

- old R2 and other exposed credentials are revoked;
- the local and remote histories pass both Gitleaks scans;
- all six required checks are green;
- Actions default permissions are read-only;
- fork runs require approval from all external contributors;
- secret scanning and push protection are enabled or will become enabled with public visibility;
- the `main` ruleset is active and tested;
- `CODEOWNERS`, `SECURITY.md`, `LICENSE`, and public contact details are correct;
- issues, discussions, sponsorship links, and repository description disclose nothing private;
- no personal server hostname, SSH key, R2 endpoint, account ID, or bucket name is present.

Then go to **Settings → General → Danger Zone → Change repository visibility**, choose **Public**, type the confirmation GitHub requests, and confirm.

Immediately after publication, repeat:

```sh
gitleaks git . --redact --no-banner
gh repo view <OWNER>/clawchat --web
```

Open the public repository in a logged-out/private browser window. Inspect the files, Actions logs, artifacts, issues, commit author email, profile links, and release metadata exactly as an external visitor sees them.

## 14. Keep personal staging separate

Do not register the personal Ubuntu machine as a self-hosted GitHub runner. A public-repository pull request must never be able to schedule code on that machine.

Use the Ubuntu host only for:

- your personal OpenClaw and Hermes instances;
- an isolated staging deployment for a candidate you explicitly selected;
- interactive development that you start manually.

Keep personal, staging, and development R2 credentials in local configuration outside this repository. Promotion to staging remains a local, explicit operation after hosted checks pass; it is not part of pull-request CI.

## 15. Failure and recovery notes

### A required check is missing

Run its workflow once on the default branch, then return to the ruleset. Confirm that the selected check name exactly matches the job name. Do not add scheduled or manual-only jobs as required pull-request checks.

### A pull request waits forever for iOS CI

Confirm `.github/workflows/ios.yml` still runs on every `pull_request` without a path filter and that the required check is `iOS build and XCTest`.

### A fork workflow needs approval

Review the diff first, especially changes to `.github/workflows/`, build scripts, dependency manifests, and tests. Approval authorizes untrusted code to consume hosted runner time; it does not grant repository secrets under the current design.

### Xcode Cloud cannot access GitHub

Confirm the Apple GitHub app is allowed to access this repository. For an organization-owned repository, an organization owner may need to complete the initial authorization.

### Xcode Cloud cannot identify the app

Verify the target has an explicit bundle identifier, the scheme is shared and archivable, the signing team is selected, and the matching App Store Connect record exists.

### A secret is discovered after publication

1. Revoke it immediately at the provider.
2. Remove it from current files.
3. Rewrite history if the value was committed, understanding that existing clones and caches may retain it.
4. force-push the sanitized history only as a deliberate security incident response using the ruleset’s emergency process;
5. review Actions logs and artifacts, then rotate any related credentials;
6. document the incident privately and determine how the scanner missed it.

Never assume that deleting a file or commit makes a published credential usable again.

## Authoritative references

- [Adding locally hosted code to GitHub](https://docs.github.com/en/migrations/importing-source-code/using-the-command-line-to-import-source-code/adding-locally-hosted-code-to-github)
- [Managing GitHub Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository)
- [Creating repository rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository)
- [Troubleshooting required status checks](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/troubleshooting-rules)
- [GitHub repository security quickstart](https://docs.github.com/en/code-security/getting-started/quickstart-for-securing-your-repository)
- [Gitleaks command reference](https://github.com/gitleaks/gitleaks)
- [Configuring the first Xcode Cloud workflow](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow)
- [Connecting Xcode Cloud to GitHub](https://developer.apple.com/documentation/xcode/connecting-xcode-cloud-to-github)
- [Creating an Xcode Cloud distribution workflow](https://developer.apple.com/documentation/Xcode/Creating-a-workflow-that-builds-your-app-for-distribution)
