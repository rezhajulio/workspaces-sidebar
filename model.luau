--!strict
-- Sidebar pane ownership, memoized reads, health logic (dedup, auto-close, tab flags).

local TITLE = "Workspaces"

local model = {}

-- Per-cycle cache; window.luau invalidates at each cycle start / mutation
local cache_panes: { number } = {}
local cache_valid = false

function model.invalidate()
	cache_valid = false
end

-- One canvas:list per cycle; every is_mine/tab_has_sidebar call hits the cache
function model.mine(cx: WindowCx): { number }
	if cache_valid then
		return cache_panes
	end
	local out = {}
	for _, c in cx.canvas:list() do
		if c.owner == tern.plugin.id and c.title == TITLE then
			if cx.session:pane(c.pane) ~= nil then
				table.insert(out, c.pane)
			end
		end
	end
	cache_panes = out
	return out
end

function model.is_mine(cx: WindowCx, pane_id: number): boolean
	for _, p in model.mine(cx) do
		if p == pane_id then
			return true
		end
	end
	return false
end

-- Checks canvas list AND the tab layout tree (prevents duplicate opens on race)
function model.tab_has_sidebar(cx: WindowCx, tab_id: number): (boolean, number?)
	for _, pane in model.mine(cx) do
		if cx.session:tab_of(pane) == tab_id then
			return true, pane
		end
	end

	local l = cx.session:layout(tab_id)
	if l and l.root then
		local function scan(tree: any): number?
			if not tree then
				return nil
			end
			if tree.pane then
				local pinfo = cx.session:pane(tree.pane)
				if pinfo and (pinfo.title == TITLE or model.is_mine(cx, tree.pane)) then
					return tree.pane
				end
			end
			return scan(tree[1]) or scan(tree[2])
		end
		local found = scan(l.root)
		if found then
			return true, found
		end
	end

	return false, nil
end

-- Closes accidental duplicate sidebar panes in the same tab
function model.deduplicate_sidebars(cx: WindowCx)
	local seen_tab: { [number]: number } = {}
	for _, pane in model.mine(cx) do
		local tab = cx.session:tab_of(pane)
		if tab then
			if seen_tab[tab] then
				cx.layout:close(pane)
				model.invalidate()
			else
				seen_tab[tab] = pane
			end
		end
	end
end

-- Ctrl+D support: a tab holding ONLY the sidebar gets it closed, so Tern closes the tab.
-- Toggleable via kv "auto_close_empty_tabs" (default ON).
function model.auto_close_empty_tabs(cx: WindowCx)
	local enabled = tern.kv.get("auto_close_empty_tabs")
	if enabled == false then
		return
	end

	for _, tab in cx.session:tabs() do
		local l = cx.session:layout(tab.id)
		if l and l.root then
			local total = 0
			local sidebar_count = 0
			local sidebar_pane: number? = nil

			local function count_leaves(tree: any)
				if not tree then
					return
				end
				if tree.pane then
					total += 1
					if model.is_mine(cx, tree.pane) then
						sidebar_count += 1
						sidebar_pane = tree.pane
					end
				end
				count_leaves(tree[1])
				count_leaves(tree[2])
			end

			count_leaves(l.root)

			if total > 0 and total == sidebar_count and sidebar_pane then
				cx.layout:close(sidebar_pane)
				model.invalidate()
			end
		end
	end
end

export type TabFlags = {
	busy: boolean,
	waiting: boolean,
	alert: boolean,
	is_agent: boolean,
}

-- Per-tab status badges from panes + agent states (keyed by AgentBlock.pane, NOT .agent)
function model.collect_tab_flags(cx: WindowCx): { [number]: TabFlags }
	local out: { [number]: TabFlags } = {}
	local agent_map: { [number]: string } = {}
	local ok_ag, agents = pcall(function() return cx.agents:list() end)
	if ok_ag and agents then
		for _, a in agents do
			if a.pane then
				agent_map[a.pane] = a.state
			end
		end
	end

	local ok_p, panes = pcall(function() return cx.session:panes() end)
	if ok_p and panes then
		for _, p in panes do
			if p.tab then
				local tf = out[p.tab]
				if not tf then
					tf = { busy = false, waiting = false, alert = false, is_agent = false }
					out[p.tab] = tf
				end
				local ag_state = agent_map[p.pane]
				if p.busy or p.running ~= nil or ag_state == "working" then
					tf.busy = true
				end
				if ag_state == "waiting_input" then
					tf.waiting = true
				end
				if p.alert or (p.last and p.last.status ~= 0) then
					tf.alert = true
				end
				if p.kind == "agent" then
					tf.is_agent = true
				end
			end
		end
	end
	return out
end

-- Accordion fold state per session (kv "fold_<id>"); default: current expanded, rest collapsed
function model.is_session_collapsed(s_id: number, is_current: boolean): boolean
	local custom = tern.kv.get("fold_" .. s_id)
	if custom ~= nil then
		return custom == true
	end
	return not is_current
end

-- Re-applies persisted tab colors (kv "tab_color_<id>"); no-op when tags disabled
function model.restore_tab_colors(cx: WindowCx)
	if tern.kv.get("color_tags_enabled") == false then
		return
	end
	for _, t in cx.session:tabs() do
		local saved = tern.kv.get("tab_color_" .. t.id)
		if saved ~= nil and t.color ~= saved then
			pcall(function()
				cx.layout:color_tab(t.id, saved)
			end)
		end
	end
end

return model
