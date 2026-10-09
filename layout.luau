--!strict
-- Sidebar geometry: ratio memory, divider sync, tab terminal/close ops.

local DEFAULT_RATIO = 0.16

local layout_mod = {}
local tab_known_ratios: { [number]: number } = {}

function layout_mod.target_ratio(): number
	local r = tern.kv.get("sidebar_ratio")
	if type(r) == "number" and r >= 0.05 and r <= 0.60 then
		return r
	end
	return DEFAULT_RATIO
end

-- Window VM exposes no cols; calibrate from observed resize deltas
function layout_mod.estimated_window_cols(): number
	local est = tern.kv.get("cols_est")
	if type(est) == "number" and est >= 40 and est <= 600 then
		return est
	end
	return 180
end

function layout_mod.calibrate_cols(cells: number, delta_ratio: number)
	if math.abs(delta_ratio) > 0.005 and math.abs(cells) > 0 then
		local est = math.floor(math.abs(cells / delta_ratio) + 0.5)
		if est >= 40 and est <= 600 then
			tern.kv.set("cols_est", est)
		end
	end
end

-- Snap a tab's sidebar split to target ratio; converges in ≤6 hops (max 3 in practice)
function layout_mod.match_ratio(
	cx: WindowCx,
	is_mine: (WindowCx, number) -> boolean,
	pane: number,
	tab_id: number,
	target: number
)
	local cols = layout_mod.estimated_window_cols()
	for _ = 1, 6 do
		local l = cx.session:layout(tab_id)
		if not l or not l.root or not l.root.ratio then
			break
		end
		local cur = l.root.ratio
		local diff = target - cur
		if math.abs(diff) < 0.015 then
			break
		end
		local cells = math.floor(diff * cols + (if diff > 0 then 0.5 else -0.5))
		if cells == 0 then
			break
		end
		local ok = cx.layout:resize(pane, "right", cells)
		if not ok then
			break
		end
		local l_after = cx.session:layout(tab_id)
		if l_after and l_after.root and l_after.root.ratio then
			local delta = l_after.root.ratio - cur
			layout_mod.calibrate_cols(cells, delta)
			cols = layout_mod.estimated_window_cols()
		end
	end
	local l_end = cx.session:layout(tab_id)
	if l_end and l_end.root and l_end.root.ratio then
		tab_known_ratios[tab_id] = l_end.root.ratio
	end
end

function layout_mod.known_ratio(tab_id: number): number?
	return tab_known_ratios[tab_id]
end

function layout_mod.set_known_ratio(tab_id: number, ratio: number)
	tab_known_ratios[tab_id] = ratio
end

-- The tab's non-sidebar pane (terminal/agent/file); nil when the tab is sidebar-only
function layout_mod.find_tab_terminal(cx: WindowCx, is_mine: (WindowCx, number) -> boolean, tab_id: number): number?
	local l = cx.session:layout(tab_id)
	if not l or not l.root then
		return nil
	end
	local function find_leaf(tree: TabTree?): number?
		if not tree then
			return nil
		end
		if tree.pane and not is_mine(cx, tree.pane) then
			return tree.pane
		end
		return find_leaf(tree[2]) or find_leaf(tree[1])
	end
	return find_leaf(l.root)
end

-- Close every pane in a tab (terminal + sidebar alike), destroying the tab
function layout_mod.close_tab(cx: WindowCx, tab_id: number)
	local l = cx.session:layout(tab_id)
	if not l or not l.root then
		return
	end
	local to_close = {}
	local function collect(t: TabTree?)
		if not t then
			return
		end
		if t.pane then
			table.insert(to_close, t.pane)
		end
		collect(t[1])
		collect(t[2])
	end
	collect(l.root)
	for _, pane in to_close do
		cx.layout:close(pane)
	end
end

return layout_mod
