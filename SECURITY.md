# Security Policy

Please do not report vulnerabilities in public issues.

Use GitHub's private vulnerability reporting feature for this repository. If private reporting is unavailable, contact the maintainer through the email address listed on the maintainer's GitHub profile and include `ClawChat security` in the subject.

Do not include live credentials, personal relay data, conversation content, or exploitable proof-of-concept material in public discussions.

## Credential handling

The repository and its pull-request workflows are designed to operate without production credentials. Apple signing is handled outside GitHub Actions, and personal Ubuntu/R2 environments are not CI infrastructure.

If a credential is accidentally committed, revoke or rotate it immediately before attempting to remove it from Git history.
