# Workmux Cheat Sheet

## Quick Setup (Copy-Paste)

```bash
# ╔══════════════════════════════════════════════════════════════════════════════╗
# ║  WORKMUX QUICK START - Run these on your devbox                              ║
# ╚══════════════════════════════════════════════════════════════════════════════╝

# 1. Install OpenCode plugin (one-time)
mkdir -p ~/.config/opencode/plugin
curl -o ~/.config/opencode/plugin/workmux-status.ts \
  https://raw.githubusercontent.com/raine/workmux/main/.opencode/plugin/workmux-status.ts

# 2. Install Claude Code plugin (one-time)
claude plugin marketplace add raine/workmux
claude plugin install workmux-status

# 3. Add tmux popup binding (~/.tmux.conf)
echo 'bind C-s display-popup -h 30 -w 100 -E "workmux dashboard"' >> ~/.tmux.conf
tmux source ~/.tmux.conf

# 4. Create/open a worktree
workmux add my-feature              # New worktree + branch
workmux open existing-branch        # Open existing worktree

# 5. Launch dashboard
workmux dashboard
```

---

## Core Commands

```
┌─────────────────────────────────────────────────────────────────────────────┐
│  WORKTREE LIFECYCLE                                                         │
├─────────────────────────────────────────────────────────────────────────────┤
│  workmux add <branch>        Create worktree + tmux window + start agent    │
│  workmux open <branch>       Open tmux window for existing worktree         │
│  workmux close <branch>      Close tmux window (keep worktree)              │
│  workmux merge <branch>      Merge to main, cleanup worktree + window       │
│  workmux rm <branch>         Remove worktree + window WITHOUT merging       │
│  workmux list                List all worktrees with status                 │
│  workmux path <branch>       Get filesystem path of worktree                │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Dashboard Keybindings

### Main View (Agent List)

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║  KEY        ACTION                                                            ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║  j / k      Navigate up/down                                                  ║
║  1-9        Quick jump to agent                                               ║
║  Enter      Switch to selected agent (closes dashboard)                       ║
║  p          Peek at agent (dashboard stays open)                              ║
║  d          Open DIFF VIEW                                                    ║
║  s          Cycle sort: Priority → Project → Recency → Natural                ║
║  f          Toggle stale filter                                               ║
║  i          Input mode (type directly to agent)                               ║
║  Ctrl+u/d   Scroll preview up/down                                            ║
║  + / -      Resize preview pane                                               ║
║  q / Esc    Quit                                                              ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

### Diff View (press `d`)

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║  KEY        ACTION                                                            ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║  Tab        Toggle WIP (uncommitted) ↔ Review (branch vs main)                ║
║  a          Enter PATCH MODE (stage individual hunks)                         ║
║  j / k      Scroll down/up                                                    ║
║  Ctrl+d/u   Page down/up                                                      ║
║  c          Send commit command to agent                                      ║
║  m          Trigger merge and exit                                            ║
║  q / Esc    Back to agent list                                                ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

### Patch Mode (press `a` from diff)

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║  KEY        ACTION                                                            ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║  y          Stage current hunk                                                ║
║  n          Skip hunk                                                         ║
║  s          Split hunk (if splittable)                                        ║
║  u          Undo last staged hunk                                             ║
║  o          Comment on hunk (sends context to agent!)                         ║
║  j / k      Navigate hunks                                                    ║
║  q / Esc    Exit patch mode                                                   ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

---

## Dashboard Columns

| Column | Description |
|--------|-------------|
| **#** | Quick jump key (1-9) |
| **Project** | Project name from path |
| **Agent** | Worktree/window name |
| **Git** | Diff stats: branch changes (dim) + uncommitted (bright) |
| **Status** | 🤖 working / 💬 waiting / ✅ done / "stale" |
| **Time** | Time since last status change |
| **Title** | Agent session title |

---

## Status Icons

| Icon | Meaning |
|------|---------|
| 🤖 | Agent is working |
| 💬 | Agent waiting for input |
| ✅ | Agent finished |
| `stale` | No recent status updates |

---

## CLI Flags

```bash
workmux dashboard                    # Normal dashboard
workmux dashboard -d                 # Open directly to diff view
workmux dashboard -P 80              # 80% preview pane (default: 60)

workmux add feature -a opencode      # Use specific agent
workmux add feature -A               # Auto-generate branch name from prompt
workmux add feature --base develop   # Branch from specific base
workmux add --pr 123                 # Checkout GitHub PR
```

---

## Workflow: Parallel Agent Development

```bash
# 1. Spawn multiple agents on different features
workmux add auth-system
workmux add payment-flow
workmux add user-dashboard

# 2. Monitor all from dashboard
workmux dashboard

# 3. Review changes (press 'd' on each agent)
# 4. Stage selectively (press 'a' for patch mode)
# 5. Merge completed work
workmux merge auth-system
```

---

## Troubleshooting

### Dashboard shows nothing
```bash
# Check if worktree has tmux window
workmux list   # Look for ✓ in TMUX column

# Open worktree if not open
workmux open <branch-name>

# Restart agent to load status plugin
# (Ctrl+C in agent pane, then run agent again)
```

### Manually set status (for testing)
```bash
workmux set-window-status working   # 🤖
workmux set-window-status waiting   # 💬
workmux set-window-status done      # ✅
```

### Check pane status
```bash
tmux list-panes -a -F '#{window_name} status=#{@workmux_pane_status}'
```

---

## Config File (`.workmux.yaml`)

```yaml
# Project-level config
main_branch: master
worktree_dir: "../"
window_prefix: "wm-"
agent: opencode              # Default agent

panes:
  - command: <agent>         # Main pane runs agent
    focus: true
  - split: horizontal        # Secondary shell pane
    size: 12

post_create:
  - just build-debug         # Run after worktree creation

status_icons:
  working: "🤖"
  waiting: "💬"
  done: "✅"

pre_merge:
  - just test                # Run before merge allowed
```

---

## WezTerm Integration (No Tmux Required)

If using WezTerm instead of tmux, these shortcuts provide similar functionality using WezTerm workspaces:

### Keyboard Shortcuts

```
╔═══════════════════════════════════════════════════════════════════════════════╗
║  KEY        ACTION                                                            ║
╠═══════════════════════════════════════════════════════════════════════════════╣
║  ⌘⇧W       Worktree Picker - switch between ALL worktrees (multi-repo)        ║
║  ⌘⇧N       New Worktree - create new branch from master                       ║
║  ⌘⇧U       Update/Fetch - checkout remote branch as new worktree              ║
║  ⌘⇧I       Import - clone a GitHub repo (auto-registers for picker)           ║
║  ⌘⇧G       Lazygit - open lazygit in current worktree                         ║
║  ⌘⇧C       Claude Code - open Claude in current worktree                      ║
║  ⌘⇧X       Codex - open Codex in current worktree                             ║
║  ⌘⇧O       Dashboard - open workmux dashboard                                 ║
║  ⌘⇧[/]     Switch workspace (previous/next)                                   ║
║  ⌘⇧Enter   Switch to master workspace                                         ║
╚═══════════════════════════════════════════════════════════════════════════════╝
```

### Worktree Picker Icons

| Icon | Meaning |
|------|---------|
| 🟢 | Claude Code running |
| 🟡 | Codex running |
| 🔵 | OpenCode running |
| ○ | No AI session |
| ✱ | Has uncommitted changes |

### Multi-Repo Support

The worktree picker (`⌘⇧W`) supports multiple repositories:

1. **Clone a new repo**: `⌘⇧I` → enter `owner/repo` or full GitHub URL
2. **Auto-registered**: Cloned repos appear in picker automatically
3. **Format**: `[RepoName] branch` when multiple repos registered
4. **Config file**: `~/.config/wezterm/registered_repos.txt`

```bash
# Example registered_repos.txt
~/Projects/TheGameJamTemplate/TheGameJamTemplate
~/Projects/OtherProject
```

### WezTerm vs Tmux Comparison

| Feature | Tmux (workmux) | WezTerm |
|---------|----------------|---------|
| Worktree creation | `workmux add` | `⌘⇧N` |
| Fetch remote branch | `workmux add --pr` | `⌘⇧U` |
| Switch worktrees | Dashboard | `⌘⇧W` |
| Agent status | Tmux pane status | Status bar icons |
| Multiple repos | N/A | `⌘⇧I` to clone & register |

---

## Links

- **Repo**: https://github.com/raine/workmux
- **Docs**: https://workmux.raine.dev/
- **Blog**: https://raine.dev/blog/introduction-to-workmux/
