from __future__ import annotations

import os
import tempfile


# Hermes resolves media-cache paths while importing its platform base module.
os.environ.setdefault("HERMES_HOME", tempfile.mkdtemp(prefix="r2-relay-hermes-tests-"))


def pytest_sessionstart(session):
    del session
    from gateway.platform_registry import PlatformEntry, platform_registry

    if not platform_registry.is_registered("r2_relay"):
        platform_registry.register(
            PlatformEntry(
                name="r2_relay",
                label="R2 Relay",
                adapter_factory=lambda config: config,
                check_fn=lambda: True,
            )
        )
