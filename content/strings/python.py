# Vidya — Strings in Python
#
# Python strings are immutable sequences of Unicode characters.
# str is the only string type — no owned/borrowed distinction.
# Concatenation creates new objects; join() and f-strings are preferred.

def main():
    # ── Creation ────────────────────────────────────────────────────
    literal = "hello"
    from_constructor = str(42)
    multiline = """line one
line two"""
    assert from_constructor == "42"
    assert multiline.count("\n") == 1

    # ── f-strings: interpolation (Python 3.6+) ──────────────────────
    name = "world"
    greeting = f"hello, {name}"
    assert greeting == "hello, world"

    # Expressions inside f-strings
    assert f"{2 + 2 = }" == "2 + 2 = 4"  # debug format (3.8+)
    assert f"{'hello':>10}" == "     hello"  # alignment

    # ── Immutability: strings cannot be modified in place ────────────
    s = "hello"
    # s[0] = "H"  # ← TypeError! strings are immutable
    s = "H" + s[1:]  # creates a new string
    assert s == "Hello"

    # ── Slicing ─────────────────────────────────────────────────────
    text = "hello world"
    assert text[0:5] == "hello"
    assert text[-5:] == "world"
    assert text[::2] == "hlowrd"  # every other character
    assert text[::-1] == "dlrow olleh"  # reverse

    # ── Common methods ──────────────────────────────────────────────
    assert "  hello  ".strip() == "hello"
    assert "hello world".split() == ["hello", "world"]
    assert "hello".upper() == "HELLO"
    assert "Hello World".lower() == "hello world"
    assert "hello world".replace("world", "python") == "hello python"
    assert "hello world".startswith("hello")
    assert "hello world".endswith("world")
    assert "hello world".find("world") == 6
    assert "hello world".find("missing") == -1

    # ── join() for efficient concatenation ──────────────────────────
    # GOOD: join() is O(n) — one allocation
    words = ["hello", "world", "from", "python"]
    sentence = " ".join(words)
    assert sentence == "hello world from python"

    # BAD: += in a loop is O(n²) — new string every iteration
    # result = ""
    # for w in words: result += w + " "

    # ── Unicode support ─────────────────────────────────────────────
    cafe = "café"
    assert len(cafe) == 4  # Python counts characters, not bytes
    assert cafe[3] == "é"  # direct indexing works (unlike Rust)

    emoji = "hello 🌍"
    assert len(emoji) == 7  # emoji is one character

    # ── Encoding/decoding ───────────────────────────────────────────
    text = "café"
    encoded = text.encode("utf-8")
    assert isinstance(encoded, bytes)
    assert len(encoded) == 5  # é is 2 bytes in UTF-8
    decoded = encoded.decode("utf-8")
    assert decoded == text

    # ── String comparison ───────────────────────────────────────────
    assert "hello" == "hello"  # case-sensitive
    assert "Hello".lower() == "hello".lower()  # case-insensitive
    assert "hello".casefold() == "HELLO".casefold()  # Unicode-aware

    # ── Common conversions ──────────────────────────────────────────
    num = int("42")
    back = str(num)
    assert back == "42"

    pi = float("3.14")
    assert abs(pi - 3.14) < 1e-10

    # ── Checking content ────────────────────────────────────────────
    assert "123".isdigit()
    assert "hello".isalpha()
    assert "hello123".isalnum()
    assert "   ".isspace()

    # ── Raw strings (no escape processing) ──────────────────────────
    path = r"C:\Users\name\docs"
    assert "\\" in path  # backslash is literal

    print("All string examples passed.")


if __name__ == "__main__":
    main()
