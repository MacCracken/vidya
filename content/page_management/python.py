# Vidya — Page Management in Python
#
# Fixed-size 4KB pages, single file. Header at offset 0; page 0 reserved
# as null sentinel; data pages at PAGE_SZ + num * PAGE_SZ. Free list is a
# stack with `next` pointer at byte offset 8 of each freed page. Mirrors
# the cyrius reference's test surface exactly.

import os
import struct

PAGE_SZ = 4096
MAGIC = 0x50415452
H_PGCOUNT = 8
H_FREEHEAD = 16
FP_NEXT = 8


def page_offset(num):
    return PAGE_SZ + num * PAGE_SZ


def hdr_init():
    return {"page_count": 1, "freehead": 0}


def hdr_to_bytes(h):
    buf = bytearray(PAGE_SZ)
    buf[0:4] = struct.pack("<I", MAGIC)
    buf[H_PGCOUNT:H_PGCOUNT + 8] = struct.pack("<Q", h["page_count"])
    buf[H_FREEHEAD:H_FREEHEAD + 8] = struct.pack("<Q", h["freehead"])
    return bytes(buf)


def hdr_verify(buf):
    return struct.unpack_from("<I", buf, 0)[0] == MAGIC


def hdr_load(buf):
    return {
        "page_count": struct.unpack_from("<Q", buf, H_PGCOUNT)[0],
        "freehead": struct.unpack_from("<Q", buf, H_FREEHEAD)[0],
    }


def page_read(f, num):
    f.seek(page_offset(num))
    return f.read(PAGE_SZ)


def page_write(f, num, buf):
    f.seek(page_offset(num))
    f.write(buf)


def page_alloc(f, h):
    if h["freehead"] != 0:
        fh = h["freehead"]
        buf = page_read(f, fh)
        h["freehead"] = struct.unpack_from("<Q", buf, FP_NEXT)[0]
        return fh
    num = h["page_count"]
    h["page_count"] += 1
    page_write(f, num, b"\x00" * PAGE_SZ)
    return num


def page_free(f, h, num):
    buf = bytearray(PAGE_SZ)
    buf[FP_NEXT:FP_NEXT + 8] = struct.pack("<Q", h["freehead"])
    page_write(f, num, bytes(buf))
    h["freehead"] = num


def main():
    path = "/tmp/vidya_page_python.bin"
    try:
        os.remove(path)
    except FileNotFoundError:
        pass

    with open(path, "w+b") as f:
        h = hdr_init()
        f.write(hdr_to_bytes(h))

        # 1-2. header
        f.seek(0)
        hbuf = f.read(PAGE_SZ)
        assert hdr_verify(hbuf), "magic ok"
        loaded = hdr_load(hbuf)
        assert loaded["page_count"] == 1, "pgcount starts at 1"

        # 3-4. alloc
        p1 = page_alloc(f, h)
        assert p1 == 1, "first alloc = 1"
        p2 = page_alloc(f, h)
        assert p2 == 2, "second alloc = 2"

        # 5. roundtrip
        buf = bytearray(PAGE_SZ)
        buf[0:8] = struct.pack("<Q", 42)
        page_write(f, p1, bytes(buf))
        rb = page_read(f, p1)
        got = struct.unpack_from("<Q", rb, 0)[0]
        assert got == 42, "read back 42"

        # 6. free + reuse
        page_free(f, h, p2)
        p3 = page_alloc(f, h)
        assert p3 == 2, "reused freed page"

    os.remove(path)
    print("page_management: 6/6 ok")


main()
