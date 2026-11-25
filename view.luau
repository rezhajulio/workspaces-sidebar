--!strict
-- Canvas tree builder + change fingerprint (what triggers a redraw).

local format = require("./format")
local model = require("./model")
local layout_mod = require("./layout")

local view_mod = {}

local TAB_COLORS: { TabColor } = {
	"blue", "green", "yellow", "orange", "red", "purple", "teal", "pink"
}

local COLOR_LABELS: { [string]: { glyph: string, tone: string } } = {
	blue = { glyph = "🔵", tone = "accent" },
	green = { glyph = "🟢", tone = "accent" },
	yellow = { glyph = "🟡", tone = "warn" },
	orange = { glyph = "🟠", tone = "warn" },
	red = { glyph = "🔴", tone = "error" },
	purple = { glyph = "🟣", tone = "accent" },
	teal = { glyph = "🩵", tone = "accent" },
	pink = { glyph = "🩷", tone = "muted" },
}

function view_mod.next_tab_color(cur: TabColor?): TabColor?
	if not cur then
		return "blue"
	end
	for i, c in TAB_COLORS do
		if c == cur then
			if i < #TAB_COLORS then
				return TAB_COLORS[i + 1]
			else
				return nil
			end
		end
	end
	return "blue"
end

function view_mod.fingerprint(cx: WindowCx): string
	local parts = {}
	local focused = cx.session:focused()
	local active_tab = if focused then cx.session:tab_of(focused) else nil
	local style = tern.kv.get("path_style") or "smart"
	local tabs = cx.session:tabs()
	table.insert(parts, "style:" .. style)
	table.insert(parts, "tags:" .. (if tern.kv.get("color_tags_enabled") == false then "0" else "1"))
	table.insert(parts, "labels:" .. (if tern.kv.get("color_labels_enabled") == false then "0" else "1"))
	table.insert(parts, "buttons:" .. (if tern.kv.get("action_buttons_enabled") == false then "0" else "1"))
	table.insert(parts, "focus:" .. (active_tab or 0))
	table.insert(parts, "ntabs:" .. #tabs)

	local tab_flags = model.collect_tab_flags(cx)
	local filt = tern.kv.get("tab_filter") or "all"
	table.insert(parts, "filter:" .. filt)

	for _, s in cx.sessions:list() do
		local collapsed = model.is_session_collapsed(s.id, s.current)
		local ntabs = if type(s.tabs) == "table" then #s.tabs else tostring(s.tabs)
		table.insert(parts, s.id .. ":" .. (if s.current then "1" else "0") .. ":" .. (if s.locked then "L" else "U") .. ":" .. (if collapsed then "C" else "E") .. ":" .. s.name .. ":" .. ntabs)
	end
	for _, t in tabs do
		local tf = tab_flags[t.id]
		local flag_str = ""
		if tf then
			flag_str = (if tf.busy then "B" else "") .. (if tf.waiting then "W" else "") .. (if tf.alert then "A" else "")
		end
		local col = t.color or tern.kv.get("tab_color_" .. t.id) or ""
		local dname = format.tab_display_name(t, cx)
		table.insert(parts, "t" .. t.id .. ":" .. col .. ":" .. flag_str .. ":" .. dname .. ":" .. (t.cwd or ""))
	end
	return table.concat(parts, "|")
end

-- Tern 0.9.35 layout motion: descendants carrying a unique `motionKey` glide to
-- their new places inside a container with `transition = "layout"`.
local function motion_key(node: Node, key: string): Node
	local props: { [string]: any } = node.p or {}
	props.motionKey = key
	node.p = props
	return node
end

function view_mod.build(cx: WindowCx): Node
	local items: { Node } = {}
	local tabs = cx.session:tabs()
	local sessions = cx.sessions:list()
	local focused_pane = cx.session:focused()
	local current_tab_id = if focused_pane then cx.session:tab_of(focused_pane) else nil
	local tab_flags = model.collect_tab_flags(cx)
	local show_buttons = (tern.kv.get("action_buttons_enabled") ~= false)

	for _, s in sessions do
		local collapsed = model.is_session_collapsed(s.id, s.current)
		local chevron = if collapsed then "▶ " else "▼ "

		local session_tabs = {}
		local ws_busy = 0
		local ws_waiting = 0
		for _, t in tabs do
			if t.session == s.id then
				table.insert(session_tabs, t)
				local f = tab_flags[t.id]
				if f then
					if f.busy then ws_busy += 1 end
					if f.waiting then ws_waiting += 1 end
				end
			end
		end

		-- Filter chips stashed for now; pass all tabs through
		local shown_tabs = {}
		for _, t in session_tabs do
			table.insert(shown_tabs, t)
		end

		local header_cells: { Node } = {
			-- Single text node: chevron + name wrap together (prevents vertical text wrap)
			tern.ui.node("text", {
				key = "ws_txt_" .. s.id,
				text = chevron .. s.name,
				actions = { click = "ws:" .. s.id },
			}),
		}

		if ws_waiting > 0 then
			table.insert(header_cells, tern.ui.node("badge", {
				key = "ws_wait_" .. s.id,
				text = ws_waiting .. "?",
				tone = "warn",
				actions = { click = "ws:" .. s.id },
			}))
		end
		if ws_busy > 0 then
			table.insert(header_cells, tern.ui.node("badge", {
				key = "ws_busy_" .. s.id,
				text = ws_busy .. "◐",
				tone = "accent",
				actions = { click = "ws:" .. s.id },
			}))
		end

		if collapsed then
			table.insert(header_cells, tern.ui.node("badge", {
				key = "ws_cnt_" .. s.id,
				text = tostring(#session_tabs),
				tone = "muted",
				actions = { click = "fold:" .. s.id },
			}))
		end

		if show_buttons then
			table.insert(header_cells, tern.ui.button("+", {
				key = "ws_add_" .. s.id,
				variant = "quiet",
				size = "sm",
				title = "New tab in workspace directory",
				actions = { click = "new_tab:" .. s.id },
			}))

			table.insert(header_cells, tern.ui.button("✎", {
				key = "ws_ren_" .. s.id,
				variant = "quiet",
				size = "sm",
				title = "Rename workspace",
				actions = { click = "ren:" .. s.id },
			}))

			-- Interactive lock toggle
			if s.locked then
				table.insert(header_cells, tern.ui.button("🔒", {
					key = "ws_lock_" .. s.id,
					variant = "quiet",
					size = "sm",
					title = "Locked: click to unlock",
					actions = { click = "toggle_lock:" .. s.id },
				}))
			else
				table.insert(header_cells, tern.ui.button("🔓", {
					key = "ws_lock_" .. s.id,
					variant = "quiet",
					size = "sm",
					title = "Unlocked: click to lock",
					actions = { click = "toggle_lock:" .. s.id },
				}))
				if #sessions > 1 then
					table.insert(header_cells, tern.ui.button("✕", {
						key = "ws_del_" .. s.id,
						variant = "quiet",
						size = "sm",
						title = "Close workspace",
						actions = { click = "close:" .. s.id },
					}))
				end
			end
		end

		-- Header row is a drop target: a tab dragged from any workspace tab strip lands here.
		local header_row = tern.ui.row(header_cells)
		local head_p: { [string]: any } = header_row.p or {}
		head_p.key = "ws_head_" .. s.id
		head_p.drop = "move_tab_to_ws=" .. s.id
		head_p.motionKey = "ws_" .. s.id
		header_row.p = head_p
		table.insert(items, header_row)

		if not collapsed then
			local tab_rows: { Node } = {}
			for i, t in shown_tabs do
				local branch = if i == #shown_tabs then "  └─ " else "  ├─ "
				local is_active = (t.id == current_tab_id)
				local dot_glyph = if is_active then "● " else "○ "

				local effective_color = t.color or tern.kv.get("tab_color_" .. t.id)
				local color_info = if effective_color then COLOR_LABELS[effective_color] else nil

				local display_name = format.tab_display_name(t, cx)

				local tab_cells: { Node } = {
					-- Single text node: branch + dot + name wrap together in narrow sidebars
					tern.ui.node("text", {
						key = "tab_" .. t.id,
						text = branch .. dot_glyph .. display_name,
						actions = { click = "tab:" .. t.id },
					}),
				}

				-- Color tag badge, gated by toggles, hidden during move mode
				local tags_enabled = tern.kv.get("color_tags_enabled")
				local show_tag = tags_enabled ~= false
				local labels_enabled = tern.kv.get("color_labels_enabled")
				local show_label = labels_enabled ~= false
				if show_tag and effective_color and color_info then
					local tag_text = if show_label then color_info.glyph .. " " .. effective_color else color_info.glyph
					table.insert(tab_cells, tern.ui.node("badge", {
						key = "tab_col_" .. t.id,
						text = tag_text,
						tone = color_info.tone,
						actions = { click = "color_tab:" .. t.id },
					}))
				elseif show_tag then
					table.insert(tab_cells, tern.ui.node("badge", {
						key = "tab_col_" .. t.id,
						text = "🏷",
						tone = "muted",
						actions = { click = "color_tab:" .. t.id },
					}))
				end

				local tf = tab_flags[t.id]
				if tf then
					if tf.waiting then
						table.insert(tab_cells, tern.ui.node("badge", {
							key = "tab_wait_" .. t.id,
							text = "?",
							tone = "warn",
							actions = { click = "tab:" .. t.id },
						}))
					elseif tf.busy then
						table.insert(tab_cells, tern.ui.node("badge", {
							key = "tab_busy_" .. t.id,
							text = "◐",
							tone = "accent",
							actions = { click = "tab:" .. t.id },
						}))
					elseif tf.alert then
						table.insert(tab_cells, tern.ui.node("badge", {
							key = "tab_alert_" .. t.id,
							text = "!",
							tone = "error",
							actions = { click = "tab:" .. t.id },
						}))
					elseif tf.is_agent then
						table.insert(tab_cells, tern.ui.node("badge", {
							key = "tab_agent_" .. t.id,
							text = "◆",
							tone = "muted",
							actions = { click = "tab:" .. t.id },
						}))
					end
				end

				if show_buttons and #shown_tabs > 1 then
					table.insert(tab_cells, tern.ui.button("✕", {
						key = "tab_del_" .. t.id,
						variant = "quiet",
						size = "sm",
						title = "Close tab",
						actions = { click = "close_tab:" .. t.id },
					}))
				end

				local tab_row = tern.ui.row(tab_cells)
				local row_p: { [string]: any } = tab_row.p or {}
				-- Child id the drag reports as `item` on release.
				row_p.key = "tab_" .. t.id
				row_p.motionKey = "tab_" .. t.id
				tab_row.p = row_p
				table.insert(tab_rows, tab_row)
			end

			-- Container drag: reordering a tab row sends reorder_tab=<session> with item + 0-based index.
			local strip = tern.ui.col(tab_rows)
			local strip_p: { [string]: any } = strip.p or {}
			strip_p.key = "tab_strip_" .. s.id
			strip_p.drag = "reorder_tab=" .. s.id
			strip.p = strip_p
			table.insert(items, strip)
		end

		table.insert(items, tern.ui.node("text", { key = "sp_" .. s.id, text = " " }))
	end

	table.insert(items, tern.ui.rule(""))
	table.insert(items, tern.ui.row({
		tern.ui.button("+ Workspace", {
			key = "new_ws",
			variant = "default",
			size = "sm",
			actions = { click = "new" },
		}),
	}))

	local root = tern.ui.col(items)
	root.p = { transition = "layout", transitionMs = 150 }
	return root
end

return view_mod
