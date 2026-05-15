#!/bin/bash
set -euo pipefail

echo "Setting up Claude configuration..."

CLAUDE_DIR="${HOME}/.claude"
mkdir -p "${CLAUDE_DIR}/plugins"

# link <repo-file> <target-path>
# Idempotent: skips if symlink already points at the right place;
# otherwise backs up any existing file/symlink before linking.
link() {
    local src="${PWD}/$1"
    local dest="$2"

    if [ ! -e "$src" ]; then
        echo "  ! source missing, skipping: $src"
        return
    fi

    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        echo "  = already linked: $dest"
        return
    fi

    if [ -e "$dest" ] || [ -L "$dest" ]; then
        local backup="${dest}.bak.$(date +%s)"
        echo "  ~ backing up existing $dest -> $backup"
        mv "$dest" "$backup"
    fi

    ln -s "$src" "$dest"
    echo "  + linked $src -> $dest"
}

link CLAUDE.md                       "${CLAUDE_DIR}/claude.md"
link claude_settings.json            "${CLAUDE_DIR}/settings.json"
link statusline-command.sh           "${CLAUDE_DIR}/statusline-command.sh"
link claude_known_marketplaces.json  "${CLAUDE_DIR}/plugins/known_marketplaces.json"

echo "Claude configuration setup complete."
