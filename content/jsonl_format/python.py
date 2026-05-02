# Vidya — JSON Lines (JSONL) in Python
#
# In-memory JSONL primitives mirroring cyrius.cyr.

def append_record(buf, rec):
    buf.extend(rec)
    buf.append(0x0A)


def build_index(buf):
    offsets = []
    lengths = []
    start = 0
    for i, b in enumerate(buf):
        if b == 0x0A:
            offsets.append(start)
            lengths.append(i - start)
            start = i + 1
    if start < len(buf):
        offsets.append(start)
        lengths.append(len(buf) - start)
    return offsets, lengths


def json_escape(src, dst_cap):
    """Returns escaped bytes, or None if 2x expansion exceeds dst_cap."""
    if len(src) * 2 > dst_cap:
        return None
    out = bytearray()
    for c in src:
        if c == 0x22:    # "
            out.append(0x5C); out.append(0x22)
        elif c == 0x5C:  # \
            out.append(0x5C); out.append(0x5C)
        elif c == 0x0A:  # \n
            out.append(0x5C); out.append(0x6E)
        elif c == 0x09:  # \t
            out.append(0x5C); out.append(0x74)
        elif c == 0x0D:  # \r
            out.append(0x5C); out.append(0x72)
        else:
            out.append(c)
    return bytes(out)


def json_unescape(src):
    out = bytearray()
    i = 0
    while i < len(src):
        if src[i] == 0x5C and i + 1 < len(src):
            n = src[i + 1]
            if n == 0x22: out.append(0x22); i += 2
            elif n == 0x5C: out.append(0x5C); i += 2
            elif n == 0x6E: out.append(0x0A); i += 2
            elif n == 0x74: out.append(0x09); i += 2
            elif n == 0x72: out.append(0x0D); i += 2
            else: out.append(src[i]); i += 1
        else:
            out.append(src[i])
            i += 1
    return bytes(out)


def main():
    # Test 1: build, index, extract
    buf = bytearray()
    append_record(buf, b'{"id":1}')
    append_record(buf, b'{"id":2}')
    append_record(buf, b'{"id":3}')
    offs, lens = build_index(buf)
    assert len(offs) == 3, "3 records indexed"
    assert lens[2] == 8, "third record length 8"
    third = bytes(buf[offs[2]:offs[2] + lens[2]])
    assert third == b'{"id":3}', "third record bytes"

    # Test 2: no trailing newline
    buf2 = bytearray(buf)
    if buf2[-1] == 0x0A:
        buf2.pop()
    offs2, _ = build_index(buf2)
    assert len(offs2) == 3, "3 records indexed without trailing newline"

    # Test 3: escape
    s3 = bytes([0x73, 0x61, 0x79, 0x20, 0x22, 0x68, 0x69, 0x22,
                0x09, 0x0A, 0x0D, 0x5C])
    esc = json_escape(s3, 256)
    assert len(esc) == 18, f"escape produces 18 bytes, got {len(esc)}"

    # Test 4: bounds check
    s4 = bytes([0x22, 0x22, 0x22, 0x22])
    assert json_escape(s4, 4) is None, "escape refuses tight cap"

    # Test 5: roundtrip
    un = json_unescape(esc)
    assert len(un) == 12, f"unescape recovers 12, got {len(un)}"
    assert un == s3, "round-trip bytes match"

    print("jsonl_format: 8/8 ok")


main()
