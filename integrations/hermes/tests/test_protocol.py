from r2_relay_adapter.protocol import R2RelayProtocol


def test_pad_rev_ts_matches_expected_width_and_reverse_order():
    proto = R2RelayProtocol(bucket='demo')
    padded = proto.pad_rev_ts(123)
    assert len(padded) == 13
    assert padded == '9999999999876'


def test_make_msg_key_uses_current_wire_layout():
    proto = R2RelayProtocol(bucket='demo')
    key = proto.make_msg_key('peer-1', now_ms=123, suffix='deadbeef')
    assert key == 'msg/peer-1/9999999999876-deadbeef.json'


def test_make_att_key_sanitizes_message_and_name():
    proto = R2RelayProtocol(bucket='demo')
    key = proto.make_att_key('peer-1', 'msg:/id', 3, 'hello world.png', now_ms=123)
    assert key == 'att/peer-1/9999999999876-msgid-03-helloworld.png'


def test_make_identity_and_head_keys_match_contract():
    proto = R2RelayProtocol(bucket='demo')
    assert proto.make_head_key('peer-1') == 'head/peer-1.json'
    assert proto.make_identity_key('peer-1') == 'identity/peer-1.json'


def test_make_att_key_strips_non_ascii_like_typescript_contract():
    proto = R2RelayProtocol(bucket='demo')
    key = proto.make_att_key('peer-1', '消息-id', 1, 'über.png', now_ms=123)
    assert key == 'att/peer-1/9999999999876--id-01-ber.png'
