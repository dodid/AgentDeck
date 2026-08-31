from __future__ import annotations

import asyncio
import os
from dataclasses import replace
from pathlib import Path

import pytest

from gateway.config import PlatformConfig

from r2_relay_adapter.adapter import R2RelayAdapter
from r2_relay_adapter.checkpoint_store import FileCheckpointStore
from r2_relay_adapter.client import R2RelayClient
from r2_relay_adapter.config import resolve_r2_relay_env_config
from r2_relay_adapter.service_factory import build_relay_service


def _live_config(monkeypatch):
    names = {
        "R2_RELAY_ENDPOINT": "AGENTDECK_TEST_R2_ENDPOINT",
        "R2_RELAY_BUCKET": "AGENTDECK_TEST_R2_BUCKET",
        "R2_RELAY_ACCESS_KEY_ID": "AGENTDECK_TEST_R2_ACCESS_KEY_ID",
        "R2_RELAY_SECRET_ACCESS_KEY": "AGENTDECK_TEST_R2_SECRET_ACCESS_KEY",
    }
    values = {}
    for relay_name, test_name in names.items():
        value = os.environ.get(test_name)
        if not value:
            pytest.skip("live MinIO integration is enabled only by maintenance workflows")
        values[relay_name] = value
        monkeypatch.setenv(relay_name, value)
    monkeypatch.setenv("R2_RELAY_SERVER_ID", "hermes-live")
    monkeypatch.setenv("R2_RELAY_POLL_INTERVAL_MS", "100")
    monkeypatch.setenv("R2_RELAY_BACKOFF_MAX_MS", "500")
    return resolve_r2_relay_env_config({})


@pytest.mark.asyncio
async def test_installed_hermes_runtime_round_trip_with_minio(monkeypatch, tmp_path: Path):
    server_config = _live_config(monkeypatch)
    server_client = R2RelayClient.from_env_config(server_config)
    try:
        server_client.s3.create_bucket(Bucket=server_config.bucket)
    except Exception as error:
        code = getattr(error, "response", {}).get("Error", {}).get("Code")
        if code not in {"BucketAlreadyExists", "BucketAlreadyOwnedByYou"}:
            raise
    existing = await server_client.list_prefix("")
    await server_client.delete_objects([item["Key"] for item in existing])

    client_peer = os.environ.get("AGENTDECK_TEST_CLIENT_PEER", "ios-live")
    phone_config = replace(server_config, server_id=client_peer, display_name="AgentDeck CI")
    phone_service = build_relay_service(
        config=phone_config,
        client=R2RelayClient.from_env_config(phone_config),
        checkpoint_store=FileCheckpointStore(tmp_path / "phone-checkpoint.json"),
    )
    adapter = R2RelayAdapter(
        PlatformConfig(enabled=True),
        checkpoint_store=FileCheckpointStore(tmp_path / "hermes-checkpoint.json"),
    )
    events = []
    received = asyncio.Event()

    async def handle(event):
        events.append(event)
        received.set()

    adapter.set_message_handler(handle)
    assert await adapter.connect() is True
    try:
        identity = await server_client.get_json_with_etag("identity/hermes-live.json")
        assert identity["body"]["protocol"] == {"name": "r2-relay", "version": 3}

        sent = await adapter.send(f"peer={client_peer},conversation=agent:main:main", "from Hermes")
        assert sent.success is True
        outbound = await phone_service.collect_inbox_messages(client_peer, None)
        assert outbound["messages"][-1]["message"]["content"]["text"] == "from Hermes"

        await phone_service.send_message(
            "hermes-live",
            {
                "route": {"agent_id": "main", "conversation_id": "agent:main:main"},
                "content": {"type": "text", "text": "from AgentDeck"},
            },
        )
        await asyncio.wait_for(received.wait(), timeout=10)
        assert events[-1].text == "from AgentDeck"
        assert events[-1].source.chat_id == f"peer={client_peer},conversation=agent:main:main"

        fixture = tmp_path / "round-trip.txt"
        fixture.write_text("attachment round trip", encoding="utf-8")
        attachment_result = await adapter.send_document(
            f"peer={client_peer},conversation=agent:main:main",
            str(fixture),
            caption="attachment",
        )
        assert attachment_result.success is True
        after_attachment = await phone_service.collect_inbox_messages(
            client_peer, outbound["head"]["head_key"]
        )
        attachment = after_attachment["messages"][-1]["message"]["content"]["attachments"][0]
        stored = await phone_service.store.get_attachment(attachment["key"])
        assert stored["Body"].read() == b"attachment round trip"

        assert (tmp_path / "hermes-checkpoint.json").exists()
    finally:
        await adapter.disconnect()
