--!strict
-- Canvas tree builder + change fingerprint (what triggers a redraw).

local format = require("./format")
local model = require("./model")
local layout_mod = require("./layout")

local view_mod = {}

view_mod.TAB_COLORS: { TabColor } = {
	"blue", "green", "yellow", "orange", "red", "purple", "teal", "pink"
}

view_mod.COLOR_LABELS: { [string]: { glyph: string, tone: string } } = {
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
	for i, c in view_mod.TAB_COLORS do
		if c == cur then
			if i < #view_mod.TAB_COLORS then
				return view_mod.TAB_COLORS[i + 1]
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
	table.insert(parts, "focus:" .. (active_tab or 0))
	table.insert(parts, "ntabs:" .. #tabs)

	local tab_flags = model.collect_tab_flags(cx)
	local moving = tern.kv.get("moving_tab")
	local filt = tern.kv.get("tab_filter") or "all"
	table.insert(parts, "moving:" .. (moving or 0))
	table.insert(parts, "filter:" .. filt)

	for _, s in cx.sessions:list() do
		local collapsed = model.is_session_collapsed(s.id, s.current)
		table.insert(parts, s.id .. ":" .. (if s.current then "1" else "0") .. ":" .. (if s.locked then "L" else "U") .. ":" .. (if collapsed then "C" else "E") .. ":" .. s.name .. ":" .. s.tabs)
	end
	for _, t in tabs do
		local tf = tab_flags[t.id]
		local flag_str = ""
		if tf then
			flag_str = (if tf.busy then "B" else "") .. (if tf.waiting then "W" else "") .. (if tf.alert then "A" else "")
		end
		local col = t.color or tern.kv.get("tab_color_" .. t.id) or ""
		table.insert(parts, "t" .. t.id .. ":" .. col .. ":" .. flag_str .. ":" .. (t.name or t.title or t.cwd or ""))
	end
	return table.concat(parts, "|")
end

function view_mod.build(cx: WindowCx): Node
	local items: { Node } = {}
	local tabs = cx.session:tabs()
	local sessions = cx.sessions:list()
	local focused_pane = cx.session:focused()
	local current_tab_id = if focused_pane then cx.session:tab_of(focused_pane) else nil
	local tab_flags = model.collect_tab_flags(cx)
	local in_move_mode = (tern.kv.get("moving_tab") ~= nil)
	local moving_tab = tern.kv.get("moving_tab")

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

		if in_move_mode then
			table.insert(header_cells, tern.ui.node("badge", {
				key = "ws_movehere_" .. s.id,
				text = "Move here",
				tone = "accent",
				actions = { click = "movehere:" .. s.id },
			}))
		end

		if not in_move_mode then
			table.insert(header_cells, tern.ui.node("badge", {
				key = "ws_add_" .. s.id,
				text = "+",
				tone = "muted",
				actions = { click = "new_tab:" .. s.id },
			}))

			table.insert(header_cells, tern.ui.node("badge", {
				key = "ws_ren_" .. s.id,
				text = "✎",
				tone = "muted",
				actions = { click = "ren:" .. s.id },
			}))

			-- Interactive lock toggle
			if s.locked then
				table.insert(header_cells, tern.ui.node("badge", {
					key = "ws_lock_" .. s.id,
					text = "🔒",
					tone = "warn",
					actions = { click = "toggle_lock:" .. s.id },
				}))
			else
				table.insert(header_cells, tern.ui.node("badge", {
					key = "ws_lock_" .. s.id,
					text = "🔓",
					tone = "muted",
					actions = { click = "toggle_lock:" .. s.id },
				}))
				if #sessions > 1 then
					table.insert(header_cells, tern.ui.node("badge", {
						key = "ws_del_" .. s.id,
						text = "✕",
						tone = "muted",
						actions = { click = "close:" .. s.id },
					}))
				end
			end
		end

		table.insert(items, tern.ui.row(header_cells))

		if not collapsed then
			for i, t in shown_tabs do
				local branch = if i == #shown_tabs then "  └─ " else "  ├─ "
				local is_active = (t.id == current_tab_id)
				local dot_glyph = if is_active then "● " else "○ "

				local effective_color = t.color or tern.kv.get("tab_color_" .. t.id)
				local color_info = if effective_color then view_mod.COLOR_LABELS[effective_color] else nil

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
				if not in_move_mode and show_tag and effective_color and color_info then
					local tag_text = if show_label then color_info.glyph .. " " .. effective_color else color_info.glyph
					table.insert(tab_cells, tern.ui.node("badge", {
						key = "tab_col_" .. t.id,
						text = tag_text,
						tone = color_info.tone,
						actions = { click = "color_tab:" .. t.id },
					}))
				elseif show_tag and not in_move_mode then
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

				if in_move_mode then
					if moving_tab == t.id then
						table.insert(tab_cells, tern.ui.node("badge", {
							key = "tab_moving_" .. t.id,
							text = "◀ moving (esc to cancel)",
							tone = "accent",
							actions = { click = "cancel_move" },
						}))
					end
				else
					table.insert(tab_cells, tern.ui.node("badge", {
						key = "tab_move_" .. t.id,
						text = "⇥",
						tone = "muted",
						actions = { click = "move:" .. t.id },
					}))

					if #shown_tabs > 1 then
						table.insert(tab_cells, tern.ui.node("badge", {
							key = "tab_del_" .. t.id,
							text = "✕",
							tone = "muted",
							actions = { click = "close_tab:" .. t.id },
						}))
					end
				end

				table.insert(items, tern.ui.row(tab_cells))
			end
		end

		table.insert(items, tern.ui.node("text", { key = "sp_" .. s.id, text = " " }))
	end

	table.insert(items, tern.ui.rule(""))
	if in_move_mode then
		table.insert(items, tern.ui.row({
			tern.ui.node("badge", {
				key = "cancel_move_ws",
				text = "Cancel move (esc)",
				tone = "warn",
				actions = { click = "cancel_move" },
			}),
		}))
	else
		table.insert(items, tern.ui.row({
			tern.ui.node("badge", {
				key = "new_ws",
				text = "+ Workspace",
				tone = "accent",
				actions = { click = "new" },
			}),
		}))
	end

	return tern.ui.col(items)
end

return view_mod
