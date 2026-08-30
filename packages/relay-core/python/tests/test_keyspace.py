from r2_relay_core.keyspace import MAX_MS, RelayKeyspace, extract_timestamp_from_key


def test_pad_rev_ts_matches_expected_width_and_reverse_order():
    keyspace = RelayKeyspace(id_factory=lambda: "unused")

    padded = keyspace.pad_rev_ts(123)

    assert len(padded) == 13
    assert padded == "9999999999876"
    assert int(padded) == MAX_MS - 123


def test_make_msg_key_uses_current_wire_layout():
    keyspace = RelayKeyspace(id_factory=lambda: "deadbeef")

    key = keyspace.make_msg_key("peer-1", now_ms=123)

    assert key == "msg/peer-1/9999999999876-deadbeef.json"
    assert keyspace.makeMsgKey("peer-1", nowMs=123) == key


def test_make_att_key_sanitizes_message_and_name():
    keyspace = RelayKeyspace()

    key = keyspace.make_att_key("peer-1", "msg:/id", 3, "hello world.png", now_ms=123)

    assert key == "att/peer-1/9999999999876-msgid-03-helloworld.png"


def test_make_identity_and_head_keys_match_contract():
    keyspace = RelayKeyspace()

    assert keyspace.make_head_key("peer-1") == "head/peer-1.json"
    assert keyspace.make_identity_key("peer-1") == "identity/peer-1.json"
    assert keyspace.makeIdentifyKey("peer-1") == "identity/peer-1.json"


def test_make_att_key_strips_non_ascii_like_contract():
    keyspace = RelayKeyspace()

    key = keyspace.make_att_key("peer-1", "消息-id", 1, "über.png", now_ms=123)

    assert key == "att/peer-1/9999999999876--id-01-ber.png"


def test_extract_timestamp_from_key_round_trips_reverse_timestamp():
    key = "msg/peer-1/9999999999876-deadbeef.json"

    assert extract_timestamp_from_key(key) == 123
    assert extract_timestamp_from_key("head/peer-1.json") is None
