# Finish setup

Hermes installs plugin source but does not install third-party Python dependencies.
Install the R2 SDK into the standard Hermes environment, then restart the gateway:

```bash
uv pip install --python ~/.hermes/hermes-agent/venv/bin/python "boto3>=1.34.0"
hermes gateway restart
```

The plugin installer prompts for the required `R2_RELAY_*` values. You can also
edit `~/.hermes/.env` later and restart the gateway.
