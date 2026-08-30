# Deployment

Use the deploy script to build/install the package and copy the Hermes platform
plugin files into the target checkout.

Current state:
- package installation is scripted
- Hermes integration is a standard user plugin under `~/.hermes/plugins/r2-relay`
- install also enables the plugin in `~/.hermes/config.yaml`
- `./scripts/config-wizard.sh` populates `~/.hermes/.env`
- only five env vars are required: endpoint, bucket, access key ID, secret access key, and server ID
- display name, discovery session key, poll timing, and oversize behavior derive or default automatically unless you opt into advanced wizard prompts

Live diagnostics:
- after deploy/restart, inspect `~/.hermes/logs/gateway.log`
- the adapter now emits structured logs from adapter/service/client layers
- the most useful lines for reply pickup debugging are:
  - `published relay identity peer=... discovery_conversation_id=...`
  - `started inbox polling task ...`
  - `collecting relay inbox self_id=... head_key=... last_seen_key=...`
  - `inbox chain broken self_id=... missing_key=...`
  - `dispatching inbound relay message key=... from=... route=... thread_id=...`
  - `sending relay message target_peer=... conversation_id=...`
  - `relay send CAS retry ...` / `relay send CAS success ...`
  - `r2 get_object missing key=...`
