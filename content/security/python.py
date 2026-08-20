# Vidya — Security Practices in Python
#
# Python's dynamic nature makes input validation essential. Use hmac
# for constant-time comparison, secrets for token generation, and
# parameterized queries (never f-strings) for SQL. Watch out for
# pickle deserialization, eval(), and path traversal.

import hashlib
import hmac
import os
from pathlib import Path
import re
import secrets
import tempfile


def main():
    test_input_validation()
    test_allowlist_regex()
    test_constant_time_comparison()
    test_secret_generation()
    test_path_traversal_prevention()
    test_parameterized_query_pattern()
    test_integer_bounds()
    test_safe_deserialization()

    print("All security examples passed.")


# ── Input validation at the boundary ───────────────────────────────────
def validate_username(name: str) -> str:
    """Validate and return username, or raise ValueError."""
    if not name:
        raise ValueError("username cannot be empty")
    if len(name) > 32:
        raise ValueError("username too long")
    if not re.fullmatch(r"[a-zA-Z0-9_]+", name):
        raise ValueError("invalid characters in username")
    return name


def test_input_validation():
    assert validate_username("alice_42") == "alice_42"

    for bad in ["", "a" * 33, "alice; DROP TABLE", "../etc/passwd", "<script>"]:
        try:
            validate_username(bad)
            assert False, f"should have rejected: {bad!r}"
        except ValueError:
            pass


# ── Allowlist regex ────────────────────────────────────────────────────
def is_safe_input(text: str) -> bool:
    """Only allow printable ASCII, no control chars or special sequences."""
    return bool(re.fullmatch(r"[a-zA-Z0-9 .,!?]{1,200}", text))


def test_allowlist_regex():
    assert is_safe_input("Hello, world!")
    assert is_safe_input("Test 123.")
    assert not is_safe_input("")
    assert not is_safe_input("<script>alert(1)</script>")
    assert not is_safe_input("a" * 201)
    assert not is_safe_input("line\nbreak")


# ── Constant-time comparison ──────────────────────────────────────────
def test_constant_time_comparison():
    secret = b"super_secret_token_2024"
    correct = b"super_secret_token_2024"
    wrong = b"super_secret_token_2025"

    # BAD: regular == leaks timing information
    #   if user_token == stored_token: ...

    # GOOD: hmac.compare_digest is constant-time
    assert hmac.compare_digest(secret, correct)
    assert not hmac.compare_digest(secret, wrong)

    # Also works with strings
    assert hmac.compare_digest("token_abc", "token_abc")
    assert not hmac.compare_digest("token_abc", "token_xyz")


# ── Secret generation ─────────────────────────────────────────────────
def test_secret_generation():
    # BAD: random.random() is predictable (Mersenne Twister, not crypto)
    #   import random; token = random.randint(0, 2**64)

    # GOOD: secrets module uses OS entropy
    token = secrets.token_hex(32)  # 64 hex chars = 256 bits
    assert len(token) == 64
    assert all(c in "0123456789abcdef" for c in token)

    # URL-safe tokens for password reset links
    url_token = secrets.token_urlsafe(32)
    assert len(url_token) > 0

    # Two tokens should never be equal
    assert secrets.token_hex(32) != secrets.token_hex(32)


# ── Path traversal prevention ─────────────────────────────────────────
def safe_resolve(base_dir: str, user_input: str) -> str:
    """Resolve user_input within base_dir, rejecting path traversal."""
    # Path.resolve() follows SYMLINKS; os.path.normpath does not. That is the
    # whole difference. normpath is a pure string operation — it collapses
    # "a/../b" without ever touching the filesystem — so a symlink INSIDE the
    # base that points outside it sails straight through a normpath-based
    # check. The lexical form of this function accepted base/escape/passwd
    # where "escape" was a symlink to /etc, and the caller read /etc/passwd.
    #
    # strict=False so a not-yet-created file still resolves; the parent chain
    # is what carries the symlinks, and that is resolved either way.
    base_resolved = Path(base_dir).resolve(strict=False)
    candidate = (base_resolved / user_input).resolve(strict=False)

    # is_relative_to is an exact path-component comparison, so it cannot be
    # fooled by a sibling directory that merely shares a name prefix
    # (/srv/data-evil vs /srv/data) the way a startswith() check can be.
    if candidate != base_resolved and not candidate.is_relative_to(base_resolved):
        raise ValueError(f"path traversal detected: {user_input!r}")
    return str(candidate)


def test_path_traversal_prevention():
    with tempfile.TemporaryDirectory() as base:
        # Safe paths
        assert safe_resolve(base, "photo.jpg").endswith("photo.jpg")
        assert "subdir" in safe_resolve(base, "subdir/file.txt")

        # Traversal attempts — all rejected
        for attack in ["../../etc/passwd", "../secret", "normal/../../escape"]:
            try:
                safe_resolve(base, attack)
                assert False, f"should have rejected: {attack!r}"
            except ValueError:
                pass

        # A SYMLINK inside the base pointing outside it. This is the case a
        # purely lexical check cannot see: the string "escape/passwd" never
        # contains "..", so normpath has nothing to collapse and happily
        # returns a path that resolves to /etc/passwd.
        os.symlink("/etc", os.path.join(base, "escape"))
        try:
            safe_resolve(base, "escape/passwd")
            assert False, "should have rejected symlink escape"
        except ValueError:
            pass


# ── Parameterized query pattern ────────────────────────────────────────
def test_parameterized_query_pattern():
    user_input = "'; DROP TABLE users; --"

    # BAD: string formatting puts user input into SQL
    bad_query = f"SELECT * FROM users WHERE name = '{user_input}'"
    assert "DROP TABLE" in bad_query  # injection present!

    # GOOD: parameterized query — data is never parsed as SQL
    # With sqlite3: cursor.execute("SELECT * FROM users WHERE name = ?", (user_input,))
    template = "SELECT * FROM users WHERE name = ?"
    params = (user_input,)
    assert "DROP TABLE" not in template
    assert params[0] == user_input  # treated as data, not code


# ── Integer / size bounds ──────────────────────────────────────────────
def test_integer_bounds():
    # Python ints don't overflow, but unbounded allocation is still dangerous
    def safe_allocate(size: int) -> bytearray:
        max_size = 100 * 1024 * 1024  # 100 MB limit
        if size < 0 or size > max_size:
            raise ValueError(f"allocation size {size} out of range")
        return bytearray(size)

    assert len(safe_allocate(1024)) == 1024

    for bad_size in [-1, 200 * 1024 * 1024]:
        try:
            safe_allocate(bad_size)
            assert False, f"should have rejected size {bad_size}"
        except ValueError:
            pass


# ── Safe deserialization ───────────────────────────────────────────────
def test_safe_deserialization():
    import json

    # BAD: pickle.loads() executes arbitrary code!
    #   import pickle
    #   data = pickle.loads(user_bytes)  # RCE if user_bytes is crafted

    # GOOD: JSON is data-only, no code execution
    safe_data = json.loads('{"name": "alice", "age": 30}')
    assert safe_data["name"] == "alice"
    assert safe_data["age"] == 30

    # Reject unexpected types even in JSON
    data = json.loads('{"admin": true}')
    assert isinstance(data.get("admin"), bool)


if __name__ == "__main__":
    main()
