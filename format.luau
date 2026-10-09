--!strict
-- Pure string/path formatting. No cx, no state — trivially testable.

local HOME = tern.getenv("HOME") or ""

local format = {}

function format.split_path(p: string): { string }
	local parts = {}
	for part in string.gmatch(p, "[^/]+") do
		table.insert(parts, part)
	end
	return parts
end

function format.truncate(s: string, max_len: number): string
	if #s <= max_len then
		return s
	end
	local half = math.floor((max_len - 1) / 2)
	return string.sub(s, 1, half) .. "…" .. string.sub(s, -half)
end

-- "tern-workspaces" / "jcs-score-ali/src" (generic basenames get a parent)
function format.smart(p: string): string
	if p == "" or p == HOME then
		return "~"
	end
	if HOME ~= "" and string.sub(p, 1, #HOME) == HOME then
		p = string.sub(p, #HOME + 1)
	end
	local parts = format.split_path(p)
	if #parts == 0 then
		return "~"
	end
	local base = parts[#parts]
	local generic = {
		src = true, lib = true, pkg = true, cmd = true,
		dist = true, build = true, test = true, app = true,
		frontend = true, backend = true,
	}
	if #parts >= 2 and generic[string.lower(base)] then
		return format.truncate(parts[#parts - 1] .. "/" .. base, 20)
	end
	return format.truncate(base, 20)
end

-- "~/W/p/tern-sidebar" (intermediate dirs contracted to initials)
function format.fish(p: string): string
	if p == "" or p == HOME then
		return "~"
	end
	local prefix = ""
	if HOME ~= "" and string.sub(p, 1, #HOME) == HOME then
		p = string.sub(p, #HOME + 1)
		prefix = "~/"
	elseif string.sub(p, 1, 1) == "/" then
		p = string.sub(p, 2)
		prefix = "/"
	end
	local parts = format.split_path(p)
	if #parts == 0 then
		return prefix
	end
	if #parts == 1 then
		return format.truncate(prefix .. parts[1], 22)
	end
	local segments = {}
	for i = 1, #parts - 1 do
		table.insert(segments, string.sub(parts[i], 1, 1))
	end
	table.insert(segments, parts[#parts])
	return format.truncate(prefix .. table.concat(segments, "/"), 22)
end

-- Dispatch on kv "path_style" ("smart" | "fish")
function format.path(p: string?): string
	if not p or p == "" then
		return "terminal"
	end
	local style = tern.kv.get("path_style") or "smart"
	if style == "fish" then
		return format.fish(p)
	end
	return format.smart(p)
end

-- Tab row label: explicit name > file/doc title > extension heuristics > formatted cwd
function format.tab_display_name(t: TabInfo, cx: WindowCx): string
	if t.name and t.name ~= "" then
		return t.name
	end
	local pinfo = cx.session:pane(t.pane)
	-- Non-shell tabs (file, markdown doc, browser, git): prioritize file/document title
	if pinfo and (pinfo.kind == "file" or pinfo.kind == "docs" or pinfo.kind == "browser" or pinfo.kind == "git") then
		if t.title and t.title ~= "" then
			return format.truncate(t.title, 22)
		end
		if pinfo.file and pinfo.file ~= "" then
			return format.truncate(format.smart(pinfo.file), 22)
		end
	end
	-- Tab title has filename extension (e.g. TODO.md, config.toml)
	if t.title and string.find(t.title, "%.%w+$") and t.title ~= t.cwd then
		return format.truncate(t.title, 22)
	end
	-- Shell terminal tab: format working directory
	return format.path(t.cwd or t.title)
end

return format
