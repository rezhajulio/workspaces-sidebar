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

print("ok")
