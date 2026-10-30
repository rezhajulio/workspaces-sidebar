# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
and [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## [0.1.12] - 2026-10-30

### Features
- **open**: mount the sidebar with native Tern 0.9.8 `CanvasSpec` placement (`target`, `dir = "left"`, `ratio`), so it opens directly at the saved width with no `layout:move` / `match_ratio` resize hops and no flicker; legacy move/resize kept only as fallback when Tern does not place it in the left rail
- **events**: subscribe to `session_ended` to drop the ended session's `fold_<id>` kv entry, invalidate the model cache, update the status segment when that session was shown, and schedule an immediate refresh

## [0.1.11] - 2026-10-29

### Features
- **rename**: use native `cx:prompt` for workspace rename, updating sidebar and status line instantly without modal handover or session switching
- **commands**: add `Workspaces: move tab to workspace...` command powered by native `cx:pick`
- **events**: subscribe to `agent_state` and `agent_finished` to update agent status badges within 30ms in addition to polling
- **telemetry**: subscribe to `budget` event to log plugin hook pause and resume transitions
- **status**: return pre-allocated status segment in `tern.chrome.status` callback to eliminate garbage collection churn within the 4ms budget

## [0.1.10] - 2026-10-29

### Performance Improvements
- **events**: defer `ensure_pinned` and `refresh` in `tern.on("focus")` via `schedule_refresh`, eliminating 50ms hook budget timeouts during rapid tab switching

## [0.1.9] - 2026-10-29

### Bug Fixes
- **model**: set `cache_valid = true` after populating `model.mine` so per-cycle memoization actually activates across `is_mine` calls
- **flags**: decouple `cache_flags` memoization check from `cache_valid` flag to eliminate redundant `cx.agents:list()` sweeps during `fingerprint` and `build`
- **cleanup**: rewrite `auto_close_empty_tabs` from full-tree layout walks to pane-membership counts, reducing execution time from 23.8ms to 1.0ms
- **render**: track per-pane fingerprints (`pane_fp`) and update active pane immediately while batching background panes, eliminating 50ms hook budget timeouts on multi-tab workspaces

## [0.1.8] - 2026-10-25

### Performance Improvements
- **events**: debounce rapid `cwd`, `title`, `command_started`, and `command_finished` lifecycle events through a scheduled timer turn, preventing hook budget exhaustion during shell activity bursts

## [0.1.7] - 2026-10-25

### Bug Fixes
- **pinned**: show the sidebar on a fresh install, as the README documents (`pinned` defaults to `true`). The rail was hidden until the first `Workspaces: toggle sidebar`, because an unset `pinned` key was read as off. Hiding now stores `false` instead of deleting the key. Users who had hidden the sidebar see it once more after this update (#1, #2 by @ankitg12).

## [0.1.6] - 2026-10-25

### Performance Improvements
- **model**: memoize `collect_tab_flags` per cycle so fingerprint, build, and poll share a single query pass
- **poll**: throttle tree layout scans for `auto_close_empty_tabs` and `deduplicate_sidebars` to 1-second intervals
- **events**: remove redundant full-tree layout scans from the hot `focus` handler
- **budget**: reduce total cycle duration from 36.6ms to 15.5ms, well within Tern's 50ms hook budget

## [0.1.5] - 2026-10-13

### Bug Fixes
- **rename**: remove unhoisted helper causing `attempt to call a nil value` crash on workspace rename action (`ren:`)
- **perf**: set poll loop to steady 200ms interval to strictly observe Tern's 50ms timer hook budget

## [0.1.4] - 2026-10-13

### Bug Fixes
- **events**: subscribe to `cwd`, `title`, `command_started`, and `command_finished` lifecycle events so shell directory changes, title updates, and command status markers redraw instantly
- **view**: fingerprint `format.tab_display_name` directly instead of short-circuiting on non-empty terminal title, ensuring path updates trigger canvas redraws
- **format**: resolve fallback working directory from pane info when tab pane points to an uninitialized block
- **rename**: activate high-frequency 50ms polling burst on workspace rename actions and commands to immediately reflect the new name upon submission

## [0.1.3] - 2026-10-13

### Features
- **layout**: support vertical splits (`split_down`) and dragged blocks underneath the pinned sidebar rail
- **layout**: guard `split_right` on the sidebar canvas; redirect horizontal splits to the active terminal pane to prevent narrow rail corruption

### Bug Fixes
- **layout**: replace single-leaf `root[1].pane` check with `layout_mod.is_in_left_rail` so stacked blocks in the left rail survive poll cycles
- **focus**: preserve divider ratio tracking when the left rail contains multiple stacked panes

## [0.1.2] - 2026-10-09

### Documentation
- **docs**: add project `CHANGELOG.md` adhering to Keep a Changelog and Conventional Commits

### Maintenance
- **release**: bump version to `0.1.2`

## [0.1.1] - 2026-10-09

### Bug Fixes
- **view**: replace typed module field annotations with localized declarations to resolve window VM parser failure (`6e2423d`)

### Documentation
- **readme**: embed demo screenshot in README (`9074d65`)

### Maintenance
- **release**: bump version to `0.1.1` (`475241d`)

## [0.1.0] - 2026-10-09

### Features
- **sidebar**: pinned workspace rail mounted to left of every tab using native canvas pane
- **tree**: sessions mapped to workspaces with nested tab trees, active dot markers, and branch glyphs
- **badges**: live status indicators for waiting agents (`?`), busy commands (`◐`), failed commands (`!`), and agent blocks (`◆`)
- **attention**: jump to next tab requiring attention via `Cmd+Alt+Shift+A`
- **navigation**: direct workspace switching with `Cmd+Alt+1..9`
- **colors**: cycling native tab colors with persistence across daemon restarts
- **cleanup**: auto-close empty tabs on shell exit (`Ctrl+D`)
- **layout**: dynamic window width calibration and ratio synchronization across tabs
- **paths**: configurable path formatting (`smart` vs `fish`)
- **perf**: memoized canvas/pane reads per poll cycle for sub-millisecond redraw checks
