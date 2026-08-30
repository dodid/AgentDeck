# r2-relay-adapter

Hermes platform adapter package for the ClawChat Cloudflare R2 relay. It is maintained in `integrations/hermes/` of the ClawChat monorepo.

Goals:
- preserve the existing ClawChat/OpenClaw relay wire contract
- implement Hermes gateway adapter logic in an external package
- provide install/deploy scripts for wiring the adapter into Hermes as a platform plugin
- keep relay secrets in `.env`, not `config.yaml`

Quick start:

```bash
./scripts/bootstrap-dev.sh
PYTHONPATH=/path/to/hermes-agent make test
./scripts/build.sh
./scripts/deploy-into-hermes.sh ~/.hermes/hermes-agent
```

Current status:
- protocol/config/checkpoint helpers are implemented and tested
- Hermes integration uses the documented user-plugin path under `~/.hermes/plugins/r2-relay/`
- relay secrets are still expected in `~/.hermes/.env`, not `config.yaml`
- only five env vars are required; other relay settings derive from those or use defaults

Debug logging:
- the adapter now emits structured logs from `r2_relay_adapter.adapter`, `r2_relay_adapter.service`, and `r2_relay_adapter.client`
- useful live diagnostics are written into the Hermes gateway log after deploy/restart
- especially useful lines to watch for:
  - `published relay identity peer=... discovery_conversation_id=...`
  - `started inbox polling task ...`
  - `collecting relay inbox self_id=... head_key=... last_seen_key=...`
  - `inbox chain broken self_id=... missing_key=...`
  - `dispatching inbound relay message key=... from=... route=... thread_id=...`
  - `sending relay message target_peer=... conversation_id=...`
  - `relay send CAS retry ...` / `relay send CAS success ...`
  - `r2 get_object missing key=...`

After deploying into Hermes, a simple way to inspect them is:

```bash
tail -f ~/.hermes/logs/gateway.log
```
