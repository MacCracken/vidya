# Vidya — Serialization in Python
#
# Varint (LEB128) + length-prefix framing + stream parser + DoS guards.

MAX_VARINT_BYTES = 10
MAX_MSG_SIZE = 1024


def encode_varint(value):
    out = bytearray()
    while value >= 128:
        out.append((value & 0x7F) | 0x80)
        value >>= 7
    out.append(value & 0x7F)
    return bytes(out)


def decode_varint(buf):
    """Returns (value, bytes_consumed) on success, None on failure."""
    value = 0
    shift = 0
    for i in range(MAX_VARINT_BYTES):
        if i >= len(buf):
            return None
        b = buf[i]
        value += (b & 0x7F) << shift
        if b & 0x80 == 0:
            return (value, i + 1)
        shift += 7
    return None


def encode_frame(payload):
    return encode_varint(len(payload)) + payload


def decode_frame(buf, max_msg=MAX_MSG_SIZE):
    """Returns (payload, bytes_consumed) on success, None on failure."""
    r = decode_varint(buf)
    if r is None:
        return None
    length, hdr = r
    if length > max_msg:
        return None
    total = hdr + length
    if total > len(buf):
        return None
    return (bytes(buf[hdr:total]), total)


def main():
    # Varint sizes
    assert encode_varint(0) == b"\x00"
    assert encode_varint(127) == b"\x7F"
    assert encode_varint(128) == b"\x80\x01"
    assert len(encode_varint(16383)) == 2
    assert len(encode_varint(16384)) == 3

    # Round-trip
    sample = 1234567890
    enc = encode_varint(sample)
    dec, dn = decode_varint(enc)
    assert dec == sample
    assert dn == len(enc)

    # Overflow guard
    bomb = bytes([0xFF] * 11)
    assert decode_varint(bomb) is None

    # Frame round-trip
    payload = b"hello, world"
    frame = encode_frame(payload)
    assert len(frame) == 13
    assert frame[0] == 12
    r = decode_frame(frame)
    assert r is not None
    decoded, consumed = r
    assert consumed == 13
    assert decoded == payload

    # Stream of 3 frames
    stream = encode_frame(b"AAA") + encode_frame(b"BBBB") + encode_frame(b"CCCCC")
    pos = 0
    msg_count = 0
    while pos < len(stream):
        r = decode_frame(stream[pos:])
        if r is None:
            break
        _, c = r
        msg_count += 1
        pos += c
    assert msg_count == 3

    # Truncated frame
    trunc = bytes([100, 0x42, 0x43, 0x44, 0x45, 0x46])
    assert decode_frame(trunc) is None

    # Oversize length rejected
    over = encode_varint(9999)
    assert decode_frame(over) is None

    print("serialization: 19/19 ok")


main()
