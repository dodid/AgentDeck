# Install

Install AgentDeck's Hermes platform plugin through Hermes:

```bash
hermes plugins install dodid/AgentDeck/integrations/hermes --enable
uv pip install --python ~/.hermes/hermes-agent/venv/bin/python "boto3>=1.34.0"
hermes gateway restart
```

The first command uses Hermes's supported monorepo-subdirectory plugin install,
prompts for required values, and records the source for future `plugins update`
and `plugins remove` operations. Hermes Git plugins do not install Python
dependencies, so `boto3` must be installed into the same environment as Hermes.

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
- `R2_RELAY_POLL_INTERVAL_MS` defaults to `5000`
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
