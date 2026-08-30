from r2_relay_adapter.config import resolve_r2_relay_env_config


def test_resolve_r2_relay_env_config_reads_env_only(monkeypatch):
    monkeypatch.delenv('R2_RELAY_DISPLAY_NAME', raising=False)
    monkeypatch.delenv('R2_RELAY_DISCOVERY_CONVERSATION_ID', raising=False)
    monkeypatch.delenv('R2_RELAY_DISCOVERY_CONVERSATION_TITLE', raising=False)
    monkeypatch.delenv('R2_RELAY_DISCOVERY_THREAD_ID', raising=False)
    monkeypatch.delenv('R2_RELAY_MODELS', raising=False)
    monkeypatch.delenv('R2_RELAY_DEFAULT_MODEL', raising=False)
    monkeypatch.delenv('R2_RELAY_OVERSIZE_ATTACHMENT_BEHAVIOR', raising=False)
    monkeypatch.delenv('R2_RELAY_MAX_INBOUND_IMAGE_BYTES', raising=False)
    monkeypatch.delenv('R2_RELAY_MAX_INBOUND_VIDEO_BYTES', raising=False)
    monkeypatch.delenv('R2_RELAY_MAX_INBOUND_AUDIO_BYTES', raising=False)
    monkeypatch.delenv('R2_RELAY_MAX_INBOUND_FILE_BYTES', raising=False)
    monkeypatch.delenv('R2_RELAY_POLL_INTERVAL_MS', raising=False)
    monkeypatch.delenv('R2_RELAY_BACKOFF_MAX_MS', raising=False)
    monkeypatch.setenv('R2_RELAY_ENDPOINT', 'https://example.r2.cloudflarestorage.com')
    monkeypatch.setenv('R2_RELAY_BUCKET', 'relay-bucket')
    monkeypatch.setenv('R2_RELAY_ACCESS_KEY_ID', 'abc')
    monkeypatch.setenv('R2_RELAY_SECRET_ACCESS_KEY', 'secret')
    monkeypatch.setenv('R2_RELAY_SERVER_ID', 'server one')

    cfg = resolve_r2_relay_env_config({})

    assert cfg.endpoint == 'https://example.r2.cloudflarestorage.com'
    assert cfg.bucket == 'relay-bucket'
    assert cfg.access_key_id == 'abc'
    assert cfg.secret_access_key == 'secret'
    assert cfg.server_id == 'server-one'
    assert cfg.display_name == 'Server One'
    assert cfg.discovery_conversation_id == 'main'
    assert cfg.discovery_conversation_title is None
    assert cfg.discovery_thread_id is None
    assert cfg.available_models == ()
    assert cfg.default_model is None
    assert cfg.poll_interval_ms == 5000
    assert cfg.backoff_max_ms == 40000
    assert cfg.config_file == ''
    assert cfg.force_path_style is True
    assert cfg.inbound_attachment_max_bytes is None
    assert cfg.oversize_attachment_behavior is None


def test_resolve_r2_relay_env_config_reads_optional_discovery_fields(monkeypatch):
    monkeypatch.setenv('R2_RELAY_DISPLAY_NAME', 'Demo Gateway')
    monkeypatch.setenv('R2_RELAY_DISCOVERY_CONVERSATION_ID', 'main')
    monkeypatch.setenv('R2_RELAY_DISCOVERY_CONVERSATION_TITLE', 'Primary Thread')
    monkeypatch.setenv('R2_RELAY_DISCOVERY_THREAD_ID', 'sess-42')
    monkeypatch.setenv(
        'R2_RELAY_MODELS',
        'openrouter/openai/gpt-5.4|GPT 5.4|openrouter,anthropic/claude-sonnet-4',
    )
    monkeypatch.setenv('R2_RELAY_DEFAULT_MODEL', 'openrouter/openai/gpt-5.4')
    monkeypatch.setenv('R2_RELAY_MAX_INBOUND_IMAGE_BYTES', '100')
    monkeypatch.setenv('R2_RELAY_MAX_INBOUND_VIDEO_BYTES', '200')
    monkeypatch.setenv('R2_RELAY_MAX_INBOUND_AUDIO_BYTES', '300')
    monkeypatch.setenv('R2_RELAY_MAX_INBOUND_FILE_BYTES', '400')
    monkeypatch.setenv('R2_RELAY_OVERSIZE_ATTACHMENT_BEHAVIOR', 'reject')

    cfg = resolve_r2_relay_env_config({})

    assert cfg.display_name == 'Demo Gateway'
    assert cfg.discovery_conversation_id == 'main'
    assert cfg.discovery_conversation_title == 'Primary Thread'
    assert cfg.discovery_thread_id == 'sess-42'
    assert cfg.available_models == (
        {
            'id': 'openrouter/openai/gpt-5.4',
            'label': 'GPT 5.4',
            'provider': 'openrouter',
        },
        {
            'id': 'anthropic/claude-sonnet-4',
            'label': None,
            'provider': 'anthropic',
        },
    )
    assert cfg.default_model == 'openrouter/openai/gpt-5.4'
    assert cfg.inbound_attachment_max_bytes == {
        'image': 100,
        'video': 200,
        'audio': 300,
        'file': 400,
    }
    assert cfg.oversize_attachment_behavior == 'reject'


def test_resolve_r2_relay_env_config_marks_missing_secret_values_unconfigured(monkeypatch):
    monkeypatch.delenv('R2_RELAY_ENDPOINT', raising=False)
    monkeypatch.delenv('R2_RELAY_BUCKET', raising=False)
    monkeypatch.delenv('R2_RELAY_ACCESS_KEY_ID', raising=False)
    monkeypatch.delenv('R2_RELAY_SECRET_ACCESS_KEY', raising=False)
    monkeypatch.delenv('R2_RELAY_SERVER_ID', raising=False)

    cfg = resolve_r2_relay_env_config({})

    assert cfg.configured is False
    assert cfg.endpoint == ''
    assert cfg.bucket == ''
    assert cfg.access_key_id == ''
    assert cfg.secret_access_key == ''
    assert cfg.server_id


def test_resolve_r2_relay_env_config_supports_force_path_style_override(monkeypatch):
    monkeypatch.setenv('R2_RELAY_FORCE_PATH_STYLE', 'false')

    cfg = resolve_r2_relay_env_config({})

    assert cfg.force_path_style is False


def test_boto3_client_kwargs_use_env_backed_r2_settings(monkeypatch):
    monkeypatch.setenv('R2_RELAY_ENDPOINT', 'https://example.r2.cloudflarestorage.com')
    monkeypatch.setenv('R2_RELAY_BUCKET', 'relay-bucket')
    monkeypatch.setenv('R2_RELAY_ACCESS_KEY_ID', 'abc')
    monkeypatch.setenv('R2_RELAY_SECRET_ACCESS_KEY', 'secret')
    monkeypatch.setenv('R2_RELAY_FORCE_PATH_STYLE', 'false')

    cfg = resolve_r2_relay_env_config({})
    kwargs = cfg.boto3_client_kwargs()

    assert kwargs['service_name'] == 's3'
    assert kwargs['endpoint_url'] == 'https://example.r2.cloudflarestorage.com'
    assert kwargs['aws_access_key_id'] == 'abc'
    assert kwargs['aws_secret_access_key'] == 'secret'
    assert kwargs['region_name'] == cfg.region
    assert kwargs['config'].s3['addressing_style'] == 'virtual'
