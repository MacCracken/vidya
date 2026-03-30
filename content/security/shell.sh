#!/usr/bin/env bash
# Vidya — Security Practices in Shell (Bash)
#
# Shell is dangerous by default: word splitting, glob expansion,
# unquoted variables, and eval all create injection vectors. Security
# in shell means quoting everything, validating inputs, using safe
# temp files, and avoiding eval.

set -euo pipefail

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

assert_fail() {
    local msg="$1"
    shift
    if "$@" 2>/dev/null; then
        echo "FAIL: $msg: command should have failed" >&2
        exit 1
    fi
}

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# ── Input validation ───────────────────────────────────────────────────
validate_username() {
    local input="$1"
    if [[ -z "$input" ]]; then
        echo "username cannot be empty" >&2
        return 1
    fi
    if [[ ${#input} -gt 32 ]]; then
        echo "username too long" >&2
        return 1
    fi
    # Allowlist: only alphanumeric and underscores
    if [[ ! "$input" =~ ^[a-zA-Z0-9_]+$ ]]; then
        echo "invalid characters" >&2
        return 1
    fi
    echo "$input"
}

result=$(validate_username "alice_42")
assert_eq "$result" "alice_42" "valid username"
assert_fail "empty username" validate_username ""
assert_fail "injection attempt" validate_username "alice; rm -rf /"
assert_fail "path traversal" validate_username "../etc/passwd"
assert_fail "special chars" validate_username '<script>'

# ── Quoting prevents word splitting and glob expansion ─────────────────
# BAD: unquoted variable undergoes word splitting and globbing
#   filename="my file.txt"; cat $filename   # tries to cat "my" and "file.txt"
#   input="*"; ls $input                    # expands glob!
# GOOD: always quote variables
filename="my file.txt"
echo "test content" > "$tmpdir/$filename"
content=$(cat "$tmpdir/$filename")   # quoted — works correctly
assert_eq "$content" "test content" "quoted filename"

# ── Safe temp files (avoid race conditions) ────────────────────────────
# BAD: predictable temp file names allow symlink attacks
#   echo "data" > /tmp/myapp_temp    # attacker can symlink this
# GOOD: mktemp creates a unique, unpredictable name
safe_tmp=$(mktemp "$tmpdir/secure_XXXXXX")
echo "sensitive data" > "$safe_tmp"
chmod 600 "$safe_tmp"   # owner-only permissions
perms=$(stat -c %a "$safe_tmp")
assert_eq "$perms" "600" "restrictive permissions"

# ── Avoid eval — it executes arbitrary code ────────────────────────────
# BAD: eval parses and executes user input as shell code
#   user_input='$(rm -rf /)'; eval "echo $user_input"
# GOOD: use printf or direct variable expansion
user_input='$(echo pwned)'
safe_output=$(printf '%s' "$user_input")
assert_eq "$safe_output" '$(echo pwned)' "printf doesn't execute"

# ── Restrict IFS to prevent splitting attacks ──────────────────────────
test_ifs() {
    local original_ifs="$IFS"
    # Set IFS to only newline for safe line-by-line processing
    local IFS=$'\n'
    local input="word1 word2 word3"
    local -a parts=($input)
    # With IFS=\n, spaces don't split
    assert_eq "${#parts[@]}" "1" "IFS newline prevents space splitting"
    IFS="$original_ifs"
}
test_ifs

# ── Safe path handling ─────────────────────────────────────────────────
safe_path() {
    local base="$1" user_input="$2"
    # Reject obvious traversal
    if [[ "$user_input" == *..* ]]; then
        echo "path traversal detected" >&2
        return 1
    fi
    local resolved
    resolved="$base/$user_input"
    # Use realpath --relative-to to verify containment (if files exist)
    # For non-existent paths, at least check for .. components
    echo "$resolved"
}

result=$(safe_path "$tmpdir" "photo.jpg")
assert_eq "$result" "$tmpdir/photo.jpg" "safe path"
assert_fail "traversal" safe_path "$tmpdir" "../../etc/passwd"
assert_fail "traversal parent" safe_path "$tmpdir" "../secret"

# ── Secrets: use /dev/urandom, not $RANDOM ─────────────────────────────
# BAD: $RANDOM is a 15-bit PRNG, trivially predictable
#   token=$RANDOM    # only 32768 possible values!
# GOOD: read from /dev/urandom
token=$(head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n')
assert_eq "${#token}" "64" "urandom hex token length"

# A second token should differ
token2=$(head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n')
if [[ "$token" == "$token2" ]]; then
    echo "FAIL: tokens should differ" >&2
    exit 1
fi

# ── Restricted permissions on sensitive files ──────────────────────────
secret_file="$tmpdir/secret.key"
(umask 077; echo "secret_key_data" > "$secret_file")
perms=$(stat -c %a "$secret_file")
assert_eq "$perms" "600" "secret file permissions"

# Verify group/other can't read
if stat -c %A "$secret_file" | grep -q 'r.\{6\}r'; then
    echo "FAIL: others can read secret file" >&2
    exit 1
fi

# ── Command injection prevention ───────────────────────────────────────
# BAD: using user input directly in a command
#   user_input="file.txt; rm -rf /"; cat $user_input
# GOOD: use -- to stop option processing, quote everything
safe_search() {
    local pattern="$1" file="$2"
    # -- prevents pattern from being interpreted as grep options
    grep -F -- "$pattern" "$file" || true
}

echo "hello world" > "$tmpdir/data.txt"
echo "-e malicious" >> "$tmpdir/data.txt"
result=$(safe_search "hello" "$tmpdir/data.txt")
assert_eq "$result" "hello world" "safe grep"
# -e as a pattern is searched literally, not as a grep flag
result=$(safe_search "-e malicious" "$tmpdir/data.txt")
assert_eq "$result" "-e malicious" "grep -- prevents option injection"

echo "All security examples passed."
