#!/usr/bin/env bash
# Bump the project version.
# Usage: ./scripts/version-bump.sh <version>
#
# VERSION is the canonical source of truth; cyrius.cyml reads it via
# `version = "${file:VERSION}"` and never needs editing. CLAUDE.md
# doesn't carry a literal version either. So this script only:
#   1. writes VERSION
#   2. stamps the CHANGELOG [Unreleased] → [VERSION] — today
# After running it, manually update the zugot marketplace recipe
# (separate repo) — see CLAUDE.md "Version check" step.
set -euo pipefail

[ $# -ne 1 ] && echo "Usage: $0 <version>" && exit 1
NEW_VERSION="$1"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "$NEW_VERSION" > "$REPO_ROOT/VERSION"

DATE=$(date -u +%Y-%m-%d)
sed -i "s/^## \[Unreleased\]/## [Unreleased]\n\n## [${NEW_VERSION}] — ${DATE}/" "$REPO_ROOT/CHANGELOG.md"

echo "Bumped to ${NEW_VERSION} (${DATE})."
echo ""
echo "Next:"
echo "  - flesh out the CHANGELOG entry under [${NEW_VERSION}]"
echo "  - update zugot marketplace recipe (marketplace/vidya.cyml) to match"
echo "  - git commit && git tag ${NEW_VERSION} && git push --tags"
