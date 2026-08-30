from pathlib import Path

from r2_relay_adapter.checkpoint_store import load_checkpoint, save_checkpoint


def test_checkpoint_round_trip(tmp_path):
    path = tmp_path / 'checkpoint.json'
    save_checkpoint(path, {'last_head_key': 'head-1', 'seen': ['a', 'b']})
    loaded = load_checkpoint(path)
    assert loaded['last_head_key'] == 'head-1'
    assert loaded['seen'] == ['a', 'b']


def test_checkpoint_missing_file_returns_defaults(tmp_path):
    path = tmp_path / 'missing.json'
    loaded = load_checkpoint(path)
    assert loaded['last_head_key'] is None
    assert loaded['seen'] == []


def test_checkpoint_missing_file_returns_fresh_default_state(tmp_path):
    path = tmp_path / 'missing.json'
    first = load_checkpoint(path)
    first['seen'].append('mutated')

    second = load_checkpoint(path)

    assert second['seen'] == []
