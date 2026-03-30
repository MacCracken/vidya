# Vidya — Input/Output in Python
#
# Python I/O uses file objects with read/write methods. The open()
# function handles text vs binary mode. Context managers (with)
# ensure files are closed. io.StringIO/BytesIO provide in-memory streams.

import io
import os
import tempfile

def main():
    # ── Writing to a file ───────────────────────────────────────────
    with tempfile.NamedTemporaryFile(mode="w", suffix=".txt", delete=False) as f:
        path = f.name
        f.write("line 1\n")
        f.write("line 2\n")
        f.write("line 3\n")

    # ── Reading entire file ─────────────────────────────────────────
    with open(path, "r") as f:
        content = f.read()
    assert content == "line 1\nline 2\nline 3\n", "read all"

    # ── Line-by-line reading (streaming) ────────────────────────────
    lines = []
    with open(path, "r") as f:
        for line in f:
            lines.append(line.rstrip("\n"))
    assert lines == ["line 1", "line 2", "line 3"], "line iteration"

    # ── readlines vs iteration ──────────────────────────────────────
    with open(path, "r") as f:
        all_lines = f.readlines()
    assert len(all_lines) == 3, "readlines"

    # ── Binary mode ─────────────────────────────────────────────────
    with tempfile.NamedTemporaryFile(mode="wb", suffix=".bin", delete=False) as f:
        bin_path = f.name
        f.write(b"\x00\x01\x02\x03")

    with open(bin_path, "rb") as f:
        data = f.read()
    assert data == b"\x00\x01\x02\x03", "binary read"
    os.unlink(bin_path)

    # ── StringIO: in-memory text stream ─────────────────────────────
    buf = io.StringIO()
    buf.write("hello ")
    buf.write("world")
    assert buf.getvalue() == "hello world", "StringIO"

    # Read back
    buf.seek(0)
    assert buf.read() == "hello world", "StringIO read"

    # ── BytesIO: in-memory binary stream ────────────────────────────
    bbuf = io.BytesIO()
    bbuf.write(b"binary data")
    assert bbuf.getvalue() == b"binary data", "BytesIO"

    # ── Seek and tell ───────────────────────────────────────────────
    buf = io.StringIO("hello world")
    buf.seek(6)
    assert buf.read() == "world", "seek+read"
    buf.seek(0)
    assert buf.tell() == 0, "tell"

    # ── Writing with print() ────────────────────────────────────────
    buf = io.StringIO()
    print("hello", "world", sep=", ", end="!", file=buf)
    assert buf.getvalue() == "hello, world!", "print to stream"

    # ── Append mode ─────────────────────────────────────────────────
    with open(path, "a") as f:
        f.write("line 4\n")
    with open(path, "r") as f:
        lines = f.readlines()
    assert len(lines) == 4, "append mode"

    # ── Context manager ensures close ───────────────────────────────
    f = open(path, "r")
    assert not f.closed
    f.close()
    assert f.closed, "explicitly closed"

    # with statement handles it automatically
    with open(path, "r") as f:
        _ = f.read()
    assert f.closed, "context manager closed"

    # ── Encoding handling ───────────────────────────────────────────
    with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8",
                                      suffix=".txt", delete=False) as f:
        enc_path = f.name
        f.write("café")

    with open(enc_path, "r", encoding="utf-8") as f:
        assert f.read() == "café", "utf-8 roundtrip"

    with open(enc_path, "rb") as f:
        raw = f.read()
    assert len(raw) == 5, "café is 5 bytes in UTF-8"

    # ── Cleanup ─────────────────────────────────────────────────────
    os.unlink(path)
    os.unlink(enc_path)

    print("All input/output examples passed.")


if __name__ == "__main__":
    main()
