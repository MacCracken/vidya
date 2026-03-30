#!/usr/bin/env bash
# Bump the project version across all files.
# Usage: ./scripts/version-bump.sh <version>
set -euo pipefail

[ $# -ne 1 ] && echo "Usage: $0 <version>" && exit 1
NEW_VERSION="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 1. VERSION file
echo "$NEW_VERSION" > "$REPO_ROOT/VERSION"

# 2. Cargo.toml
sed -i "0,/^version = \".*\"/s//version = \"${NEW_VERSION}\"/" "$REPO_ROOT/Cargo.toml"

# 3. CLAUDE.md
sed -i "s/^\- \*\*Version\*\*: SemVer .*/- **Version**: SemVer ${NEW_VERSION}/" "$REPO_ROOT/CLAUDE.md"

# 4. CHANGELOG.md — stamp [Unreleased] as new version with today's date
DATE=$(date -u +%Y-%m-%d)
sed -i "s/^## \[Unreleased\]/## [Unreleased]\n\n## [${NEW_VERSION}] — ${DATE}/" "$REPO_ROOT/CHANGELOG.md"

# 5. Regenerate lockfile
cd "$REPO_ROOT" && cargo generate-lockfile 2>/dev/null

echo "Bumped to ${NEW_VERSION} (${DATE})."
echo ""
echo "To release:"
echo "  git add -A && git commit -m 'release: v${NEW_VERSION}'"
echo "  git tag v${NEW_VERSION}"
echo "  git push origin main --tags"
