#!/bin/bash
# Vidya — Filesystems in Shell (Bash)
#
# Shell is the natural environment for filesystem operations.
# We use a temp directory as a miniature "filesystem" to demonstrate
# create, read, write, delete, metadata (stat/inode), permissions,
# links, and directory traversal.

set -euo pipefail

PASS=0

assert_eq() {
    local got="$1" expected="$2" msg="$3"
    if [[ "$got" != "$expected" ]]; then
        echo "FAIL: $msg: got '$got', expected '$expected'" >&2
        exit 1
    fi
    PASS=$((PASS + 1))
}

# ── Setup: temp directory as our filesystem ────────────────────────
FS_ROOT=$(mktemp -d)
trap "rm -rf $FS_ROOT" EXIT

# ── Create files and directories ──────────────────────────────────
mkdir -p "$FS_ROOT/docs/drafts"
mkdir -p "$FS_ROOT/src"

echo "hello world" > "$FS_ROOT/docs/readme.txt"
echo "fn main() {}" > "$FS_ROOT/src/main.rs"
echo "draft content" > "$FS_ROOT/docs/drafts/notes.txt"

assert_eq "$(cat "$FS_ROOT/docs/readme.txt")" "hello world" "create and read"

# ── Write modes: overwrite vs append ──────────────────────────────
echo "line1" > "$FS_ROOT/log.txt"       # overwrite (truncate)
echo "line2" >> "$FS_ROOT/log.txt"      # append

lines=$(wc -l < "$FS_ROOT/log.txt" | tr -d ' ')
assert_eq "$lines" "2" "append preserves"

# Truncate to empty
: > "$FS_ROOT/log.txt"
size=$(wc -c < "$FS_ROOT/log.txt" | tr -d ' ')
assert_eq "$size" "0" "truncate"

# ── Read techniques ───────────────────────────────────────────────
echo -e "alpha\nbeta\ngamma\ndelta" > "$FS_ROOT/data.txt"

# First line only
first=$(head -n1 "$FS_ROOT/data.txt")
assert_eq "$first" "alpha" "head first line"

# Last line only
last=$(tail -n1 "$FS_ROOT/data.txt")
assert_eq "$last" "delta" "tail last line"

# Line count
count=$(wc -l < "$FS_ROOT/data.txt" | tr -d ' ')
assert_eq "$count" "4" "line count"

# Read line by line
line_num=0
while IFS= read -r line; do
    line_num=$((line_num + 1))
done < "$FS_ROOT/data.txt"
assert_eq "$line_num" "4" "read loop"

# ── Inode concepts via stat ───────────────────────────────────────
# Every file has an inode — a unique identifier in the filesystem.
# stat exposes inode number, size, permissions, timestamps.

inode=$(stat -c '%i' "$FS_ROOT/docs/readme.txt")
assert_eq "$((inode > 0))" "1" "inode positive"

# Two different files have different inodes
inode2=$(stat -c '%i' "$FS_ROOT/src/main.rs")
if [[ "$inode" != "$inode2" ]]; then
    result="different"
else
    result="same"
fi
assert_eq "$result" "different" "unique inodes"

# File type via stat
ftype=$(stat -c '%F' "$FS_ROOT/docs")
assert_eq "$ftype" "directory" "stat file type dir"

ftype2=$(stat -c '%F' "$FS_ROOT/docs/readme.txt")
assert_eq "$ftype2" "regular file" "stat file type regular"

# ── Hard links share inodes ───────────────────────────────────────
ln "$FS_ROOT/docs/readme.txt" "$FS_ROOT/docs/readme_link.txt"

inode_orig=$(stat -c '%i' "$FS_ROOT/docs/readme.txt")
inode_link=$(stat -c '%i' "$FS_ROOT/docs/readme_link.txt")
assert_eq "$inode_orig" "$inode_link" "hard link same inode"

# Hard link count
nlinks=$(stat -c '%h' "$FS_ROOT/docs/readme.txt")
assert_eq "$nlinks" "2" "hard link count"

# ── Symbolic links ────────────────────────────────────────────────
ln -s "$FS_ROOT/docs/readme.txt" "$FS_ROOT/shortcut.txt"

content=$(cat "$FS_ROOT/shortcut.txt")
assert_eq "$content" "hello world" "symlink read-through"

# Symlink has its own inode
inode_sym=$(stat -c '%i' "$FS_ROOT/shortcut.txt")
if [[ "$inode_sym" != "$inode_orig" ]]; then
    result="different"
else
    result="same"
fi
assert_eq "$result" "different" "symlink own inode"

# Detect symlink
if [[ -L "$FS_ROOT/shortcut.txt" ]]; then
    result="link"
else
    result="regular"
fi
assert_eq "$result" "link" "detect symlink"

# ── Permissions ───────────────────────────────────────────────────
chmod 644 "$FS_ROOT/data.txt"
perms=$(stat -c '%a' "$FS_ROOT/data.txt")
assert_eq "$perms" "644" "chmod permissions"

# Readable check
if [[ -r "$FS_ROOT/data.txt" ]]; then
    result="readable"
else
    result="not readable"
fi
assert_eq "$result" "readable" "file readable"

# ── Delete operations ─────────────────────────────────────────────
touch "$FS_ROOT/temp.txt"
assert_eq "$(test -f "$FS_ROOT/temp.txt" && echo yes)" "yes" "file exists"

rm "$FS_ROOT/temp.txt"
assert_eq "$(test -f "$FS_ROOT/temp.txt" && echo yes || echo no)" "no" "file deleted"

# ── Directory traversal with find ─────────────────────────────────
# Find all regular files
file_count=$(find "$FS_ROOT" -type f | wc -l | tr -d ' ')
assert_eq "$((file_count >= 5))" "1" "find files"

# Find by extension
rs_files=$(find "$FS_ROOT" -name "*.rs" | wc -l | tr -d ' ')
assert_eq "$rs_files" "1" "find by extension"

# Find by name pattern
txt_files=$(find "$FS_ROOT" -name "*.txt" -type f | wc -l | tr -d ' ')
assert_eq "$((txt_files >= 4))" "1" "find txt files"

# ── Directory listing and globbing ────────────────────────────────
# Glob expansion for matching files in a directory
count=0
for f in "$FS_ROOT/docs"/*.txt; do
    if [[ -f "$f" ]]; then
        count=$((count + 1))
    fi
done
assert_eq "$count" "2" "glob listing"

# ── File size and disk usage ──────────────────────────────────────
echo "some content" > "$FS_ROOT/sized.txt"
fsize=$(stat -c '%s' "$FS_ROOT/sized.txt")
assert_eq "$((fsize > 0))" "1" "file has size"

# du for directory usage
du_output=$(du -sb "$FS_ROOT" | cut -f1)
assert_eq "$((du_output > 0))" "1" "du reports usage"

# ── Rename (move) ─────────────────────────────────────────────────
echo "moveme" > "$FS_ROOT/old_name.txt"
mv "$FS_ROOT/old_name.txt" "$FS_ROOT/new_name.txt"
assert_eq "$(cat "$FS_ROOT/new_name.txt")" "moveme" "rename preserves content"
assert_eq "$(test -f "$FS_ROOT/old_name.txt" && echo yes || echo no)" "no" "old name gone"

# ── Atomic write pattern ─────────────────────────────────────────
# Write to temp file, then rename — rename is atomic on same filesystem
echo "safe data" > "$FS_ROOT/config.tmp"
mv "$FS_ROOT/config.tmp" "$FS_ROOT/config.txt"
assert_eq "$(cat "$FS_ROOT/config.txt")" "safe data" "atomic write"

echo "All filesystem examples passed ($PASS assertions)."
exit 0
