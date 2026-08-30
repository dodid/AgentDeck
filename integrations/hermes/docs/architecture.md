# Architecture

This package preserves the existing ClawChat/OpenClaw R2 relay wire contract
while adapting it to Hermes' BasePlatformAdapter model.

Configuration policy:
- R2 connection secrets live in `.env`
- Hermes auto-enables the plugin from env via `env_enablement_fn`; secret values live in `~/.hermes/.env`
