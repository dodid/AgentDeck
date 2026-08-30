from __future__ import annotations

from typing import Any

from r2_relay_adapter.service import R2RelayService
from r2_relay_adapter.protocol import R2RelayProtocol


def build_relay_service(
    config: Any,
    client: Any,
    checkpoint_store: Any,
) -> R2RelayService:
    return R2RelayService(
        client=client,
        relay=R2RelayProtocol(bucket=config.bucket),
        peer_id=config.server_id,
        checkpoint_store=checkpoint_store,
    )
