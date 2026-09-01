# AgentDeck Relay for Hermes

This package adds relay v3 support to Hermes as a user plugin. It publishes Hermes identity and conversation metadata, receives AgentDeck messages from Cloudflare R2, and delivers Hermes responses through the same relay.

AgentDeck is fully open source under the MIT License. Build the iOS app for free
from the [AgentDeck repository](https://github.com/dodid/AgentDeck), or install
the signed public app from the App Store as a paid app by searching for
**AgentDeck**.

## Why this exists

- **No ports open** — keep the Hermes server behind its firewall instead of
  exposing a direct mobile endpoint.
- **You own your data** — relay objects live in your Cloudflare R2 bucket.
- **Native Hermes integration** — use Hermes gateway, cron, and platform flows
  while AgentDeck provides the mobile chat experience.
- **One client for two platforms** — use the same iOS app with Hermes or
  OpenClaw.

## Requirements

- A Hermes installation with user-plugin support
- Python 3.12 or later
- A Cloudflare R2 bucket and S3-compatible credentials

## Install the plugin

Install the released package from PyPI into the same Python environment that
runs Hermes:

```sh
python -m pip install --upgrade r2-relay-adapter
hermes plugins enable r2-relay
hermes gateway restart
```

The package exposes the `r2-relay` Hermes entry point and installs its runtime
dependencies automatically. Hermes keeps the plugin opt-in; installing the
package does not enable it until you run `hermes plugins enable r2-relay`.

## Configure Hermes

Set the required values in `~/.hermes/.env`:

```dotenv
R2_RELAY_ENDPOINT=...
R2_RELAY_BUCKET=...
R2_RELAY_ACCESS_KEY_ID=...
R2_RELAY_SECRET_ACCESS_KEY=...
```

Optional values include `R2_RELAY_SERVER_ID`, `R2_RELAY_HOME_CHANNEL`, and
`R2_RELAY_ALLOWED_USERS`. See [docs/install.md](docs/install.md) for the full
configuration list. Keep credentials in the environment file, not in
`config.yaml` or the repository.

## Install AgentDeck on iOS

Install AgentDeck from the App Store by searching for **AgentDeck**, or build it
for free using the [iOS build instructions](../../apps/ios/README.md). Enter the
same R2 connection details in AgentDeck that you configured for Hermes.

## Cron delivery

Set `R2_RELAY_HOME_CHANNEL` to a relay target when Hermes cron jobs should send
messages to AgentDeck. A target can be a peer ID or the provider-specific form:

```text
peer=<peer>,session=<thread-or-session-id>
```

Keep the target stable and unique when multiple Hermes gateways share one R2
bucket.

## Uninstall the plugin

Disable the platform, remove the package, and restart the gateway:

```sh
hermes plugins disable r2-relay
python -m pip uninstall r2-relay-adapter
hermes gateway restart
```

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

## Support and issues

Report bugs, feature requests, and installation problems in the
[AgentDeck GitHub Issues](https://github.com/dodid/AgentDeck/issues). Include
the Hermes version and redacted logs; never include R2 credentials or private
relay data.

## License

MIT License. See [LICENSE](../../LICENSE).
