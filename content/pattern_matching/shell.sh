#!/usr/bin/env bash
# Vidya — Pattern Matching in Shell (Bash)
#
# Bash pattern matching uses case statements, glob patterns, extended
# globs, and regex via [[ =~ ]]. case/esac is the shell's switch
# statement — it matches against glob patterns, not values.

set -euo pipefail

# ── Helper functions ────────────────────────────────────────────────
assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
}

# ── case/esac: pattern matching ─────────────────────────────────────
classify_status() {
    case "$1" in
        200) echo "ok" ;;
        301|302) echo "redirect" ;;
        404) echo "not found" ;;
        5??) echo "server error" ;;  # glob: 5 followed by any two chars
        *) echo "unknown" ;;
    esac
}

assert_eq "$(classify_status 200)" "ok" "200"
assert_eq "$(classify_status 301)" "redirect" "301"
assert_eq "$(classify_status 302)" "redirect" "302"
assert_eq "$(classify_status 404)" "not found" "404"
assert_eq "$(classify_status 503)" "server error" "503"
assert_eq "$(classify_status 999)" "unknown" "999"

# ── case with glob patterns ────────────────────────────────────────
classify_file() {
    case "$1" in
        *.tar.gz|*.tgz) echo "tar gzip" ;;
        *.tar.bz2) echo "tar bzip2" ;;
        *.zip) echo "zip" ;;
        *.rs) echo "rust" ;;
        *.py) echo "python" ;;
        *.sh) echo "shell" ;;
        *) echo "other" ;;
    esac
}

assert_eq "$(classify_file "archive.tar.gz")" "tar gzip" "tar.gz"
assert_eq "$(classify_file "backup.tgz")" "tar gzip" "tgz"
assert_eq "$(classify_file "main.rs")" "rust" "rust file"
assert_eq "$(classify_file "README.md")" "other" "other file"

# ── [[ with glob patterns ]] ───────────────────────────────────────
# == inside [[ does glob matching (not string equality)
text="hello world"
if [[ "$text" == hello* ]]; then
    result="matched"
else
    result="no match"
fi
assert_eq "$result" "matched" "glob in [["

# ── [[ with regex ]] ───────────────────────────────────────────────
email="user@example.com"
if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
    result="valid"
else
    result="invalid"
fi
assert_eq "$result" "valid" "regex email"

# Capture groups via BASH_REMATCH
version="v1.23.456"
if [[ "$version" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[3]}"
fi
assert_eq "$major" "1" "major version"
assert_eq "$minor" "23" "minor version"
assert_eq "$patch" "456" "patch version"

# ── Extended globs (shopt -s extglob) ───────────────────────────────
# Bash extended globs add powerful patterns:
#   ?(pattern) — zero or one
#   *(pattern) — zero or more
#   +(pattern) — one or more
#   @(pattern) — exactly one
#   !(pattern) — not matching
#
# Note: extglob must be enabled before parsing (can't use in -n check).
# Use regex matching as a portable alternative:

classify_number() {
    if [[ "$1" =~ ^[0-9]+$ ]]; then
        echo "integer"
    elif [[ "$1" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "float"
    elif [[ "$1" =~ ^-[0-9]+$ ]]; then
        echo "negative"
    else
        echo "other"
    fi
}

assert_eq "$(classify_number "42")" "integer" "regex integer"
assert_eq "$(classify_number "3.14")" "float" "regex float"
assert_eq "$(classify_number "-7")" "negative" "regex negative"
assert_eq "$(classify_number "abc")" "other" "regex other"

# ── Parameter expansion patterns ───────────────────────────────────
# These are a form of pattern matching built into variable expansion

path="/home/user/documents/file.tar.gz"

# Remove shortest match from end
assert_eq "${path%.gz}" "/home/user/documents/file.tar" "shortest suffix"
# Remove longest match from end
assert_eq "${path%%.*}" "/home/user/documents/file" "longest suffix"
# Remove shortest match from start
assert_eq "${path#*/}" "home/user/documents/file.tar.gz" "shortest prefix"
# Remove longest match from start
assert_eq "${path##*/}" "file.tar.gz" "longest prefix (basename)"

# ── Conditional patterns ───────────────────────────────────────────
check_input() {
    local input="$1"
    case "$input" in
        "")
            echo "empty"
            ;;
        [0-9]*)
            echo "starts with digit"
            ;;
        [a-zA-Z]*)
            echo "starts with letter"
            ;;
        -*)
            echo "flag"
            ;;
        *)
            echo "other"
            ;;
    esac
}

assert_eq "$(check_input "")" "empty" "empty input"
assert_eq "$(check_input "42abc")" "starts with digit" "digit start"
assert_eq "$(check_input "hello")" "starts with letter" "letter start"
assert_eq "$(check_input "--verbose")" "flag" "flag"

# ── Multiple patterns in if-elif ────────────────────────────────────
classify() {
    local n="$1"
    if [[ "$n" -lt 0 ]]; then
        echo "negative"
    elif [[ "$n" -eq 0 ]]; then
        echo "zero"
    elif [[ "$n" -le 10 ]]; then
        echo "small"
    else
        echo "large"
    fi
}

assert_eq "$(classify -5)" "negative" "classify negative"
assert_eq "$(classify 0)" "zero" "classify zero"
assert_eq "$(classify 7)" "small" "classify small"
assert_eq "$(classify 100)" "large" "classify large"

echo "All pattern matching examples passed."
