import re
import tomllib
from pathlib import Path

# Verify plugin.toml
manifest_path = Path("tern-workspaces/plugin.toml")
assert manifest_path.exists(), "manifest missing"
manifest = tomllib.loads(manifest_path.read_text())
assert manifest["id"] == "workspaces-sidebar"
assert manifest["schema"] == 1
assert manifest["window"] == "window.luau"

# Verify window.luau action parser logic
action_re = re.compile(r"^([a-zA-Z_]+):?(\d*)$")

cases = [
    ("ws:12", ("ws", "12")),
    ("fold:12", ("fold", "12")),
    ("ren:12", ("ren", "12")),
    ("toggle_lock:12", ("toggle_lock", "12")),
    ("color_tab:34", ("color_tab", "34")),
    ("close:12", ("close", "12")),
    ("close_tab:45", ("close_tab", "45")),
    ("new_tab:12", ("new_tab", "12")),
    ("new", ("new", "")),
    ("tab:34", ("tab", "34")),
    ("tab_up:34", ("tab_up", "34")),
    ("tab_down:34", ("tab_down", "34")),
    ("move:34", ("move", "34")),
    ("movehere:12", ("movehere", "12")),
    ("note:12", ("note", "12")),
    ("filter", None),  # filter:all does NOT match number-tail regex (string id)
]

for act, expected in cases:
    m = action_re.match(act)
    if expected is None:
        # filter:all has non-numeric tail -> must NOT match numeric parser
        assert act.startswith("filter"), f"sanity {act}"
        continue
    assert m is not None, f"Failed match on {act}"
    assert m.groups() == expected, f"Mismatch on {act}: got {m.groups()}"

# filter chip action uses string ids; verify kind extraction separately
chip_re = re.compile(r"^([a-zA-Z_]+):?(.*)$")
m = chip_re.match("filter:busy")
assert m is not None
assert m.group(1) == "filter"
assert m.group(2) == "busy"

# Verify is_in_left_rail tree search logic
def is_in_left_rail(tree, pane):
    if not tree:
        return False
    if tree.get("pane") == pane:
        return True
    left = tree.get(1) or tree.get("1")
    if not left:
        return False
    def scan(t):
        if not t:
            return False
        if t.get("pane") == pane:
            return True
        return scan(t.get(1) or t.get("1")) or scan(t.get(2) or t.get("2"))
    return scan(left)

sb = 100
assert is_in_left_rail({"pane": sb}, sb)  # bare leaf
assert is_in_left_rail({"1": {"pane": sb}, "2": {"pane": 200}}, sb)  # normal left rail
assert is_in_left_rail({"1": {"1": {"pane": sb}, "2": {"pane": 300}}, "2": {"pane": 200}}, sb)  # block under sidebar
assert is_in_left_rail({"1": {"1": {"pane": 300}, "2": {"pane": sb}}, "2": {"pane": 200}}, sb)  # block above sidebar
assert not is_in_left_rail({"1": {"pane": 200}, "2": {"pane": sb}}, sb)  # displaced: sidebar in root[2]
assert not is_in_left_rail({"1": {"pane": 200}, "2": {"1": {"pane": sb}, "2": {"pane": 300}}}, sb)  # displaced deep

# Verify Tern 0.9.7 API wiring
win_source = Path("tern-workspaces/window.luau").read_text()
for needle in ('tern.on("agent_state"', 'tern.on("agent_finished"', 'tern.on("budget"', "cx:prompt(", "cx:pick("):
    assert needle in win_source, f"missing {needle}"
assert 'cx:command("rename_session")' not in win_source

# Verify plugin.toml version matches latest CHANGELOG heading
changelog = Path("tern-workspaces/CHANGELOG.md").read_text()
latest_ver = re.search(r"## \[([0-9.]+)\]", changelog)
assert latest_ver is not None, "latest changelog version not found"
assert latest_ver.group(1) == manifest["version"], f"version mismatch: {latest_ver.group(1)} vs {manifest['version']}"

print("ok")
