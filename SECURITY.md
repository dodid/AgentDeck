# Security Policy

Please do not report vulnerabilities in public issues.

Use GitHub private vulnerability reporting for this repository. If it is unavailable, contact the maintainer through the address on the maintainer’s GitHub profile and include `AgentDeck security` in the subject.

Do not include live credentials, relay data, conversation content, or weaponized proof-of-concept material in public discussions.

## Credential handling

AgentDeck stores R2 secret material in the iOS Keychain. GitHub Actions uses only disposable test credentials and unsigned simulator builds. Apple signing is handled by Xcode Cloud.

If a credential is exposed, revoke or rotate it immediately. Removing it from a file or Git history does not make the credential safe to reuse.
