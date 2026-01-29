#!/bin/bash
# WezTerm Devbox Config Installer

set -e

echo "🚀 Installing WezTerm Devbox Config..."

# Create config directory if needed
mkdir -p ~/.config/wezterm

# Backup existing config
if [ -f ~/.config/wezterm/wezterm.lua ]; then
    echo "📦 Backing up existing config to wezterm.lua.backup"
    cp ~/.config/wezterm/wezterm.lua ~/.config/wezterm/wezterm.lua.backup
fi

# Copy config
cp wezterm.lua ~/.config/wezterm/wezterm.lua
echo "✅ Copied wezterm.lua"

# Create registered repos file if it doesn't exist
if [ ! -f ~/.config/wezterm/registered_repos.txt ]; then
    cp registered_repos.txt.example ~/.config/wezterm/registered_repos.txt
    echo "✅ Created registered_repos.txt (edit to add your repos)"
fi

echo ""
echo "📝 Next steps:"
echo "   1. Edit ~/.config/wezterm/wezterm.lua and update:"
echo "      - DEVBOX_PROJECT (your main project path on devbox)"
echo "      - DEVBOX_PROJECTS_ROOT (parent directory for projects)"
echo ""
echo "   2. Ensure SSH config has 'devbox' host configured:"
echo "      Host devbox"
echo "        HostName your-devbox-ip-or-hostname"
echo "        User your-username"
echo "        ForwardAgent yes"
echo ""
echo "   3. On devbox, install tmux: brew install tmux"
echo "   4. On devbox, copy tmux.conf: scp tmux.conf devbox:~/.tmux.conf"
echo ""
echo "✨ Installation complete! Restart WezTerm to apply."
