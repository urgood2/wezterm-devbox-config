-- Wezterm config for devbox + workmux integration
-- Gives you Superset-like experience with native macOS tabs
local wezterm = require("wezterm")
local act = wezterm.action

local config = wezterm.config_builder()

-- ============================================================================
-- APPEARANCE
-- ============================================================================
config.color_scheme = "Catppuccin Mocha"
config.font = wezterm.font("JetBrains Mono", { weight = "Medium" })
config.font_size = 13.0
config.line_height = 1.1

-- Window styling
config.window_decorations = "RESIZE"
config.window_padding = { left = 8, right = 8, top = 8, bottom = 8 }
config.window_background_opacity = 0.95
config.macos_window_background_blur = 20
config.native_macos_fullscreen_mode = true  -- Use macOS native fullscreen (green button behavior)

-- Tab bar (clickable tabs at top)
config.use_fancy_tab_bar = false -- Use retro tabs (more visible, larger click targets)
config.hide_tab_bar_if_only_one_tab = false
config.tab_bar_at_bottom = false
config.show_new_tab_button_in_tab_bar = true
config.show_tab_index_in_tab_bar = true
config.tab_max_width = 32

-- Tab bar colors (make it stand out)
config.colors = {
	tab_bar = {
		background = "#1e1e2e",
		active_tab = {
			bg_color = "#89b4fa",
			fg_color = "#1e1e2e",
			intensity = "Bold",
		},
		inactive_tab = {
			bg_color = "#313244",
			fg_color = "#cdd6f4",
		},
		inactive_tab_hover = {
			bg_color = "#45475a",
			fg_color = "#cdd6f4",
		},
		new_tab = {
			bg_color = "#313244",
			fg_color = "#89b4fa",
		},
		new_tab_hover = {
			bg_color = "#45475a",
			fg_color = "#89dceb",
		},
	},
}

-- ============================================================================
-- STARTUP LAYOUT
-- ============================================================================
-- 2-pane layout: Main terminal on left, lazygit on right
-- Use ⌘⇧W for worktree picker, tabs for multiple terminals
local ENABLE_STARTUP_LAYOUT = true
local LAZYGIT_WIDTH = 0.30 -- 30% of window width for lazygit

-- ============================================================================
-- WORKSPACES (one per worktree)
-- ============================================================================
-- Workspaces are like virtual desktops - each can have multiple tabs
-- We use them to represent worktrees

-- Store current worktree info per workspace
-- Use GLOBAL to persist across config reloads
wezterm.GLOBAL = wezterm.GLOBAL or {}
wezterm.GLOBAL.worktree_info = wezterm.GLOBAL.worktree_info or {}
wezterm.GLOBAL.worktree_access_times = wezterm.GLOBAL.worktree_access_times or {}

-- Helper to get/set worktree info (always use global)
local function get_worktree_info(workspace)
	return wezterm.GLOBAL.worktree_info[workspace]
end

local function set_worktree_info(workspace, info)
	wezterm.GLOBAL.worktree_info[workspace] = info
	wezterm.log_info("Stored worktree info: " .. workspace .. " -> " .. info.path)
end

-- Track worktree access time for recency sorting
local function record_worktree_access(branch)
	wezterm.GLOBAL.worktree_access_times[branch] = os.time()
end

local function get_worktree_access_time(branch)
	return wezterm.GLOBAL.worktree_access_times[branch] or 0
end

-- Get the project root on devbox (default/primary project)
local DEVBOX_PROJECT = "~/Projects/TheGameJamTemplate/TheGameJamTemplate"
local DEVBOX_PROJECTS_ROOT = "~/Projects"

-- ============================================================================
-- MULTI-REPO REGISTRY (persisted to file)
-- ============================================================================
local REPOS_FILE = wezterm.config_dir .. "/registered_repos.txt"

-- Load registered repos from file
local function load_registered_repos()
	local repos = {}
	local file = io.open(REPOS_FILE, "r")
	if file then
		for line in file:lines() do
			local trimmed = line:gsub("^%s+", ""):gsub("%s+$", "")
			if #trimmed > 0 and not trimmed:match("^#") then
				table.insert(repos, trimmed)
			end
		end
		file:close()
	end
	-- Always include the default project
	local has_default = false
	for _, repo in ipairs(repos) do
		if repo == DEVBOX_PROJECT then
			has_default = true
			break
		end
	end
	if not has_default then
		table.insert(repos, 1, DEVBOX_PROJECT)
	end
	return repos
end

-- Save registered repos to file
local function save_registered_repos(repos)
	local file = io.open(REPOS_FILE, "w")
	if file then
		file:write("# Registered repos for WezTerm worktree picker\n")
		file:write("# One path per line (on devbox)\n")
		for _, repo in ipairs(repos) do
			file:write(repo .. "\n")
		end
		file:close()
	end
end

-- Add a repo to the registry
local function register_repo(repo_path)
	local repos = load_registered_repos()
	for _, repo in ipairs(repos) do
		if repo == repo_path then
			return -- Already registered
		end
	end
	table.insert(repos, repo_path)
	save_registered_repos(repos)
end

-- Get short name for a repo path (last component)
local function get_repo_short_name(repo_path)
	return repo_path:match("([^/]+)$") or repo_path
end

-- Startup layout event (creates 2-pane layout on launch)
-- Layout: [Main Terminal 70%] [Lazygit 30%]
wezterm.on("gui-startup", function(cmd)
	if not ENABLE_STARTUP_LAYOUT then
		local tab, pane, window = wezterm.mux.spawn_window(cmd or {})
		return
	end

	-- Create main terminal pane first (left)
	local tab, main_pane, window = wezterm.mux.spawn_window({
		args = { "ssh", "-t", "devbox", "cd " .. DEVBOX_PROJECT .. " && zsh -l" },
	})

	-- Split right for lazygit (30% width)
	local lazygit_pane = main_pane:split({
		direction = "Right",
		size = LAZYGIT_WIDTH,
		args = { "ssh", "-t", "devbox", "zsh -lc 'cd " .. DEVBOX_PROJECT .. " && lazygit'" },
	})

	-- Focus the main (left) pane
	main_pane:activate()
end)

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Parse workmux list output into structured data
local function parse_workmux_list(output)
	local worktrees = {}
	local lines = {}
	for line in output:gmatch("[^\r\n]+") do
		table.insert(lines, line)
	end

	-- Skip header line
	for i = 2, #lines do
		local line = lines[i]
		if line and #line > 0 and not line:match("^%s*$") then
			-- Parse fixed-width columns from workmux list output
			-- BRANCH                                   TMUX  UNMERGED  PATH
			-- The branch is the first non-space sequence
			local branch = line:match("^(%S+)")
			if branch and branch ~= "BRANCH" then
				local has_tmux = line:find("✓") ~= nil
				local has_changes = line:find("●") ~= nil

				-- Path is everything after the last column marker, trimmed
				-- Look for path patterns: (here), ../, ./, or absolute paths
				local path = line:match("(%S+)%s*$")

				if path then
					table.insert(worktrees, {
						branch = branch,
						has_tmux = has_tmux,
						has_changes = has_changes,
						path = path,
					})
				end
			end
		end
	end
	return worktrees
end

-- Resolve worktree path to absolute path on devbox
local function resolve_worktree_path(path)
	if path == "(here)" then
		return DEVBOX_PROJECT
	elseif path:match("^%.%.") or path:match("^%.%/") or path:match("^%.worktrees") then
		-- Relative path - resolve from project root
		return DEVBOX_PROJECT .. "/" .. path
	else
		-- Assume it's already a usable path
		return path
	end
end

-- Get the current workspace's worktree path
local function get_current_worktree_path(window)
	local workspace = window:active_workspace()
	local info = get_worktree_info(workspace)
	if info and info.path then
		wezterm.log_info("Using worktree path for workspace '" .. workspace .. "': " .. info.path)
		return info.path
	end
	-- Default to project root
	wezterm.log_info("No worktree info for workspace '" .. workspace .. "', using default: " .. DEVBOX_PROJECT)
	return DEVBOX_PROJECT
end

-- ============================================================================
-- CUSTOM EVENTS
-- ============================================================================

-- Event: Switch to a worktree (creates new workspace or switches to existing)
-- New workspaces get a 2-pane layout with lazygit on the right
wezterm.on("switch-worktree", function(window, pane, worktree_path, branch_name)
	local workspace_name = branch_name:gsub("/", "-"):gsub("%s+", "-")
	local full_path = resolve_worktree_path(worktree_path)

	-- Record access time for recency sorting in picker
	record_worktree_access(branch_name)

	-- Store worktree info BEFORE switching (so new tabs know the path)
	set_worktree_info(workspace_name, {
		branch = branch_name,
		path = full_path,
	})

	-- Check if workspace already exists
	local workspaces = wezterm.mux.get_workspace_names()
	local exists = false
	for _, ws in ipairs(workspaces) do
		if ws == workspace_name then
			exists = true
			break
		end
	end

	if exists then
		-- Switch to existing workspace
		window:perform_action(act.SwitchToWorkspace({ name = workspace_name }), pane)
	else
		-- Create new workspace with 2-pane layout: main terminal + lazygit
		window:perform_action(
			act.SwitchToWorkspace({
				name = workspace_name,
				spawn = {
					args = { "ssh", "-t", "devbox", "cd " .. full_path .. " && zsh -l" },
				},
			}),
			pane
		)

		-- After switching, spawn lazygit in a split on the right
		-- We need to defer this slightly to let the workspace initialize
		wezterm.time.call_after(0.5, function()
			local mux_window = wezterm.mux.get_active_window()
			if mux_window then
				local active_tab = mux_window:active_tab()
				if active_tab then
					local active_pane = active_tab:active_pane()
					if active_pane then
						active_pane:split({
							direction = "Right",
							size = LAZYGIT_WIDTH,
							args = { "ssh", "-t", "devbox", "zsh -lc 'cd " .. full_path .. " && lazygit'" },
						})
					end
				end
			end
		end)
	end
end)

-- Event: Switch to a worktree from any registered repo (multi-repo support)
wezterm.on("switch-worktree-multi", function(window, pane, repo_path, worktree_path, branch_name)
	-- Resolve full path based on repo
	local full_path
	if worktree_path == "(here)" then
		full_path = repo_path
	elseif worktree_path:match("^%.") then
		full_path = repo_path .. "/" .. worktree_path
	else
		full_path = worktree_path
	end

	-- Create unique workspace name: repo-branch
	local repo_name = get_repo_short_name(repo_path)
	local workspace_name = repo_name .. "-" .. branch_name:gsub("/", "-"):gsub("%s+", "-")

	-- Record access time for recency sorting in picker
	record_worktree_access(branch_name)

	-- Store worktree info
	set_worktree_info(workspace_name, {
		branch = branch_name,
		path = full_path,
		repo = repo_path,
	})

	-- Check if workspace already exists
	local workspaces = wezterm.mux.get_workspace_names()
	local exists = false
	for _, ws in ipairs(workspaces) do
		if ws == workspace_name then
			exists = true
			break
		end
	end

	if exists then
		window:perform_action(act.SwitchToWorkspace({ name = workspace_name }), pane)
	else
		window:perform_action(
			act.SwitchToWorkspace({
				name = workspace_name,
				spawn = {
					args = { "ssh", "-t", "devbox", "cd " .. full_path .. " && zsh -l" },
				},
			}),
			pane
		)

		-- Spawn lazygit in split
		wezterm.time.call_after(0.5, function()
			local mux_window = wezterm.mux.get_active_window()
			if mux_window then
				local active_tab = mux_window:active_tab()
				if active_tab then
					local active_pane = active_tab:active_pane()
					if active_pane then
						active_pane:split({
							direction = "Right",
							size = LAZYGIT_WIDTH,
							args = { "ssh", "-t", "devbox", "zsh -lc 'cd " .. full_path .. " && lazygit'" },
						})
					end
				end
			end
		end)
	end
end)

-- Event: Spawn new tab in current workspace's worktree
wezterm.on("new-tab-in-worktree", function(window, pane)
	local path = get_current_worktree_path(window)
	window:perform_action(
		act.SpawnCommandInNewTab({
			args = { "ssh", "-t", "devbox", "cd " .. path .. " && zsh -l" },
		}),
		pane
	)
end)

-- Event: Split pane in current workspace's worktree
wezterm.on("split-pane-in-worktree", function(window, pane, direction)
	local path = get_current_worktree_path(window)
	local split_action
	if direction == "horizontal" then
		split_action = act.SplitHorizontal({
			args = { "ssh", "-t", "devbox", "cd " .. path .. " && zsh -l" },
		})
	else
		split_action = act.SplitVertical({
			args = { "ssh", "-t", "devbox", "cd " .. path .. " && zsh -l" },
		})
	end
	window:perform_action(split_action, pane)
end)

-- Event: Fetch worktrees from ALL registered repos and show picker
wezterm.on("fetch-and-show-worktrees", function(window, pane)
	local repos = load_registered_repos()

	-- Build command to query all repos
	-- Format: REPO:<repo_path>\n<workmux list output>\n for each repo
	local repo_cmds = {}
	for _, repo in ipairs(repos) do
		table.insert(
			repo_cmds,
			string.format(
				'echo "REPO:%s" && cd %s 2>/dev/null && workmux list 2>/dev/null || echo "SKIP"',
				repo,
				repo
			)
		)
	end
	local all_repos_cmd = table.concat(repo_cmds, " && ")

	-- Also get AI sessions
	local full_cmd = all_repos_cmd
		.. [[ && echo "---AI---" && for pid in $(pgrep -f 'claude|codex|opencode' 2>/dev/null); do cmd=$(ps -p $pid -o comm= 2>/dev/null); cwd=$(lsof -a -p $pid -d cwd 2>/dev/null | tail -1 | awk '{print $NF}'); echo "$cmd:$cwd"; done 2>/dev/null]]

	local success, stdout, stderr = wezterm.run_child_process({
		"ssh",
		"devbox",
		full_cmd,
	})

	if success and stdout then
		-- Split output into repo sections and AI processes
		local repos_output = stdout:match("(.-)%-%-%-AI%-%-%-") or stdout
		local ai_output = stdout:match("%-%-%-AI%-%-%-(.*)") or ""

		-- Parse AI sessions into a table: path -> agent type
		local ai_sessions = {}
		for line in ai_output:gmatch("[^\r\n]+") do
			local agent, path = line:match("([^:]+):(.+)")
			if agent and path then
				local agent_type = nil
				if agent:find("claude") then
					agent_type = "claude"
				elseif agent:find("codex") then
					agent_type = "codex"
				elseif agent:find("opencode") then
					agent_type = "opencode"
				end
				if agent_type and path then
					ai_sessions[path] = agent_type
				end
			end
		end

		-- Parse worktrees from all repos
		local all_worktrees = {} -- { repo_path, repo_name, branch, path, has_changes }
		local current_repo = nil
		local current_repo_name = nil
		local in_header = true

		for line in repos_output:gmatch("[^\r\n]+") do
			if line:match("^REPO:") then
				current_repo = line:gsub("^REPO:", "")
				current_repo_name = get_repo_short_name(current_repo)
				in_header = true
			elseif line == "SKIP" then
				current_repo = nil
			elseif current_repo then
				-- Skip header line (BRANCH TMUX UNMERGED PATH)
				if in_header and line:match("^BRANCH") then
					in_header = false
				elseif not in_header and #line > 0 and not line:match("^%s*$") then
					local branch = line:match("^(%S+)")
					if branch and branch ~= "BRANCH" then
						local has_changes = line:find("●") ~= nil
						local path = line:match("(%S+)%s*$")
						if path then
							table.insert(all_worktrees, {
								repo_path = current_repo,
								repo_name = current_repo_name,
								branch = branch,
								wt_path = path,
								has_changes = has_changes,
							})
						end
					end
				end
			end
		end

		-- Build choices with repo prefix
		local choices = {}
		local worktrees_lookup = {}
		local multiple_repos = #repos > 1

		for idx, wt in ipairs(all_worktrees) do
			local changes_icon = wt.has_changes and "✱" or " "

			-- Check for AI session
			local ai_icon = "○"
			local is_active = false
			local full_path = wt.wt_path
			if full_path == "(here)" then
				full_path = wt.repo_path
			elseif full_path:match("^%.") then
				full_path = wt.repo_path .. "/" .. full_path
			end
			local expanded_path = full_path:gsub("^~", "/Users/joshuashin")

			for session_path, agent_type in pairs(ai_sessions) do
				if session_path:find(expanded_path, 1, true) or expanded_path:find(session_path, 1, true) then
					is_active = true
					if agent_type == "claude" then
						ai_icon = "🟢"
					elseif agent_type == "codex" then
						ai_icon = "🟡"
					elseif agent_type == "opencode" then
						ai_icon = "🔵"
					end
					break
				end
			end

			-- Format: [RepoName] branch (only show repo name if multiple repos)
			local label
			if multiple_repos then
				label = string.format("%s %s [%s] %s", ai_icon, changes_icon, wt.repo_name, wt.branch)
			else
				label = string.format("%s %s %s", ai_icon, changes_icon, wt.branch)
			end

			table.insert(choices, {
				label = label,
				id = tostring(idx),
				is_active = is_active,
				branch = wt.branch,  -- Store for recency lookup
			})
			worktrees_lookup[idx] = wt
		end

		-- Sort: active first, then by recency (most recent first), then alphabetically
		table.sort(choices, function(a, b)
			-- Active worktrees always come first
			if a.is_active and not b.is_active then
				return true
			elseif not a.is_active and b.is_active then
				return false
			end
			-- Within same active status, sort by recency
			local a_time = get_worktree_access_time(a.branch)
			local b_time = get_worktree_access_time(b.branch)
			if a_time ~= b_time then
				return a_time > b_time  -- Most recent first
			end
			-- Fallback to alphabetical
			return a.label < b.label
		end)

		-- Remove temporary fields (InputSelector only accepts label and id)
		for _, choice in ipairs(choices) do
			choice.is_active = nil
			choice.branch = nil
		end

		if #choices == 0 then
			table.insert(choices, { label = "No worktrees found", id = "none" })
		end

		window:perform_action(
			act.InputSelector({
				title = "🌳 Switch Worktree (click or type)",
				choices = choices,
				fuzzy = true,
				action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
					if id and id ~= "none" then
						local idx = tonumber(id)
						if idx and worktrees_lookup[idx] then
							local wt = worktrees_lookup[idx]
							-- Pass repo_path to switch-worktree for proper path resolution
							wezterm.emit(
								"switch-worktree-multi",
								inner_window,
								inner_pane,
								wt.repo_path,
								wt.wt_path,
								wt.branch
							)
						end
					end
				end),
			}),
			pane
		)
	else
		window:perform_action(
			act.InputSelector({
				title = "🌳 Switch Worktree",
				choices = { { label = "Error: " .. (stderr or "Could not fetch worktrees"), id = "error" } },
				action = wezterm.action_callback(function() end),
			}),
			pane
		)
	end
end)

-- Event: Open workmux dashboard
wezterm.on("open-dashboard", function(window, pane)
	window:perform_action(
		act.SpawnCommandInNewTab({
			args = { "ssh", "-t", "devbox", "zsh -lc 'cd " .. DEVBOX_PROJECT .. " && workmux dashboard'" },
		}),
		pane
	)
end)

-- Event: Create new worktree
-- Uses git worktree directly since workmux requires tmux
wezterm.on("new-worktree", function(window, pane)
	window:perform_action(
		act.PromptInputLine({
			description = "Enter branch name for new worktree:",
			action = wezterm.action_callback(function(inner_window, inner_pane, line)
				if line and #line > 0 then
					-- Sanitize branch name for directory (replace / with -)
					local dir_name = line:gsub("/", "-")
					local worktree_path = "../" .. dir_name

					-- Create worktree with git worktree add
					-- -b creates a new branch, base is master
					local create_cmd = "git worktree add -b "
						.. line
						.. " "
						.. worktree_path
						.. " master 2>&1"

					-- Spawn tab that creates worktree then switches to it
					inner_window:perform_action(
						act.SpawnCommandInNewTab({
							args = {
								"ssh",
								"-t",
								"devbox",
								"zsh -lc 'cd "
									.. DEVBOX_PROJECT
									.. " && echo \"Creating worktree: "
									.. line
									.. "\" && "
									.. create_cmd
									.. " && cd "
									.. worktree_path
									.. " && exec zsh'",
							},
						}),
						inner_pane
					)

					-- Store worktree info for the new workspace
					local workspace_name = line:gsub("/", "-"):gsub("%s+", "-")
					local full_path = DEVBOX_PROJECT .. "/" .. worktree_path
					set_worktree_info(workspace_name, {
						branch = line,
						path = full_path,
					})
				end
			end),
		}),
		pane
	)
end)

-- Event: Fetch and checkout a remote branch as a new worktree
wezterm.on("fetch-remote-worktree", function(window, pane)
	-- Fetch latest and list ALL remote branches (not just unmerged)
	local success, stdout, stderr = wezterm.run_child_process({
		"ssh",
		"devbox",
		"cd "
			.. DEVBOX_PROJECT
			.. [[ && git fetch origin --prune 2>&1 && echo "---BRANCHES---" && git branch -r 2>/dev/null | grep -v HEAD | sed 's/^ *//' && echo "---LOCAL---" && git worktree list --porcelain | grep '^branch' | sed 's/branch refs\/heads\///' ]],
	})

	if success and stdout then
		-- Parse remote branches and local worktrees
		local branches_output = stdout:match("%-%-%-BRANCHES%-%-%-(.-)%-%-%-LOCAL%-%-%-") or ""
		local local_output = stdout:match("%-%-%-LOCAL%-%-%-(.*)") or ""

		-- Build set of local branches (already have worktrees)
		local local_branches = {}
		for line in local_output:gmatch("[^\r\n]+") do
			local branch = line:gsub("^%s+", ""):gsub("%s+$", "")
			if #branch > 0 then
				-- Store both with and without origin/ prefix for matching
				local_branches[branch] = true
				local_branches["origin/" .. branch] = true
			end
		end

		-- Parse remote branches, filter out ones we already have locally
		local choices = {}
		for line in branches_output:gmatch("[^\r\n]+") do
			local remote_branch = line:gsub("^%s+", ""):gsub("%s+$", "")
			if #remote_branch > 0 and remote_branch:match("^origin/") then
				local local_name = remote_branch:gsub("^origin/", "")
				-- Only show branches we don't have locally
				if not local_branches[local_name] then
					table.insert(choices, {
						label = "📥 " .. local_name,
						id = remote_branch,
					})
				end
			end
		end

		-- Sort alphabetically
		table.sort(choices, function(a, b)
			return a.label < b.label
		end)

		if #choices == 0 then
			table.insert(choices, { label = "No new remote branches found", id = "none" })
		end

		window:perform_action(
			act.InputSelector({
				title = "📥 Fetch Remote Branch as Worktree",
				choices = choices,
				fuzzy = true,
				action = wezterm.action_callback(function(inner_window, inner_pane, id, label)
					if id and id ~= "none" then
						-- id is the full remote ref (e.g., origin/feature-x)
						local local_name = id:gsub("^origin/", "")
						local dir_name = local_name:gsub("/", "-")
						local worktree_path = "../" .. dir_name

						-- Create worktree tracking the remote branch
						-- git worktree add <path> <remote-branch> automatically tracks it
						inner_window:perform_action(
							act.SpawnCommandInNewTab({
								args = {
									"ssh",
									"-t",
									"devbox",
									"zsh -lc 'cd "
										.. DEVBOX_PROJECT
										.. " && echo \"Fetching remote branch: "
										.. local_name
										.. "\" && git worktree add "
										.. worktree_path
										.. " "
										.. id
										.. " && cd "
										.. worktree_path
										.. " && exec zsh'",
								},
							}),
							inner_pane
						)

						-- Store worktree info
						local workspace_name = local_name:gsub("/", "-"):gsub("%s+", "-")
						local full_path = DEVBOX_PROJECT .. "/" .. worktree_path
						set_worktree_info(workspace_name, {
							branch = local_name,
							path = full_path,
						})
					end
				end),
			}),
			pane
		)
	else
		window:perform_action(
			act.InputSelector({
				title = "📥 Fetch Remote Branch",
				choices = { { label = "Error: " .. (stderr or "Could not fetch branches"), id = "error" } },
				action = wezterm.action_callback(function() end),
			}),
			pane
		)
	end
end)

-- Event: Clone a GitHub repo and register it
wezterm.on("clone-github-repo", function(window, pane)
	window:perform_action(
		act.PromptInputLine({
			description = "Enter GitHub repo (owner/repo or full URL):",
			action = wezterm.action_callback(function(inner_window, inner_pane, line)
				if line and #line > 0 then
					-- Parse repo input - accept "owner/repo" or full URL
					local repo_spec = line:gsub("^https?://github.com/", ""):gsub("%.git$", "")
					local repo_name = repo_spec:match("([^/]+)$") or repo_spec

					-- Clone to ~/Projects/<repo_name>
					local clone_path = DEVBOX_PROJECTS_ROOT .. "/" .. repo_name
					local clone_url = "https://github.com/" .. repo_spec .. ".git"

					inner_window:perform_action(
						act.SpawnCommandInNewTab({
							args = {
								"ssh",
								"-t",
								"devbox",
								"zsh -lc '"
									.. "echo \"Cloning "
									.. repo_spec
									.. " to "
									.. clone_path
									.. "\" && "
									.. "git clone "
									.. clone_url
									.. " "
									.. clone_path
									.. " && "
									.. "cd "
									.. clone_path
									.. " && "
									.. "echo \"Clone complete! Repo registered.\" && "
									.. "exec zsh'",
							},
						}),
						inner_pane
					)

					-- Register the repo (will be picked up on next picker open)
					register_repo(clone_path)

					-- Store worktree info for immediate workspace switch
					local workspace_name = repo_name .. "-" .. "main"
					set_worktree_info(workspace_name, {
						branch = "main",
						path = clone_path,
						repo = clone_path,
					})
				end
			end),
		}),
		pane
	)
end)

-- Event: Open lazygit in current worktree
wezterm.on("open-lazygit", function(window, pane)
	local path = get_current_worktree_path(window)
	window:perform_action(
		act.SpawnCommandInNewTab({
			args = { "ssh", "-t", "devbox", "zsh -lc 'cd " .. path .. " && lazygit'" },
		}),
		pane
	)
end)

-- Helper: Generate tmux session name from path
local function get_tmux_session_name(path, agent_type)
	-- Extract branch name from path for readable session names
	local branch = path:match("/%.worktrees/([^/]+)") or path:match("/([^/]+)$") or "main"
	-- Sanitize for tmux session name (alphanumeric, dash, underscore only)
	branch = branch:gsub("[^%w%-_]", "-")
	return agent_type .. "-" .. branch
end

-- Event: Open Codex in current worktree (cx)
-- Runs inside tmux so session persists across SSH disconnections
wezterm.on("open-codex", function(window, pane)
	local path = get_current_worktree_path(window)
	local session_name = get_tmux_session_name(path, "codex")
	local codex_cmd = 'codex -c model_reasoning_effort="high" --ask-for-approval never --sandbox danger-full-access -c model_reasoning_summary="detailed" -c model_supports_reasoning_summaries=true'

	-- tmux new-session -A: attach if exists, create if not
	-- -s: session name, -c: starting directory
	local tmux_cmd = string.format(
		"tmux new-session -A -s %s -c %s '%s'",
		session_name,
		path,
		codex_cmd
	)

	window:perform_action(
		act.SpawnCommandInNewTab({
			args = { "ssh", "-t", "devbox", "zsh -lc '" .. tmux_cmd .. "'" },
		}),
		pane
	)
end)

-- Event: Open Claude Code in current worktree (cc) with dangerous bypass
-- Runs inside tmux so session persists across SSH disconnections
wezterm.on("open-claude", function(window, pane)
	local path = get_current_worktree_path(window)
	local session_name = get_tmux_session_name(path, "claude")
	local claude_cmd = "claude --dangerously-skip-permissions"

	-- tmux new-session -A: attach if exists, create if not
	local tmux_cmd = string.format(
		"tmux new-session -A -s %s -c %s '%s'",
		session_name,
		path,
		claude_cmd
	)

	window:perform_action(
		act.SpawnCommandInNewTab({
			args = { "ssh", "-t", "devbox", "zsh -lc '" .. tmux_cmd .. "'" },
		}),
		pane
	)
end)

-- ============================================================================
-- TAB TITLE
-- ============================================================================
wezterm.on("format-tab-title", function(tab, tabs, panes, cfg, hover, max_width)
	local title = tab.active_pane.title
	local index = tab.tab_index + 1

	-- Clean up SSH prefix if present
	title = title:gsub("^ssh %- devbox %- ", "")
	title = title:gsub("^ssh devbox ", "")

	-- Truncate if needed
	if #title > max_width - 4 then
		title = title:sub(1, max_width - 7) .. "..."
	end

	return string.format(" %d: %s ", index, title)
end)

-- ============================================================================
-- STATUS BAR (shows AI sessions at a glance)
-- ============================================================================
-- Cache AI sessions to avoid hammering SSH
wezterm.GLOBAL.ai_cache = wezterm.GLOBAL.ai_cache or { data = "", updated = 0 }
local AI_CACHE_TTL = 10 -- seconds

-- Fetch AI sessions in background
local function refresh_ai_sessions()
	local now = os.time()
	if now - wezterm.GLOBAL.ai_cache.updated < AI_CACHE_TTL then
		return -- Cache still fresh
	end

	wezterm.GLOBAL.ai_cache.updated = now

	-- Run in background to avoid blocking
	local success, stdout, _ = wezterm.run_child_process({
		"ssh",
		"devbox",
		[[for pid in $(pgrep -f 'claude|codex|opencode' 2>/dev/null); do cmd=$(ps -p $pid -o comm= 2>/dev/null); cwd=$(lsof -a -p $pid -d cwd 2>/dev/null | tail -1 | awk '{print $NF}'); echo "$cmd:$cwd"; done 2>/dev/null]],
	})

	if success and stdout then
		wezterm.GLOBAL.ai_cache.data = stdout
	end
end

-- Parse cached AI sessions into structured data (for status bar and lookups)
local function get_ai_sessions_structured()
	local ai_output = wezterm.GLOBAL.ai_cache.data or ""
	local sessions = {} -- { branch, icon, path, agent_type }
	local seen = {}

	for line in ai_output:gmatch("[^\r\n]+") do
		local agent, path = line:match("([^:]+):(.+)")
		if agent and path then
			-- Extract branch name from path
			local branch = path:match("/%.worktrees/([^/]+)") or path:match("/([^/]+)$") or "master"

			local icon = nil
			local agent_type = nil
			if agent:find("claude") then
				icon = "🟢"
				agent_type = "claude"
			elseif agent:find("codex") then
				icon = "🟡"
				agent_type = "codex"
			elseif agent:find("opencode") then
				icon = "🔵"
				agent_type = "opencode"
			end

			-- Deduplicate by branch
			if icon and not seen[branch] then
				seen[branch] = true
				table.insert(sessions, {
					branch = branch,
					icon = icon,
					path = path,
					agent_type = agent_type,
				})
			end
		end
	end

	-- Sort alphabetically by branch
	table.sort(sessions, function(a, b)
		return a.branch < b.branch
	end)

	return sessions
end

-- Store sessions globally for click handling
wezterm.GLOBAL.ai_sessions_list = wezterm.GLOBAL.ai_sessions_list or {}
wezterm.GLOBAL.ai_session_positions = wezterm.GLOBAL.ai_session_positions or {}

wezterm.on("update-status", function(window, pane)
	-- Refresh AI sessions cache (non-blocking after first call)
	refresh_ai_sessions()

	local workspace = window:active_workspace()
	local info = get_worktree_info(workspace)

	-- Get structured AI sessions
	local sessions = get_ai_sessions_structured()
	wezterm.GLOBAL.ai_sessions_list = sessions

	-- Build left status with colored segments and numbered shortcuts
	local left_elements = {}

	if #sessions > 0 then
		table.insert(left_elements, { Text = "  " })
		for i, session in ipairs(sessions) do
			-- Color based on agent type
			local color = "#a6e3a1" -- default green
			if session.agent_type == "codex" then
				color = "#f9e2af" -- yellow
			elseif session.agent_type == "opencode" then
				color = "#89b4fa" -- blue
			end

			-- Show number shortcut (Ctrl+1/2/3)
			table.insert(left_elements, { Foreground = { Color = "#6c7086" } })
			table.insert(left_elements, { Text = "^" .. i .. " " })

			-- Session icon and branch
			table.insert(left_elements, { Foreground = { Color = color } })
			table.insert(left_elements, { Text = session.icon .. " " .. session.branch })

			if i < #sessions then
				table.insert(left_elements, { Foreground = { Color = "#45475a" } })
				table.insert(left_elements, { Text = " │ " })
			end
		end
		table.insert(left_elements, { Text = "  " })
	end
	window:set_left_status(wezterm.format(left_elements))

	-- Right status: current branch + time
	local right_status = workspace
	if info then
		right_status = string.format("🌿 %s", info.branch)
	end
	right_status = right_status .. "  " .. wezterm.strftime("%H:%M")

	window:set_right_status(wezterm.format({
		{ Foreground = { Color = "#89b4fa" } },
		{ Text = right_status .. "  " },
	}))
end)

-- Event handler for switching to active AI session by index (1-3)
wezterm.on("switch-to-active-session", function(window, pane, index)
	local sessions = wezterm.GLOBAL.ai_sessions_list or {}

	if index > #sessions then
		wezterm.log_info("No active session at index " .. index)
		return
	end

	local session = sessions[index]
	local workspace_name = session.branch:gsub("/", "-"):gsub("%s+", "-")

	wezterm.log_info("Switching to session " .. index .. ": " .. session.branch)

	-- Try to find existing workspace
	local workspaces = wezterm.mux.get_workspace_names()
	local found_ws = nil

	-- Check various workspace name formats
	local possible_names = {
		workspace_name,
		"TheGameJamTemplate-" .. workspace_name,
		session.branch:gsub("/", "-"),
	}

	for _, ws_name in ipairs(possible_names) do
		for _, ws in ipairs(workspaces) do
			if ws == ws_name or ws:find(workspace_name, 1, true) then
				found_ws = ws
				break
			end
		end
		if found_ws then
			break
		end
	end

	if found_ws then
		window:perform_action(act.SwitchToWorkspace({ name = found_ws }), pane)
	else
		-- Create new workspace for this session
		window:perform_action(
			act.SwitchToWorkspace({
				name = workspace_name,
				spawn = {
					args = { "ssh", "-t", "devbox", "cd " .. session.path .. " && zsh -l" },
				},
			}),
			pane
		)
	end
end)

-- ============================================================================
-- KEY BINDINGS
-- ============================================================================
config.leader = { key = "b", mods = "CTRL", timeout_milliseconds = 1000 }

config.keys = {
	-- Worktree management
	{
		key = "w",
		mods = "CMD|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("fetch-and-show-worktrees", window, pane)
		end),
	},
	{
		key = "o",
		mods = "CMD|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("open-dashboard", window, pane)
		end),
	},
	{
		key = "n",
		mods = "CMD|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("new-worktree", window, pane)
		end),
	},
	{
		key = "g",
		mods = "CMD|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("open-lazygit", window, pane)
		end),
	},
	-- Fetch remote branch as worktree (U for Update from remote)
	{
		key = "u",
		mods = "CMD|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("fetch-remote-worktree", window, pane)
		end),
	},
	-- Clone/Import a GitHub repo (I for Import)
	{
		key = "i",
		mods = "CMD|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("clone-github-repo", window, pane)
		end),
	},
	-- Codex (cx) - high reasoning, no approval, full access
	{
		key = "x",
		mods = "CMD|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("open-codex", window, pane)
		end),
	},
	-- Claude Code (cc) - dangerous bypass permissions
	{
		key = "c",
		mods = "CMD|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("open-claude", window, pane)
		end),
	},

	-- Workspace switching (quick access to recent worktrees)
	{ key = "[", mods = "CMD|SHIFT", action = act.SwitchWorkspaceRelative(-1) },
	{ key = "]", mods = "CMD|SHIFT", action = act.SwitchWorkspaceRelative(1) },

	-- Quick-switch to active AI sessions (Ctrl+1/2/3 matches status bar order)
	{
		key = "1",
		mods = "CTRL",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("switch-to-active-session", window, pane, 1)
		end),
	},
	{
		key = "2",
		mods = "CTRL",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("switch-to-active-session", window, pane, 2)
		end),
	},
	{
		key = "3",
		mods = "CTRL",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("switch-to-active-session", window, pane, 3)
		end),
	},

	-- Tab picker popup (mouse-clickable list of all tabs)
	{ key = "e", mods = "CMD", action = act.ShowTabNavigator },

	-- Tab management - NEW TAB SPAWNS IN CURRENT WORKTREE
	{
		key = "t",
		mods = "CMD",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("new-tab-in-worktree", window, pane)
		end),
	},
	{ key = "w", mods = "CMD", action = act.CloseCurrentTab({ confirm = true }) },
	{ key = "1", mods = "CMD", action = act.ActivateTab(0) },
	{ key = "2", mods = "CMD", action = act.ActivateTab(1) },
	{ key = "3", mods = "CMD", action = act.ActivateTab(2) },
	{ key = "4", mods = "CMD", action = act.ActivateTab(3) },
	{ key = "5", mods = "CMD", action = act.ActivateTab(4) },
	{ key = "6", mods = "CMD", action = act.ActivateTab(5) },
	{ key = "7", mods = "CMD", action = act.ActivateTab(6) },
	{ key = "8", mods = "CMD", action = act.ActivateTab(7) },
	{ key = "9", mods = "CMD", action = act.ActivateTab(-1) }, -- Last tab

	-- Pane splitting - SPAWNS IN CURRENT WORKTREE
	{
		key = "d",
		mods = "CMD",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("split-pane-in-worktree", window, pane, "horizontal")
		end),
	},
	{
		key = "d",
		mods = "CMD|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			wezterm.emit("split-pane-in-worktree", window, pane, "vertical")
		end),
	},

	-- Pane navigation
	{ key = "[", mods = "CMD", action = act.ActivatePaneDirection("Prev") },
	{ key = "]", mods = "CMD", action = act.ActivatePaneDirection("Next") },
	{ key = "h", mods = "CMD|ALT", action = act.ActivatePaneDirection("Left") },
	{ key = "l", mods = "CMD|ALT", action = act.ActivatePaneDirection("Right") },
	{ key = "k", mods = "CMD|ALT", action = act.ActivatePaneDirection("Up") },
	{ key = "j", mods = "CMD|ALT", action = act.ActivatePaneDirection("Down") },

	-- Zoom pane
	{ key = "z", mods = "CMD", action = act.TogglePaneZoomState },

	-- Connect to devbox (master branch / project root)
	{
		key = "Enter",
		mods = "CMD|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			-- This creates/switches to the "master" workspace
			wezterm.emit("switch-worktree", window, pane, "(here)", "master")
		end),
	},

	-- Copy mode (like tmux)
	{ key = "[", mods = "LEADER", action = act.ActivateCopyMode },

	-- Quick actions
	{ key = "r", mods = "CMD|SHIFT", action = act.ReloadConfiguration },
	{ key = "p", mods = "CMD|SHIFT", action = act.ActivateCommandPalette },
	{ key = "f", mods = "CTRL|CMD", action = act.ToggleFullScreen }, -- macOS standard fullscreen

	-- Layout: Add side panes (worktree list + dashboard)
	{
		key = "l",
		mods = "CMD|SHIFT",
		action = wezterm.action_callback(function(window, pane)
			local path = get_current_worktree_path(window)
			-- Split left for worktree list
			pane:split({
				direction = "Left",
				size = 0.15,
				args = { "ssh", "-t", "devbox", "cd " .. path .. " && watch -n3 -c 'workmux list'" },
			})
			-- Split right for dashboard
			pane:split({
				direction = "Right",
				size = 0.25,
				args = { "ssh", "-t", "devbox", "zsh -lc 'cd " .. path .. " && workmux dashboard'" },
			})
		end),
	},

	-- Local terminal (escape hatch)
	{
		key = "t",
		mods = "CMD|SHIFT",
		action = act.SpawnTab("DefaultDomain"),
	},
}

-- ============================================================================
-- MOUSE BINDINGS
-- ============================================================================
config.mouse_bindings = {
	-- Right-click paste
	{
		event = { Down = { streak = 1, button = "Right" } },
		mods = "NONE",
		action = act.PasteFrom("Clipboard"),
	},
	-- Cmd+click to open links
	{
		event = { Up = { streak = 1, button = "Left" } },
		mods = "CMD",
		action = act.OpenLinkAtMouseCursor,
	},
}

-- Additional mouse bindings for tab bar clicks
-- We'll use the tab-bar-specific mouse handling
wezterm.on("augment-command-palette", function(window, pane)
	-- This gives us access to add commands that can reference status bar data
	return {}
end)

-- Tab bar mouse handling - detect clicks on left status area
-- This uses format-tab-title to add clickable elements
local tab_bar_mouse_enabled = true

-- ============================================================================
-- MISC
-- ============================================================================
config.scrollback_lines = 10000
config.enable_scroll_bar = false
config.check_for_updates = true
config.automatically_reload_config = true

-- Bell
config.audible_bell = "Disabled"
config.visual_bell = {
	fade_in_duration_ms = 75,
	fade_out_duration_ms = 75,
	target = "CursorColor",
}

-- Cursor
config.default_cursor_style = "BlinkingBar"
config.cursor_blink_rate = 500

return config
