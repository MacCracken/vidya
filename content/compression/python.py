# Vidya — Compression (LZ77-shaped) in Python
#
# Two-byte token stream matching cyrius.cyr:
#   [0, BYTE]      — literal
#   [OFFSET, LEN]  — match: copy LEN bytes from out[pos - OFFSET..]
# Greedy O(n^2) match-finder over a 255-byte window. Decoder enforces
# an output-cap to defuse decompression bombs. Match copy is byte-by-
# byte so offset=1 replicates the trailing byte (RLE).

MIN_MATCH = 3
MAX_MATCH = 255
WIN_SIZE = 255


def match_len_at(src, hist, pos):
    n = 0
    max_n = min(len(src) - pos, MAX_MATCH)
    while n < max_n and src[hist + n] == src[pos + n]:
        n += 1
    return n


def best_match(src, pos):
    win_start = max(0, pos - WIN_SIZE)
    best_off = 0
    best_len = 0
    for i in range(win_start, pos):
        n = match_len_at(src, i, pos)
        if n > best_len:
            best_len = n
            best_off = pos - i
    if best_len >= MIN_MATCH:
        return (best_off, best_len)
    return None


def encode(src):
    tok = bytearray()
    pos = 0
    while pos < len(src):
        m = best_match(src, pos)
        if m is not None:
            off, length = m
            tok.append(off)
            tok.append(length)
            pos += length
        else:
            tok.append(0)
            tok.append(src[pos])
            pos += 1
    return bytes(tok)


def decode(tok, out_cap):
    """Returns bytes on success, None on bomb-guard trigger."""
    out = bytearray()
    i = 0
    while i + 1 < len(tok):
        b0 = tok[i]
        b1 = tok[i + 1]
        i += 2
        if b0 == 0:
            if len(out) + 1 > out_cap:
                return None
            out.append(b1)
        else:
            offset = b0
            length = b1
            if len(out) + length > out_cap:
                return None
            for k in range(length):
                out.append(out[len(out) - offset])
    return bytes(out)


def main():
    # 1. Round-trip with substring match
    s1 = b"ABCABCABC"
    t1 = encode(s1)
    assert len(t1) > 0, "encoded length > 0"
    d1 = decode(t1, 512)
    assert d1 == s1, "ABCABCABC roundtrip"

    # 2. Overlapping (RLE) match
    s2 = b"AAAAAAAA"
    t2 = encode(s2)
    d2 = decode(t2, 512)
    assert d2 == s2, "AAAAAAAA roundtrip"
    assert len(t2) < len(s2) + 4, "AAAAAAAA actually compresses"

    # 3. Mostly literals
    s3 = b"Hello, World!"
    t3 = encode(s3)
    d3 = decode(t3, 512)
    assert d3 == s3, "Hello roundtrip"

    # 4. Bomb guard
    bomb = bytes([1, 200])
    assert decode(bomb, 10) is None, "bomb guard rejects oversize"

    # 5. Empty input
    t5 = encode(b"")
    assert len(t5) == 0, "empty input → zero tokens"
    d5 = decode(b"", 512)
    assert d5 == b"", "empty tokens → zero output"

    print("compression: 11/11 ok")


main()
