# Install

Install AgentDeck's Hermes platform plugin from PyPI:

```bash
python -m pip install --upgrade r2-relay-adapter
hermes plugins enable r2-relay
hermes gateway restart
```

Install the package into the same Python environment that runs Hermes. The
package declares `boto3` and `PyYAML` as runtime dependencies and exposes the
`r2-relay` Hermes entry point.

Minimum required R2 relay credentials in `~/.hermes/.env`:

```dotenv
R2_RELAY_ENDPOINT=...
R2_RELAY_BUCKET=...
R2_RELAY_ACCESS_KEY_ID=...
R2_RELAY_SECRET_ACCESS_KEY=...
```

Everything else is optional at the env level and will use defaults or derived values when omitted:
- `R2_RELAY_DISPLAY_NAME` defaults from `R2_RELAY_SERVER_ID`
- `R2_RELAY_SERVER_ID` defaults from the host name
- `R2_RELAY_DISCOVERY_CONVERSATION_ID` defaults to `main`
- `R2_RELAY_OVERSIZE_ATTACHMENT_BEHAVIOR` defaults to `reject`
- `R2_RELAY_POLL_INTERVAL_MS` defaults to `3000` and is clamped to `2000`–`60000`
- `R2_RELAY_BACKOFF_MAX_MS` defaults to `40000`

For a local AgentDeck checkout used in development, you can run the legacy
configuration wizard directly:

```bash
./scripts/config-wizard.sh
```

The official plugin installer prompts for the four required values above.
Advanced relay settings can be added to `~/.hermes/.env` when you need to
override derived/default behavior.

For live debugging after install, inspect the Hermes gateway log:

```bash
tail -f ~/.hermes/logs/gateway.log
```

Useful relay adapter log lines include:
- `published relay identity peer=... discovery_conversation_id=...`
- `started inbox polling task ...`
- `dispatching inbound relay message key=... from=... route=... thread_id=...`
- `inbox chain broken self_id=... missing_key=...`
- `sending relay message target_peer=... conversation_id=...`
- `r2 get_object missing key=...`
