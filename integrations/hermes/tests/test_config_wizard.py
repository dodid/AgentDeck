from __future__ import annotations

from pathlib import Path

from r2_relay_adapter.config_wizard import apply_r2_relay_settings, load_env_file


REQUIRED = {
    'R2_RELAY_ENDPOINT': 'https://example.r2.cloudflarestorage.com',
    'R2_RELAY_BUCKET': 'relay-bucket',
    'R2_RELAY_ACCESS_KEY_ID': 'access-key',
    'R2_RELAY_SECRET_ACCESS_KEY': 'secret-key',
    'R2_RELAY_SERVER_ID': 'server-one',
}


OPTIONAL = {
    'R2_RELAY_DISPLAY_NAME': 'Demo Gateway',
    'R2_RELAY_DISCOVERY_CONVERSATION_ID': 'main',
    'R2_RELAY_DISCOVERY_THREAD_ID': 'sess-42',
    'R2_RELAY_MAX_INBOUND_IMAGE_BYTES': '100',
    'R2_RELAY_MAX_INBOUND_VIDEO_BYTES': '200',
    'R2_RELAY_MAX_INBOUND_AUDIO_BYTES': '300',
    'R2_RELAY_MAX_INBOUND_FILE_BYTES': '400',
    'R2_RELAY_OVERSIZE_ATTACHMENT_BEHAVIOR': 'reject',
    'R2_RELAY_ALLOWED_USERS': 'peer-1,peer-2',
    'R2_RELAY_ALLOW_ALL_USERS': 'false',
    'R2_RELAY_POLL_INTERVAL_MS': '7000',
    'R2_RELAY_BACKOFF_MAX_MS': '45000',
}


def test_apply_r2_relay_settings_writes_env_and_home_channel(tmp_path: Path) -> None:
    hermes_home = tmp_path / '.hermes'
    hermes_home.mkdir()
    env_path = hermes_home / '.env'
    env_path.write_text('EXISTING=value\nR2_RELAY_BUCKET=old-bucket\n', encoding='utf-8')

    apply_r2_relay_settings(
        hermes_home=hermes_home,
        values={**REQUIRED, **OPTIONAL},
        home_channel='peer=demo,conversation=main',
    )

    env_values = load_env_file(env_path)
    assert env_values['EXISTING'] == 'value'
    for key, value in {**REQUIRED, **OPTIONAL}.items():
        assert env_values[key] == value
    assert env_values['R2_RELAY_HOME_CHANNEL'] == 'peer=demo,conversation=main'
    assert env_values['R2_RELAY_HOME_CHANNEL_NAME'] == 'R2 Relay Home'


def test_apply_r2_relay_settings_with_required_values_only_keeps_env_minimal(tmp_path: Path) -> None:
    hermes_home = tmp_path / '.hermes'
    hermes_home.mkdir()
    env_path = hermes_home / '.env'

    apply_r2_relay_settings(
        hermes_home=hermes_home,
        values=REQUIRED,
    )

    env_values = load_env_file(env_path)
    assert env_values == REQUIRED


def test_apply_r2_relay_settings_removes_blank_optional_values(tmp_path: Path) -> None:
    hermes_home = tmp_path / '.hermes'
    hermes_home.mkdir()
    env_path = hermes_home / '.env'
    env_path.write_text(
        '\n'.join(
            [
                'R2_RELAY_ENDPOINT=https://example.r2.cloudflarestorage.com',
                'R2_RELAY_BUCKET=relay-bucket',
                'R2_RELAY_ACCESS_KEY_ID=access-key',
                'R2_RELAY_SECRET_ACCESS_KEY=secret-key',
                'R2_RELAY_SERVER_ID=server-one',
                'R2_RELAY_DISPLAY_NAME=Old Name',
                'R2_RELAY_DISCOVERY_THREAD_ID=old-session',
                '',
            ]
        ),
        encoding='utf-8',
    )

    apply_r2_relay_settings(
        hermes_home=hermes_home,
        values={
            **REQUIRED,
            'R2_RELAY_DISPLAY_NAME': '',
            'R2_RELAY_DISCOVERY_THREAD_ID': None,
        },
    )

    env_values = load_env_file(env_path)
    assert env_values['R2_RELAY_ENDPOINT'] == REQUIRED['R2_RELAY_ENDPOINT']
    assert 'R2_RELAY_DISPLAY_NAME' not in env_values
    assert 'R2_RELAY_DISCOVERY_THREAD_ID' not in env_values


def test_apply_r2_relay_settings_clears_home_channel_values_when_omitted(tmp_path: Path) -> None:
    hermes_home = tmp_path / '.hermes'
    hermes_home.mkdir()
    env_path = hermes_home / '.env'
    env_path.write_text(
        'R2_RELAY_HOME_CHANNEL=peer=demo,session=main\n'
        'R2_RELAY_HOME_CHANNEL_NAME=Demo Home\n'
        'R2_RELAY_HOME_CHANNEL_THREAD_ID=thread-1\n',
        encoding='utf-8',
    )

    apply_r2_relay_settings(
        hermes_home=hermes_home,
        values=REQUIRED,
        home_channel=None,
    )

    env_values = load_env_file(env_path)
    assert 'R2_RELAY_HOME_CHANNEL' not in env_values
    assert 'R2_RELAY_HOME_CHANNEL_NAME' not in env_values
    assert 'R2_RELAY_HOME_CHANNEL_THREAD_ID' not in env_values
