# Vidya — Tracing & Structured Logging in Python
#
# Python's logging module provides level-based filtering, handlers, and
# formatters. This covers structured JSON logging, span context managers
# with nanosecond timing, packed error codes, and handler patterns.

import json
import logging
import io
import time


def main():
    # ── Basic log levels ───────────────────────────────────────────────
    # logging module levels: DEBUG=10, INFO=20, WARNING=30, ERROR=40, CRITICAL=50
    assert logging.DEBUG < logging.INFO < logging.WARNING < logging.ERROR < logging.CRITICAL
    assert logging.DEBUG == 10
    assert logging.CRITICAL == 50

    # ── Custom structured JSON logger ──────────────────────────────────

    class JsonFormatter(logging.Formatter):
        """Formats log records as single-line JSON."""
        def format(self, record):
            entry = {
                "level": record.levelname,
                "target": record.name,
                "message": record.getMessage(),
                "timestamp_ns": time.perf_counter_ns(),
            }
            # Attach extra structured fields if present
            if hasattr(record, "extra_fields"):
                entry.update(record.extra_fields)
            return json.dumps(entry, separators=(",", ":"))

    # Set up a logger that writes JSON to a StringIO buffer
    buf = io.StringIO()
    handler = logging.StreamHandler(buf)
    handler.setFormatter(JsonFormatter())

    logger = logging.getLogger("vidya.tracing")
    logger.setLevel(logging.DEBUG)
    logger.handlers.clear()
    logger.addHandler(handler)

    # Log at various levels
    logger.error("connection refused")
    logger.warning("retry attempt 2")
    logger.info("connected")
    logger.debug("query plan cached")

    # Parse the JSON output
    lines = buf.getvalue().strip().split("\n")
    assert len(lines) == 4

    entry0 = json.loads(lines[0])
    assert entry0["level"] == "ERROR"
    assert entry0["target"] == "vidya.tracing"
    assert entry0["message"] == "connection refused"
    assert "timestamp_ns" in entry0

    entry3 = json.loads(lines[3])
    assert entry3["level"] == "DEBUG"

    # ── Level filtering ────────────────────────────────────────────────
    buf2 = io.StringIO()
    handler2 = logging.StreamHandler(buf2)
    handler2.setFormatter(JsonFormatter())

    filtered_logger = logging.getLogger("vidya.filtered")
    filtered_logger.setLevel(logging.WARNING)  # Only WARNING and above
    filtered_logger.handlers.clear()
    filtered_logger.addHandler(handler2)

    filtered_logger.debug("should not appear")
    filtered_logger.info("should not appear")
    filtered_logger.warning("disk 90%")
    filtered_logger.error("disk full")

    filtered_lines = buf2.getvalue().strip().split("\n")
    assert len(filtered_lines) == 2
    assert json.loads(filtered_lines[0])["level"] == "WARNING"
    assert json.loads(filtered_lines[1])["level"] == "ERROR"

    # ── Structured extra fields ────────────────────────────────────────
    buf3 = io.StringIO()
    handler3 = logging.StreamHandler(buf3)
    handler3.setFormatter(JsonFormatter())

    struct_logger = logging.getLogger("vidya.structured")
    struct_logger.setLevel(logging.DEBUG)
    struct_logger.handlers.clear()
    struct_logger.addHandler(handler3)

    # Use LogRecord's extra mechanism
    extra_record = struct_logger.makeRecord(
        name="vidya.structured",
        level=logging.INFO,
        fn="", lno=0, msg="request handled",
        args=(), exc_info=None,
    )
    extra_record.extra_fields = {"method": "GET", "path": "/api/v1", "status": 200}
    struct_logger.handle(extra_record)

    parsed = json.loads(buf3.getvalue().strip())
    assert parsed["method"] == "GET"
    assert parsed["status"] == 200
    assert parsed["message"] == "request handled"

    # ── Span context manager with timing ───────────────────────────────

    class Span:
        """Context manager that measures elapsed time in nanoseconds."""
        def __init__(self, name):
            self.name = name
            self.elapsed_ns = 0
            self._start = 0

        def __enter__(self):
            self._start = time.perf_counter_ns()
            return self

        def __exit__(self, exc_type, exc_val, exc_tb):
            self.elapsed_ns = time.perf_counter_ns() - self._start
            return False  # Do not suppress exceptions

    # Basic span
    with Span("compute") as span:
        total = sum(range(1000))
        assert total == 499_500

    assert span.elapsed_ns >= 0
    print(f"[SPAN] compute: {span.elapsed_ns}ns")

    # Nested spans — outer >= inner
    with Span("request") as outer:
        with Span("parse_body") as inner:
            _ = json.loads('{"key": "value"}')

    assert outer.elapsed_ns >= inner.elapsed_ns

    # ── Packed error codes ─────────────────────────────────────────────
    # Layout: [63..32] = category, [31..0] = code

    CATEGORY_SHIFT = 32
    CODE_MASK = 0xFFFF_FFFF

    CAT_IO = 1
    CAT_PARSE = 2
    CAT_AUTH = 3

    def pack_error(category, code):
        return (category << CATEGORY_SHIFT) | (code & CODE_MASK)

    def unpack_category(packed):
        return (packed >> CATEGORY_SHIFT) & CODE_MASK

    def unpack_code(packed):
        return packed & CODE_MASK

    err = pack_error(CAT_IO, 42)
    assert unpack_category(err) == CAT_IO
    assert unpack_code(err) == 42

    err2 = pack_error(CAT_PARSE, 7)
    assert unpack_category(err2) == CAT_PARSE
    assert unpack_code(err2) == 7

    err3 = pack_error(CAT_AUTH, 0xDEAD)
    assert unpack_category(err3) == CAT_AUTH
    assert unpack_code(err3) == 0xDEAD

    # Different categories, same code -> different packed values
    assert pack_error(CAT_IO, 1) != pack_error(CAT_PARSE, 1)

    # Deterministic
    assert pack_error(CAT_IO, 99) == pack_error(CAT_IO, 99)

    # ── Handler patterns ───────────────────────────────────────────────
    # Multiple handlers: one for errors only, one for everything

    err_buf = io.StringIO()
    all_buf = io.StringIO()

    err_handler = logging.StreamHandler(err_buf)
    err_handler.setLevel(logging.ERROR)
    err_handler.setFormatter(JsonFormatter())

    all_handler = logging.StreamHandler(all_buf)
    all_handler.setLevel(logging.DEBUG)
    all_handler.setFormatter(JsonFormatter())

    multi_logger = logging.getLogger("vidya.multi")
    multi_logger.setLevel(logging.DEBUG)
    multi_logger.handlers.clear()
    multi_logger.addHandler(err_handler)
    multi_logger.addHandler(all_handler)

    multi_logger.info("startup")
    multi_logger.error("crash")

    err_lines = err_buf.getvalue().strip().split("\n")
    all_lines = all_buf.getvalue().strip().split("\n")

    assert len(err_lines) == 1  # Only the error
    assert json.loads(err_lines[0])["level"] == "ERROR"
    assert len(all_lines) == 2  # Both messages

    print("All tracing examples passed.")


if __name__ == "__main__":
    main()
