from gateway.platform_registry import PlatformEntry

from r2_relay_adapter.hermes_plugin import register


def test_registration_arguments_match_current_hermes_platform_entry():
    captured = {}

    class Context:
        def register_platform(self, **kwargs):
            captured.update(kwargs)

    register(Context())

    entry = PlatformEntry(source="plugin", plugin_name="r2-relay-adapter", **captured)
    assert entry.name == "r2_relay"
    assert entry.standalone_sender_fn is not None
