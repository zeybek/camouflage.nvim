#!/bin/bash

# Setup git hooks for conventional commits

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOKS_DIR="$(git rev-parse --show-toplevel)/.git/hooks"

if [ ! -d "$HOOKS_DIR" ]; then
  echo "Error: Not a git repository or .git/hooks directory not found"
  exit 1
fi

cp "$SCRIPT_DIR/commit-msg" "$HOOKS_DIR/commit-msg"
chmod +x "$HOOKS_DIR/commit-msg"

echo "Git hooks installed successfully!"
echo "Conventional commits will now be enforced."
