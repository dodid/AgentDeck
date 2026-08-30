# AgentDeck Relay for Hermes

This package adds relay v3 support to Hermes as a user plugin. It publishes Hermes identity and conversation metadata, receives AgentDeck messages from Cloudflare R2, and delivers Hermes responses through the same relay.

## Requirements

- A Hermes installation with user-plugin support
- Python 3.12 or later
- A Cloudflare R2 bucket and S3-compatible credentials

## Install

From this directory:

```sh
./scripts/build.sh
./scripts/deploy-into-hermes.sh ~/.hermes/hermes-agent
./scripts/config-wizard.sh
```

The deploy script installs the package into the Hermes environment, copies the plugin to `~/.hermes/plugins/r2-relay/`, and enables `r2-relay` in `~/.hermes/config.yaml`.

The wizard stores relay credentials in `~/.hermes/.env`. Do not put credentials in `config.yaml` or this repository.

See [docs/install.md](docs/install.md) for environment variables and troubleshooting.

## Development

```sh
./scripts/bootstrap-dev.sh
PYTHONPATH=/path/to/hermes-agent python3 -m pytest -q
```

The tests import Hermes’s real platform registry, so `PYTHONPATH` must reference a compatible Hermes source checkout. The tested revision is recorded in the repository’s `compatibility.json`.

## Logs

After restarting Hermes, relay diagnostics are written to the Hermes gateway log:

```sh
tail -f ~/.hermes/logs/gateway.log
```
