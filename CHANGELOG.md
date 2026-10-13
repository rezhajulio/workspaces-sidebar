# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html)
and [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## [Unreleased]

### Planned
- Layout and split pane integration:
  - Guard `split_right` against horizontal distortion of the pinned sidebar rail.
  - Enable `split_down` below the workspace header/action controls without poll eviction.
  - Preserve dragged panes placed beneath the sidebar canvas.

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
