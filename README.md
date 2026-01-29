# WezTerm Devbox Config

A WezTerm configuration for seamless remote development on a Mac Mini devbox via SSH, with git worktree management, AI coding assistant integration, and persistent sessions.

## Quick Reference

- **[Visual Cheatsheet](cheatsheet.html)** - Print-friendly HTML reference (open in browser)
- **[CHEATSHEET.md](CHEATSHEET.md)** - Full markdown reference with workmux commands
- **[tmux Cheatsheet](tmux-cheatsheet.html)** - tmux reference for devbox sessions

## Features

- **Git Worktree Management**: Create, switch, and manage git worktrees with keyboard shortcuts
- **Multi-Repo Support**: Work across multiple repositories with a unified worktree picker
- **AI Session Persistence**: Claude Code, Codex, and OpenCode sessions survive SSH disconnects via tmux
- **Smart Status Bar**: Shows active AI sessions with quick-switch shortcuts
- **Workspace Per Worktree**: Each worktree gets its own WezTerm workspace with lazygit sidebar
- **Recency Sorting**: Worktree picker shows recently accessed worktrees first

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Local Mac (WezTerm)                       │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐          │
│  │ Workspace 1 │  │ Workspace 2 │  │ Workspace 3 │          │
│  │  (master)   │  │ (feature-x) │  │ (bugfix-y)  │          │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘          │
│         │                │                │                  │
│         └────────────────┼────────────────┘                  │
│                          │ SSH                               │
└──────────────────────────┼───────────────────────────────────┘
                           │
┌──────────────────────────┼───────────────────────────────────┐
│                    Devbox (Mac Mini)                         │
│                          │                                   │
│  ┌───────────────────────┴───────────────────────┐          │
│  │                    tmux                        │          │
│  │  ┌──────────────┐  ┌──────────────┐           │          │
│  │  │ claude-master│  │ codex-feature│  ...      │          │
│  │  │   (Claude)   │  │   (Codex)    │           │          │
│  │  └──────────────┘  └──────────────┘           │          │
│  └───────────────────────────────────────────────┘          │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Git Worktrees                           │    │
│  │  ~/Projects/MyProject/           (master)            │    │
│  │  ~/Projects/MyProject/../feature-x/                  │    │
│  │  ~/Projects/MyProject/../bugfix-y/                   │    │
│  └─────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────┘
```

## Keyboard Shortcuts

### Worktree Management

| Shortcut | Action |
|----------|--------|
| `⌘⇧W` | **Worktree Picker** - switch between all worktrees (multi-repo) |
| `⌘⇧N` | **New Worktree** - create new branch from master |
| `⌘⇧U` | **Update/Fetch** - checkout remote branch as new worktree |
| `⌘⇧I` | **Import** - clone a GitHub repo (auto-registers for picker) |
| `⌘⇧Enter` | Switch to master workspace |
| `⌘⇧[` / `⌘⇧]` | Switch workspace (previous/next) |

### AI Assistants

| Shortcut | Action |
|----------|--------|
| `⌘⇧C` | **Claude Code** - opens in current worktree (tmux-persistent) |
| `⌘⇧X` | **Codex** - opens in current worktree (tmux-persistent) |
| `Ctrl+1/2/3` | Quick-switch to 1st/2nd/3rd active AI session |

### Navigation

| Shortcut | Action |
|----------|--------|
| `⌘⇧G` | Open lazygit in current worktree |
| `⌘⇧O` | Open workmux dashboard |
| `⌘T` | New tab in current worktree |
| `⌘D` | Split pane horizontally |
| `⌘⇧D` | Split pane vertically |
| `⌘[` / `⌘]` | Navigate panes |
| `⌘1-9` | Switch to tab by number |
| `⌘E` | Tab picker popup |

### Other

| Shortcut | Action |
|----------|--------|
| `⌘⇧R` | Reload configuration |
| `⌘⇧P` | Command palette |
| `⌘⇧L` | Add side panes (worktree list + dashboard) |
| `⌘⇧T` | Local terminal (escape hatch) |

## Worktree Picker Icons

| Icon | Meaning |
|------|---------|
| 🟢 | Claude Code running |
| 🟡 | Codex running |
| 🔵 | OpenCode running |
| ○ | No AI session |
| ✱ | Has uncommitted changes |

## Status Bar

The status bar shows active AI sessions with quick-switch shortcuts:

```
^1 🟢 master  │  ^2 🟡 feature-auth  │  ^3 🔵 bugfix-ui     🌿 current-branch  14:30
```

- `^1`, `^2`, `^3` = Press `Ctrl+1/2/3` to switch
- Colors indicate agent type (green=Claude, yellow=Codex, blue=OpenCode)

## Session Persistence

AI sessions run inside tmux on the devbox, so they survive:
- SSH disconnections
- Network blips
- Laptop sleep
- WezTerm restarts

When you press `⌘⇧C` again, you'll reattach to the existing session.

### Manual tmux Commands (on devbox)

```bash
# List all AI sessions
tmux list-sessions

# Attach to a specific session
tmux attach -t claude-master

# Kill a session
tmux kill-session -t codex-feature-x
```

## Installation

### 1. Local Machine (WezTerm)

```bash
# Copy wezterm.lua to config directory
cp wezterm.lua ~/.config/wezterm/wezterm.lua

# Create registered repos file (optional)
cp registered_repos.txt.example ~/.config/wezterm/registered_repos.txt
```

Edit `wezterm.lua` and update these variables for your setup:

```lua
local DEVBOX_PROJECT = "~/Projects/YourProject"
local DEVBOX_PROJECTS_ROOT = "~/Projects"
```

### 2. Devbox (Remote Mac)

```bash
# Install tmux
brew install tmux

# Copy tmux config
cp tmux.conf ~/.tmux.conf

# Ensure SSH is configured in ~/.ssh/config:
# Host devbox
#   HostName your-devbox-hostname
#   User your-username
#   ForwardAgent yes
```

### 3. Required Tools on Devbox

- `tmux` - Session persistence
- `lazygit` - Git TUI (optional but recommended)
- `workmux` - Worktree management CLI (optional)
- `claude` / `codex` / `opencode` - AI coding assistants

## Multi-Repo Support

Register additional repositories for the worktree picker:

```bash
# Edit ~/.config/wezterm/registered_repos.txt
~/Projects/ProjectA
~/Projects/ProjectB
~/Projects/AnotherRepo
```

Or use `⌘⇧I` to clone a new repo - it auto-registers.

## Customization

### Appearance

```lua
config.color_scheme = "Catppuccin Mocha"
config.font = wezterm.font("JetBrains Mono", { weight = "Medium" })
config.font_size = 13.0
config.window_background_opacity = 0.95
```

### Lazygit Sidebar Width

```lua
local LAZYGIT_WIDTH = 0.30  -- 30% of window
```

### AI Cache TTL

```lua
local AI_CACHE_TTL = 10  -- seconds between status bar updates
```

## Troubleshooting

### AI sessions not showing in picker/status bar

The detection relies on `pgrep` finding claude/codex/opencode processes. Ensure:
1. The AI tool is actually running on devbox
2. SSH connection is working (`ssh devbox` succeeds)

### Worktree picker shows nothing

1. Check SSH: `ssh devbox "workmux list"`
2. Verify registered repos exist on devbox
3. Check WezTerm logs: `⌘⇧P` → "Show Debug Overlay"

### Session not persisting

1. Verify tmux is installed: `ssh devbox "which tmux"`
2. Check for existing session: `ssh devbox "tmux list-sessions"`
3. Look for errors in tmux: `ssh devbox "tmux attach -t claude-master"`

## License

MIT
