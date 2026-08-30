# AgentDeck Relay for Hermes

This package adds relay v3 support to Hermes as a user plugin. It publishes Hermes identity and conversation metadata, receives AgentDeck messages from Cloudflare R2, and delivers Hermes responses through the same relay.

## Requirements

- A Hermes installation with user-plugin support
- Python 3.12 or later
- A Cloudflare R2 bucket and S3-compatible credentials

## Install

Install and enable the plugin through Hermes's supported plugin manager:

```sh
hermes plugins install dodid/AgentDeck/integrations/hermes --enable
uv pip install --python ~/.hermes/hermes-agent/venv/bin/python "boto3>=1.34.0"
hermes gateway restart
```

Hermes clones this monorepo subdirectory into `~/.hermes/plugins/r2-relay/`,
prompts for the required relay environment variables, and records the plugin so
`hermes plugins update r2-relay` and `hermes plugins remove r2-relay` work normally.
Hermes does not install third-party Python dependencies from a Git plugin, so the
second command installs the R2 SDK into the standard Hermes environment.

The plugin installer stores relay credentials in `~/.hermes/.env`. Do not put
credentials in `config.yaml` or this repository.

Python package managers can alternatively discover the integration through its
`hermes_agent.plugins` entry point. Install the package into the same Python
environment that runs Hermes, then run `hermes plugins enable r2-relay`.

See [docs/install.md](docs/install.md) for environment variables and troubleshooting.

The scripts in `scripts/` are limited to building, bootstrapping a development
environment, and editing local relay configuration. Plugin installation,
updates, enablement, and removal belong to Hermes.

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
