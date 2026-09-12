#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
./build.sh
DESTINATION="$HOME/Applications/Codex Usage.app"
if [[ -e "$DESTINATION" ]]; then
    printf 'Already exists: %s. Quit and remove that copy before reinstalling.\n' "$DESTINATION" >&2
    exit 1
fi
mkdir -p "$HOME/Applications"
ditto --norsrc "build/Codex Usage.app" "$DESTINATION"
xattr -dr com.apple.FinderInfo "$DESTINATION" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$DESTINATION" 2>/dev/null || true
codesign --force --sign - "$DESTINATION"
codesign --verify --strict "$DESTINATION"
open "$DESTINATION"
