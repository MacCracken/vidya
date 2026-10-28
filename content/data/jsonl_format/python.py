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
    """Returns escaped bytes, or None if the worst-case expansion exceeds
    dst_cap. Worst case is 6x: RFC 8259 §7 requires EVERY control byte
    U+0000..U+001F to be escaped, and those without a short form become
    \\u00XX. Leaving them raw (only escaping \\n \\t \\r) emits invalid JSON."""
    if len(src) * 6 > dst_cap:
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
        elif c < 0x20:   # other control bytes: \u00XX
            out.extend(b"\\u%04x" % c)
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
            elif n == 0x75 and i + 5 < len(src):  # \u00XX (control bytes)
                out.append(int(src[i + 2:i + 6], 16)); i += 6
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

    # Test 6: control bytes without a short escape (NUL, backspace, 0x1F)
    s6 = bytes([0x61, 0x00, 0x08, 0x1F])
    esc6 = json_escape(s6, 64)
    assert esc6 == b"a\\u0000\\u0008\\u001f", f"\\u00XX escapes, got {esc6!r}"
    assert json_unescape(esc6) == s6, "\\u00XX round-trip"

    print("jsonl_format: 10/10 ok")


main()
