# Changelog

[English](CHANGELOG.md) | [简体中文](CHANGELOG.zh.md)

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)

## [Unreleased]

### Added
- Apache 2.0 license file and lightweight privacy note for open-source readiness.

### Planned
- Support for more trigger modes
- Improved portal visual editor
- Configuration profile import/export

## [1.1.1] - 2026-09-14

### Window Layout Recovery

- Fixed window restoration failures after browser tab or window title changes.
- Improved matching between multiple windows of the same app, including after restarting MousePortal while those windows remain open.

### Automatic Capture on Lock

- Fixed saved window sizes being affected by the lock-screen animation, which could cause windows to restore smaller than expected.
- Improved automatic layout capture on screen lock, including handling incomplete window lists and preserving existing saved layouts when capture fails.

### Displays and Portals

- Fixed saved portal configurations not being applied correctly when displays are connected, disconnected, or rearranged—even when the MousePortal main window is closed.
- Preserved matched display layout identities when cleaning up unused layouts.

Thanks to @JaeHyeon-KAIST for contributing these display and portal fixes in [#8](https://github.com/ai-eks/MousePortal/pull/8)!

## [1.1.0] - 2026-09-02

### Added
- Manual and automatic window-layout snapshots for each display arrangement.
- Display-canvas previews with switchable saved layouts and visible window placement.
- Apply, rename, delete, and automatic-to-manual promotion actions for saved layouts.
- Independent controls for global window recovery, sleep/lock capture, and automatic wake restoration.
- Searchable ignored-application settings for excluding apps from future snapshots.
- System, Light, and Dark application themes across all 20 supported languages.

### Changed
- Moved display controls into a clearer top toolbar and each display card.
- Persisted the resizable display-layout sidebar width.
- Kept four portal rows visible before scrolling.

### Fixed
- Prevented wake handling from scanning displays or moving windows when automatic restoration is disabled.
- Improved matching for multiple windows from the same application and preserved layouts with saved windows.
- Limited restoration to standard, non-minimized, non-full-screen windows and documented unsupported macOS window modes.

## [1.0.1] - 2026-07-24

### Fixed
- Prevented a portal's two lines from overlapping or sharing an endpoint on the same display edge.

## [1.0.0] - 2026-07-19

### Added
- First public release of Hotkey Jump and bidirectional edge portals.
- Automatic display-arrangement detection, named layouts, and display visualization.
- Global shortcut and portal configuration with menu bar and launch-at-login support.
- Localized interface in 20 languages.

## [0.1.2] - 2026-06-15

### Changed
- Updated Mac App Store packaging metadata and signing preparation.
- Improved packaged resource loading and Accessibility permission handoff.
- Restored the Dock/app menu presence and switched the menu bar entry to a stable system template icon.

## [0.1.1] - 2026-06-13

### Added
- Display layout cleanup action for removing unused layouts.
- Per-display custom names in the display layout canvas.

## [0.1.0] - 2026-03-19

### Added
- Hotkey Jump: Global keyboard shortcuts to teleport cursor to specific displays
- Portal System: Custom edge-to-edge teleportation zones
- Support for 20 languages (English, Chinese, Japanese, Korean, and more)
- Display layout management
- Configuration profile management
- Launch at login
- Menu bar quick access
- Visual portal editor
- Portal trigger modes (automatic/key-held)

### Technical
- SwiftUI-based user interface
- CGEvent-based global keyboard and mouse event monitoring
- Comprehensive unit test coverage

## [0.0.1] - 2025-01-17

### Added
- Initial development version
- Basic architecture setup
