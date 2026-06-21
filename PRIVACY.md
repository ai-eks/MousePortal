# Privacy

Last updated: 2026-06-14

MousePortal is designed as a local macOS utility for managing cursor movement across multiple displays.

## What MousePortal Stores

MousePortal stores its settings locally on your Mac, including:

- Display layout names and display arrangement metadata.
- Hotkey configuration.
- Portal configuration.
- Configuration profiles.
- App preferences such as launch-at-login and menu bar visibility.

The project maintainers do not receive this data.

## Network and Analytics

MousePortal does not include analytics, advertising, telemetry, or a backend service.

The codebase includes optional configuration profile sync support through Apple's `NSUbiquitousKeyValueStore`. If a build exposes and enables that feature, sync is handled through the user's iCloud account.

## Permissions

MousePortal asks for macOS Accessibility permission because its core features need to:

- Listen for configured global hotkeys.
- Monitor mouse movement for portal triggers.
- Move the cursor between displays.

MousePortal uses these permissions only for the cursor and hotkey features described in the app.
