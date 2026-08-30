# Install

Minimum required R2 relay credentials in `~/.hermes/.env`:

```dotenv
R2_RELAY_ENDPOINT=...
R2_RELAY_BUCKET=...
R2_RELAY_ACCESS_KEY_ID=...
R2_RELAY_SECRET_ACCESS_KEY=...
R2_RELAY_SERVER_ID=...
```

Everything else is optional at the env level and will use defaults or derived values when omitted:
- `R2_RELAY_DISPLAY_NAME` defaults from `R2_RELAY_SERVER_ID`
- `R2_RELAY_DISCOVERY_SESSION_KEY` defaults to `main`
- `R2_RELAY_OVERSIZE_ATTACHMENT_BEHAVIOR` defaults to `reject`
- `R2_RELAY_POLL_INTERVAL_MS` defaults to `5000`
- `R2_RELAY_BACKOFF_MAX_MS` defaults to `40000`

Then deploy into Hermes:

```bash
./scripts/deploy-into-hermes.sh ~/.hermes/hermes-agent
```

You can also run the wizard directly:

```bash
./scripts/config-wizard.sh
```

By default the wizard only prompts for the five required values above. It can optionally prompt for advanced relay settings if you want to override derived/default behavior.

Deployment installs the Python package into the Hermes venv, copies a standard
Hermes user plugin into `~/.hermes/plugins/r2-relay/`, and adds `r2-relay` to
`plugins.enabled` in `~/.hermes/config.yaml`.

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
