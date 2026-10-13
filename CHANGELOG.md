# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
and [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

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
