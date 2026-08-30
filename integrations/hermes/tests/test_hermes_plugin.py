from pathlib import Path
import tomllib
from types import SimpleNamespace

import yaml

from gateway.platform_registry import PlatformEntry

from r2_relay_adapter.hermes_plugin import register


def test_registration_arguments_match_current_hermes_platform_entry(monkeypatch):
    captured = {}

    class Context:
        def register_platform(self, **kwargs):
            captured.update(kwargs)

    register(Context())

    entry = PlatformEntry(source="plugin", plugin_name="r2-relay-adapter", **captured)
    assert entry.name == "r2_relay"
    assert entry.standalone_sender_fn is not None
    assert entry.check_fn() is True
    for name in entry.required_env:
        monkeypatch.delenv(name, raising=False)
    assert entry.validate_config(SimpleNamespace(extra={})) is False


def test_official_plugin_directory_and_python_entry_point_are_publishable():
    integration_root = Path(__file__).resolve().parents[1]
    manifest = yaml.safe_load((integration_root / "plugin.yaml").read_text(encoding="utf-8"))

    assert manifest["name"] == "r2-relay"
    assert manifest["kind"] == "platform"
    assert (integration_root / "__init__.py").is_file()
    assert (integration_root / "adapter.py").is_file()

    project = tomllib.loads((integration_root / "pyproject.toml").read_text(encoding="utf-8"))
    registered = project["project"]["entry-points"]["hermes_agent.plugins"]
    assert registered["r2-relay"] == "r2_relay_adapter.hermes_plugin"
