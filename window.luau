--!strict
-- Pinned Workspaces Sidebar for Tern — wiring only.
-- Logic lives in format.luau / model.luau / layout.luau / view.luau.
-- In Tern, canvas panes belong to a tab split tree; this plugin mounts the sidebar
-- canvas on the left of the active tab, syncs widths across tabs, and lists
-- sessions (= workspaces) with their tabs, badges and controls.

local format = require("./format")
local model = require("./model")
local layout_mod = require("./layout")
local view_mod = require("./view")

local TITLE = "Workspaces"
local HOME = tern.getenv("HOME") or ""
local opening = false
local last_fp: string?
local tab_opening_times: { [number]: number } = {}

local function mine(cx: WindowCx): { number }
	return model.mine(cx)
end

local function refresh(cx: WindowCx)
	local panes = mine(cx)
	if #panes == 0 then
		return
	end
	local fp = view_mod.fingerprint(cx)
	if fp == last_fp then
		return
	end
	last_fp = fp
	local ok, v = pcall(view_mod.build, cx)
	if ok and v then
		for _, pane in panes do
			cx.canvas:set(pane, { view = v })
		end
	end
end

local function open(cx: WindowCx, tab_id: number, focus: boolean)
	if opening then
		return
	end
	local now = tern.now()
	local last_time = tab_opening_times[tab_id]
	if last_time and (now - last_time) < 1200 then
		return
	end
	tab_opening_times[tab_id] = now

	opening = true
	pcall(function()
		local active_tab = if cx.session:focused() then cx.session:tab_of(cx.session:focused()) else nil
		local target = layout_mod.find_tab_terminal(cx, model.is_mine, tab_id) or cx.session:focused()
		local pane, _err = cx.canvas:open({
			title = TITLE,
			about = "Workspaces Sidebar. Click workspace to switch, tab to focus, ✎ to rename, ✕ to close.",
			view = view_mod.build(cx),
			how = "beside",
			focus = focus,
		})
		if pane then
			model.invalidate()
			if active_tab == tab_id and target then
				cx.layout:move(pane, target, "left", { focus = false })
				layout_mod.match_ratio(cx, model.is_mine, pane, tab_id, layout_mod.target_ratio())
			else
				cx.layout:move_to_tab(pane, tab_id, { focus = false })
			end
		end
	end)
	opening = false
end

-- Ensures active tab in shown workspace has the sidebar mounted and synced
local function ensure_pinned(cx: WindowCx)
	if not tern.kv.get("pinned") then
		return
	end
	model.deduplicate_sidebars(cx)
	model.auto_close_empty_tabs(cx)
	model.restore_tab_colors(cx)

	local cur_session = cx.sessions:current().id
	local tr = layout_mod.target_ratio()
	local focused = cx.session:focused()
	local active_tab = if focused then cx.session:tab_of(focused) else nil

	-- Fallback if focused is nil: pick first tab in current session and focus its terminal
	if not active_tab then
		for _, t in cx.session:tabs() do
			if t.session == cur_session then
				active_tab = t.id
				local term = layout_mod.find_tab_terminal(cx, model.is_mine, t.id)
				if term then
					cx.layout:focus(term)
				end
				break
			end
		end
	end

	if active_tab then
		local has, pane = model.tab_has_sidebar(cx, active_tab)
		if not has then
			open(cx, active_tab, false)
		elseif pane then
			local l = cx.session:layout(active_tab)
			if l and l.root and l.root.ratio then
				-- Reposition sidebar to left if not already there
				if l.root[1] and not model.is_mine(cx, l.root[1].pane or 0) then
					local target = layout_mod.find_tab_terminal(cx, model.is_mine, active_tab)
					if target then
						cx.layout:move(pane, target, "left", { focus = false })
						model.invalidate()
					end
				end
				local cur_r = l.root.ratio
				local prev_known = layout_mod.known_ratio(active_tab)
				if prev_known and math.abs(cur_r - prev_known) > 0.015 and cur_r >= 0.05 and cur_r <= 0.60 then
					tern.kv.set("sidebar_ratio", cur_r)
					tr = cur_r
				end
				layout_mod.set_known_ratio(active_tab, cur_r)

				if math.abs(cur_r - tr) > 0.015 then
					layout_mod.match_ratio(cx, model.is_mine, pane, active_tab, tr)
				end
			end
		end
	end
end

-- Context inheritance helpers
local function current_context(cx: WindowCx): (string, string)
	local focused = cx.session:focused()
	local pinfo = if focused then cx.session:pane(focused) else nil
	local cwd = if pinfo and pinfo.cwd and pinfo.cwd ~= "" then pinfo.cwd else HOME
	local name = format.smart(cwd)
	if name == "~" or name == "terminal" then
		name = "workspace"
	end

	local existing: { [string]: boolean } = {}
	for _, s in cx.sessions:list() do
		existing[string.lower(s.name)] = true
	end
	if existing[string.lower(name)] then
		local idx = 2
		while existing[string.lower(name .. " " .. idx)] do
			idx += 1
		end
		name = name .. " " .. idx
	end

	return cwd, name
end

local function get_session_cwd(cx: WindowCx, session_id: number): string
	for _, t in cx.session:tabs() do
		if t.session == session_id and t.cwd and t.cwd ~= "" then
			return t.cwd
		end
	end
	return HOME
end

local function step(cx: WindowCx, d: number)
	local list = cx.sessions:list()
	for i, s in list do
		if s.current then
			cx.sessions:switch(list[(i - 1 + d) % #list + 1].id)
			return
		end
	end
end

-- Attention jump across all sessions
local function find_attention_tab(cx: WindowCx): (number?, number?)
	local agent_map: { [number]: string } = {}
	local ok_ag, agents = pcall(function() return cx.agents:list() end)
	if ok_ag and agents then
		for _, a in agents do
			if a.pane and a.state == "waiting_input" then
				agent_map[a.pane] = a.state
			end
		end
	end

	for _, t in cx.session:tabs() do
		local l = cx.session:layout(t.id)
		if l and l.root then
			local function scan(tree: any): number?
				if not tree then return nil end
				if tree.pane then
					local pinfo = cx.session:pane(tree.pane)
					if pinfo and not model.is_mine(cx, tree.pane) then
						local ag_state = agent_map[tree.pane]
						if ag_state == "waiting_input" or pinfo.alert or (pinfo.last and pinfo.last.status ~= 0) then
							return tree.pane
						end
					end
				end
				return scan(tree[1]) or scan(tree[2])
			end
			local target = scan(l.root)
			if target then
				return t.id, target
			end
		end
	end
	return nil, nil
end

tern.command({
	id = "toggle",
	title = "Workspaces: toggle sidebar",
	icon = "sidebar",
	keys = { "cmd+alt+shift+b" },
	run = function(cx)
		local panes = mine(cx)
		if tern.kv.get("pinned") or #panes > 0 then
			tern.kv.set("pinned", nil)
			for _, p in panes do
				cx.layout:close(p)
			end
			model.invalidate()
		else
			tern.kv.set("pinned", true)
			opening = false
			last_fp = nil
			ensure_pinned(cx)
			refresh(cx)
		end
	end,
})
tern.command({ id = "new", title = "Workspaces: new", icon = "plus", run = function(cx)
	local cwd, name = current_context(cx)
	cx.sessions:create({ name = name, cwd = cwd })
	last_fp = nil
	pcall(ensure_pinned, cx)
	pcall(refresh, cx)
end })
tern.command({
	id = "rename",
	title = "Workspaces: rename workspace",
	icon = "pencil",
	run = function(cx)
		cx:command("rename_session")
	end,
})
tern.command({
	id = "toggle_path_style",
	title = "Workspaces: toggle path style (smart / fish)",
	icon = "text",
	run = function(cx)
		local cur = tern.kv.get("path_style") or "smart"
		local next_style = if cur == "smart" then "fish" else "smart"
		tern.kv.set("path_style", next_style)
		cx:toast("info", "Path style: " .. next_style)
		last_fp = nil
		refresh(cx)
	end,
})
tern.command({
	id = "cycle_tab_color",
	title = "Workspaces: cycle active tab color",
	icon = "palette",
	keys = { "cmd+alt+shift+c" },
	run = function(cx)
		local focused = cx.session:focused()
		local tab_id = if focused then cx.session:tab_of(focused) else nil
		if tab_id then
			local cur_color: TabColor? = nil
			for _, t in cx.session:tabs() do
				if t.id == tab_id then
					cur_color = t.color or tern.kv.get("tab_color_" .. t.id)
					break
				end
			end
			local next_c = view_mod.next_tab_color(cur_color)
			cx.layout:color_tab(tab_id, next_c)
			tern.kv.set("tab_color_" .. tab_id, next_c)
			cx:toast("info", "Tab color: " .. (next_c or "none"))
			last_fp = nil
			refresh(cx)
		end
	end,
})
tern.command({
	id = "toggle_color_tags",
	title = "Workspaces: toggle color tags",
	icon = "palette",
	run = function(cx)
		local cur = tern.kv.get("color_tags_enabled")
		local next_val = if cur == false then true else false
		tern.kv.set("color_tags_enabled", next_val)
		cx:toast("info", "Color tags: " .. (if next_val then "ON" else "OFF"))
		if not next_val then
			for _, t in cx.session:tabs() do
				pcall(function()
					cx.layout:color_tab(t.id, nil)
				end)
			end
		else
			for _, t in cx.session:tabs() do
				local saved = tern.kv.get("tab_color_" .. t.id)
				if saved then
					pcall(function()
						cx.layout:color_tab(t.id, saved)
					end)
				end
			end
		end
		last_fp = nil
		refresh(cx)
	end,
})
tern.command({
	id = "toggle_color_labels",
	title = "Workspaces: toggle color tag labels",
	icon = "text",
	run = function(cx)
		local cur = tern.kv.get("color_labels_enabled")
		local next_val = if cur == false then true else false
		tern.kv.set("color_labels_enabled", next_val)
		cx:toast("info", "Color tag labels: " .. (if next_val then "ON" else "OFF"))
		last_fp = nil
		refresh(cx)
	end,
})
tern.command({
	id = "toggle_auto_close_empty",
	title = "Workspaces: toggle auto-close empty tabs",
	icon = "x",
	run = function(cx)
		local cur = tern.kv.get("auto_close_empty_tabs")
		if cur == nil then
			cur = true
		end
		local next_val = not cur
		tern.kv.set("auto_close_empty_tabs", next_val)
		cx:toast("info", "Auto-close empty tabs: " .. (if next_val then "ON" else "OFF"))
		if next_val then
			model.auto_close_empty_tabs(cx)
		end
	end,
})
tern.command({ id = "next", title = "Workspaces: next", keys = { "cmd+alt+shift+]" }, run = function(cx) step(cx, 1) end })
tern.command({ id = "prev", title = "Workspaces: previous", keys = { "cmd+alt+shift+[" }, run = function(cx) step(cx, -1) end })

-- Direct workspace jumps Cmd+Alt+1..9 (avoid terminal ctrl+alt preset conflicts)
for i = 1, 9 do
	tern.command({
		id = "goto_ws_" .. i,
		title = "Workspaces: go to " .. i,
		run = function(cx)
			local list = cx.sessions:list()
			if #list >= i then
				cx.sessions:switch(list[i].id)
				last_fp = nil
				refresh(cx)
			end
		end,
	})
end

-- Bind the chords through tern.bind at load (runs once per plugin VM start)
for i = 1, 9 do
	tern.bind("cmd+alt+" .. i, "plugin.workspaces-sidebar.goto_ws_" .. i)
end

-- Esc cancels move mode (guarded: only acts when moving_tab is set)
tern.bind("esc", function(cx: WindowCx)
	if tern.kv.get("moving_tab") then
		tern.kv.set("moving_tab", nil)
		cx:toast("info", "Move cancelled")
		last_fp = nil
		refresh(cx)
	end
end)

-- Attention jump command
tern.command({
	id = "attention",
	title = "Workspaces: next needing attention",
	icon = "bell",
	keys = { "cmd+alt+shift+a" },
	run = function(cx)
		local tab_id, pane = find_attention_tab(cx)
		if tab_id and pane then
			local target_tab: TabInfo? = nil
			for _, t in cx.session:tabs() do
				if t.id == tab_id then
					target_tab = t
					break
				end
			end
			if target_tab then
				local cur_s = cx.sessions:current().id
				if target_tab.session ~= cur_s then
					cx.sessions:switch(target_tab.session)
				end
				cx.layout:focus(pane)
				cx:toast("info", "Jumped to tab needing attention")
			end
		else
			cx:toast("info", "All tasks clear")
		end
	end,
})

-- Native chrome status line segment (pure formatter, reads cached snapshot)
local chrome_snapshot: ManagedSession? = nil

tern.chrome.status(function(_pane: StatusPaneInfo): { StatusSegment }?
	if not chrome_snapshot then
		return nil
	end
	local seg: StatusSegment = {
		text = " ▸ " .. chrome_snapshot.name,
		icon = "sidebar",
		tone = "accent",
		command = "plugin.workspaces-sidebar.toggle",
	}
	return { seg }
end)

tern.on("canvas_action", function(ev: CanvasAction, cx: WindowCx): boolean?
	if ev.owner ~= tern.plugin.id then
		return nil
	end
	local kind, id = string.match(ev.act, "^([%a_]+):?(%d*)$")
	local n = tonumber(id)

	-- Cancel move mode via badge click
	if kind == "cancel_move" then
		tern.kv.set("moving_tab", nil)
		last_fp = nil
		refresh(cx)
		return true
	end

	local cur_focused = cx.session:focused()
	local cur_tab = if cur_focused then cx.session:tab_of(cur_focused) else nil
	local cur_term = if cur_tab then layout_mod.find_tab_terminal(cx, model.is_mine, cur_tab) else nil

	-- Modifier-click reorder on tab rows (drag-free alternative)
	-- shift-click tab row = move up, alt-click = move down
	if kind == "tab" and n and ev.mods then
		local held: { [string]: boolean } = {}
		for _, m in ev.mods do
			held[m] = true
		end
		local my_pos: number? = nil
		for _, t in cx.session:tabs() do
			if t.id == n then
				my_pos = t.position
				break
			end
		end
		if my_pos then
			if held["shift"] and my_pos > 1 then
				cx.layout:order_tab(n, my_pos - 1)
				last_fp = nil
				refresh(cx)
				return true
			elseif held["alt"] then
				cx.layout:order_tab(n, my_pos + 1)
				last_fp = nil
				refresh(cx)
				return true
			end
		end
	end

	if kind == "ws" and n then
		for _, s in cx.sessions:list() do
			if s.id == n then
				cx.sessions:switch(n)
				break
			end
		end
	elseif kind == "fold" and n then
		local cur_s = cx.sessions:current().id
		local is_curr = (n == cur_s)
		local cur_collapsed = model.is_session_collapsed(n, is_curr)
		tern.kv.set("fold_" .. n, not cur_collapsed)
	elseif kind == "toggle_lock" and n then
		-- Interactive lock toggle
		for _, s in cx.sessions:list() do
			if s.id == n then
				if s.locked then
					cx.sessions:unlock(n)
					cx:toast("info", s.name .. " unlocked")
				else
					cx.sessions:lock(n)
					cx:toast("info", s.name .. " locked")
				end
				break
			end
		end
	elseif kind == "color_tab" and n then
		-- Cycle and persist tab color tag
		local cur_c: TabColor? = nil
		for _, t in cx.session:tabs() do
			if t.id == n then
				cur_c = t.color or tern.kv.get("tab_color_" .. n)
				break
			end
		end
		local next_c = view_mod.next_tab_color(cur_c)
		cx.layout:color_tab(n, next_c)
		tern.kv.set("tab_color_" .. n, next_c)
	elseif kind == "tab_up" and n then
		for _, t in cx.session:tabs() do
			if t.id == n and t.position > 1 then
				cx.layout:order_tab(n, t.position - 1)
				break
			end
		end
	elseif kind == "tab_down" and n then
		for _, t in cx.session:tabs() do
			if t.id == n then
				cx.layout:order_tab(n, t.position + 1)
				break
			end
		end
	elseif kind == "move" and n then
		-- Enter move mode for this tab
		tern.kv.set("moving_tab", n)
		cx:toast("info", "Pick a workspace to move this tab to")
	elseif kind == "movehere" and n then
		-- Move pending tab panes into this workspace
		local moving = tern.kv.get("moving_tab")
		if moving then
			local cur_s = cx.sessions:current().id
			if n ~= cur_s then
				cx.sessions:switch(n)
			end
			local l = cx.session:layout(moving)
			if l and l.root then
				local panes_to_move = {}
				local function collect(t: TabTree?)
					if not t then return end
					if t.pane and not model.is_mine(cx, t.pane) then
						table.insert(panes_to_move, t.pane)
					end
					collect(t[1])
					collect(t[2])
				end
				collect(l.root)
				for _, p in panes_to_move do
					cx.layout:move_to_new_tab(p, n, { focus = false })
				end
			end
			tern.kv.set("moving_tab", nil)
		end
	elseif kind == "ren" and n then
		if cx.sessions:current().id ~= n then
			cx.sessions:switch(n)
		end
		cx:command("rename_session")
	elseif kind == "close" and n then
		for _, s in cx.sessions:list() do
			if s.id == n and not s.locked then
				cx.sessions:close(n)
				break
			end
		end
	elseif kind == "close_tab" and n then
		layout_mod.close_tab(cx, n)
	elseif kind == "new_tab" and n then
		-- Create tab in designated workspace
		local cur_s = cx.sessions:current().id
		if n ~= cur_s then
			cx.sessions:switch(n)
		end
		local cwd = get_session_cwd(cx, n)
		cx.layout:new_tab({ cwd = cwd }, { focus = true })
	elseif kind == "new" then
		-- Smart workspace creation with context inheritance
		local cwd, name = current_context(cx)
		cx.sessions:create({ name = name, cwd = cwd })
	elseif kind == "tab" and n then
		local target_tab: TabInfo? = nil
		for _, t in cx.session:tabs() do
			if t.id == n then
				target_tab = t
				break
			end
		end

		if target_tab then
			local cur_s = cx.sessions:current().id
			if target_tab.session ~= cur_s then
				cx.sessions:switch(target_tab.session)
			else
				if cur_term then
					cx.layout:focus(cur_term)
				end
			end
			local dest_term = layout_mod.find_tab_terminal(cx, model.is_mine, n) or target_tab.pane
			if dest_term then
				cx.layout:focus(dest_term)
			end
		end
	else
		return nil
	end

	model.invalidate()
	last_fp = nil
	refresh(cx)
	return true
end)

-- Single cache lifetime per poll cycle; caches invalidated on any mutation
local function poll(cx: WindowCx?)
	tern.timer(250, poll)
	if cx then
		model.invalidate() -- fresh read at cycle start
		pcall(model.auto_close_empty_tabs, cx)
		pcall(ensure_pinned, cx)

		-- Update the chrome snapshot for the pure status formatter
		local ok, cur = pcall(function() return cx.sessions:current() end)
		local new_name = if ok and cur then cur.name else nil
		if new_name and (not chrome_snapshot or chrome_snapshot.name ~= new_name) then
			chrome_snapshot = cur
			tern.chrome.refresh()
		end

		pcall(refresh, cx)
	end
end

tern.timer(100, poll)

tern.on("window_start", function(cx: WindowCx)
	last_fp = nil
	model.invalidate()
	pcall(ensure_pinned, cx)
	pcall(refresh, cx)
end)

tern.on("pane_closed", function(_ev: PaneEvent, cx: WindowCx)
	pcall(model.auto_close_empty_tabs, cx)
	last_fp = nil
	model.invalidate()
	pcall(refresh, cx)
end)

tern.on("tab_created", function(_ev: TabEvent, cx: WindowCx)
	last_fp = nil
	model.invalidate()
	pcall(ensure_pinned, cx)
	pcall(refresh, cx)
end)

tern.on("tab_closed", function(_ev: TabEvent, cx: WindowCx)
	last_fp = nil
	model.invalidate()
	pcall(ensure_pinned, cx)
	pcall(refresh, cx)
end)

tern.on("focus", function(ev: any, cx: WindowCx)
	local tab_id = ev and ev.tab
	if tab_id then
		local l = cx.session:layout(tab_id)
		if l and l.root and l.root[1] and l.root.ratio then
			local p = l.root[1].pane
			if p and model.is_mine(cx, p) then
				local cur_r = l.root.ratio
				local prev_known = layout_mod.known_ratio(tab_id)
				if prev_known and math.abs(cur_r - prev_known) > 0.015 and cur_r >= 0.05 and cur_r <= 0.60 then
					tern.kv.set("sidebar_ratio", cur_r)
				end
				layout_mod.set_known_ratio(tab_id, cur_r)
			end
		end
	end
	model.invalidate()
	pcall(model.auto_close_empty_tabs, cx)
	pcall(ensure_pinned, cx)
	pcall(refresh, cx)
end)
