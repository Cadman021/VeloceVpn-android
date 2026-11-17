# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

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
