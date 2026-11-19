# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-11-18

### Added

- Automatic reconnect with bounded exponential backoff after network loss, server failure or three failed health probes
- Connection health probe through a loopback SOCKS listener, with a "reconnecting" state in the app, tile and notification
- Tunnel-specific throughput from Xray's loopback Prometheus metrics; device-wide `TrafficStats` remains a short-lived fallback
- In-app update checker for GitHub Releases, checked at most once per day, with dismissible banner and manual check in Settings
- Redacted in-app diagnostics report (version, ABI, service state, traffic counters, last error) with copy-to-clipboard
- Downloaded Xray configs are now treated as untrusted: server-provided inbound listeners and logging are removed, only TUN and loopback SOCKS are created, and outbound tags are validated
- Deterministic loopback SOCKS port allocation; the selected port is reused by the tile and auto-reconnect
- Adaptive launcher foreground with proper safe-zone padding, round icon, Android 13 monochrome layer and a padded native splash logo

### Changed

- Version bumped to `1.1.0+2`
- Launcher icon resources moved to new names so the old, over-cropped assets are never referenced again

### Fixed

- Launcher and splash icons were cropped on circular/squircle masks after the 1.0.0 icon change
- Reconnect and health state now reach Flutter instead of showing a stale "connected" UI
- Traffic counters reset cleanly when Xray restarts on reconnect

## [1.0.0] - 2026-11-17

First public Android release.

### Added

- Server list grouped by country with search, favorites, recents and latency tests
- Xray TUN connection through `libXray`
- Per-app split tunneling (exclusive/inclusive) and IP/domain exclusions
- Optional ad-block server variant with automatic fallback to the normal config
- Quick Settings tile and foreground-service notification
- Dark/light themes and English, Persian, French, Chinese and Russian UI
- Live throughput indicator
- Local, network-free country flags
- Offline cache of the last server list with retry
- Encrypted last-config storage using Android Keystore; backup and device transfer disabled
- Release signing via `android/key.properties`; CI and tag-driven GitHub Release workflows with per-ABI APKs, SHA-256 and private Dart symbols

### Fixed

- Persian/Arabic RTL direction was overridden by `MaterialApp`
- Split-tunneling settings were not loaded before a cold-start connection
- Native start/stop state was not synchronised with Flutter (tile/notification actions)
- First connection could fail because the native start handshake raced `startService()`
- IPv6 traffic could bypass the VPN; IPv6 is now routed into the tunnel
- Selecting a new server while connected now reconnects instead of showing a misleading active badge
- `libXray` stop was moved off the main thread; start/stop generations prevent stale results
- Start while already running now releases the old TUN descriptor and network callback
- Empty inclusive-mode selection is rejected instead of tunneling every app
- Ad-block 404 now falls back to the normal configuration
- Location load failures now offer retry and a stale offline cache
- Unnecessary repeating animation and background speed polling removed
- Version display now comes from `package_info_plus`
- Notification permission is requested once; notification has a dedicated small icon and localized strings
- Settings and home screens are scrollable on small displays
- App ID changed to `com.cadman.veloce`; version bumped to `1.0.0+1`

## [0.1.0] - 2026-11-17

### Added

- Initial development build of the Android client
