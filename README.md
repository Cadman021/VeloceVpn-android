# Veloce VPN — Android

A lightweight Android VPN client built with Flutter and the [Xray-core](https://github.com/XTLS/Xray-core) native library (via `libXray`). The app downloads a health-checked server list from the Veloce backend, connects through a local TUN interface, and provides per-app split tunneling, domain/IP exclusions, an ad-block server variant and a Quick Settings tile.

> **Status:** Android-only, 1.0.0. The iOS, web, Windows, Linux and macOS folders are Flutter template leftovers and are not supported.

---

## Features

- Server list grouped by country, with search, favorites and recent connections
- Latency test for one server or all servers, plus an “optimal server” shortcut
- Xray TUN mode with TCP/UDP, DNS interception and a foreground service notification
- Optional ad-block configuration (`*.adblock.json` on the backend)
- Split tunneling: bypass selected apps (*exclusive*) or tunnel only selected apps (*inclusive*)
- IP / hostname exclusions routed directly instead of through the tunnel
- Quick Settings tile for connect/disconnect without opening the app
- Dark/light theme and UI in English, Persian, French, Chinese and Russian, with real RTL layout for Persian
- IPv4 and IPv6 routed through the tunnel
- Keystore-encrypted last-config cache and disabled Android backup
- Offline server-list cache with retry
- Live throughput indicator on the home screen

---

## Install

1. Open the [Releases](https://github.com/Cadman021/VeloceVpn-android/releases) page.
2. Download the APK that matches your device:
   - `app-arm64-v8a-release.apk` — almost all Android phones from ~2017 onwards
   - `app-armeabi-v7a-release.apk` — older 32-bit devices
3. Compare the SHA-256 hash with `SHA256SUMS.txt` from the same release.
4. Allow installation from your browser/file manager, install, then open the app.
5. Grant the Android VPN permission when asked. On Android 13+ also allow notifications so the VPN status notification is visible.

**Requirements:** Android 7.0 (API 24) or newer. Package ID: `com.cadman.veloce`. The Xray native library is bundled for `arm64-v8a` and `armeabi-v7a`; x86 builds are only useful for emulators.

Veloce is not distributed on Google Play. Sideloading means you are responsible for verifying the download source and hash.

---

## First run

1. Tap the location card and pick a country/city, or tap the lightning icon to test latency.
2. Tap the power button. The first connection asks for the system VPN permission.
3. The notification and the Quick Settings tile show the tunnel state.
4. Use **Settings → Split Tunneling** to choose which apps bypass the tunnel, and **IP & Hostname Exclusions** for domains/IP ranges that must stay outside it.

Changing the location while connected switches the tunnel automatically. Changing split-tunneling settings or IP exclusions shows a "Reconnect to apply" banner, and toggling AdBlock while connected reconnects automatically.

---

## Privacy and security

- No analytics, advertising SDKs or crash-reporting SDKs are included in the app.
- The app requests the candidate list and Xray configuration from `https://api.honeyface.ir`; as with any HTTPS request, that server sees your IP address and standard request metadata.
- VPN traffic is carried by third-party servers. Veloce does not operate every server in the list and cannot guarantee an operator's logging policy.
- Server configurations contain connection credentials. The last configuration is stored encrypted with Android Keystore, the temporary Xray config file lives in `noBackupFilesDir` and is deleted when the tunnel stops, and Android cloud backup/device-to-device transfer is disabled.
- Country flags are rendered locally as Unicode emoji; the app does not request flag images from an external CDN.

Read the [Privacy Policy](docs/privacy-policy.md) and [Terms of Service](docs/terms-of-service.md). Have them reviewed for the jurisdictions where you distribute the app; they are also published from the `docs/` folder for GitHub Pages.

---

## Build from source

### Prerequisites

- Flutter **3.47.0** stable (Dart 3.13+) — test with the version pinned in `.metadata`
- JDK **17** or newer
- Android SDK with platform/build-tools matching `compileSdk` (currently API 36)
- The `android/app/libs/libXray.aar` file (already in this repository)

### Debug / local release

```bash
flutter pub get
flutter analyze
flutter test
flutter run                     # debug on a connected device
flutter build apk --debug
```

A local release build without signing material falls back to the Android debug key:

```bash
flutter build apk --release --split-per-abi
```

### Signed release

1. Generate a keystore **once** and keep it outside the repository:

   ```bash
   keytool -genkeypair -v \
     -keystore veloce-release.jks \
     -alias veloce \
     -keyalg RSA -keysize 4096 -validity 10000
   ```

2. Copy `android/key.properties.example` to `android/key.properties` and fill in the path/passwords.
3. Put the `.jks` where `storeFile` points (relative to `android/app/`).
4. Build:

   ```bash
   flutter build apk --release --split-per-abi \
     --obfuscate --split-debug-info=build/symbols
   ```

`android/key.properties`, `*.jks` and `*.keystore` are git-ignored. Never commit them.

### CI and release automation

- `.github/workflows/android-ci.yml` runs `flutter analyze`, `flutter test` and a debug APK build on pushes/PRs.
- `.github/workflows/android-release.yml` runs on `v*` tags, validates that the tag matches `pubspec.yaml`, requires the four signing secrets below, builds per-ABI release APKs, writes `SHA256SUMS.txt`, uploads Dart symbols as a private artifact and publishes the GitHub Release.

Configure these repository secrets before tagging:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | `base64 -w0 veloce-release.jks` (on Windows: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("veloce-release.jks"))` in PowerShell) |
| `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| `ANDROID_KEY_ALIAS` | `veloce` (or your alias) |
| `ANDROID_KEY_PASSWORD` | key password |

Then bump `version:` in `pubspec.yaml`, commit, and push a matching tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

---

## Architecture

```
lib/
  main.dart                     app bootstrap, providers, MaterialApp
  controllers/
    vpn_controller.dart         connection state, API calls, preferences
    split_tunneling_controller.dart
  screens/                      splash, home, locations, settings, split tunneling
  services/                     API client and models
  theme/                        colors, Material theme, i18n
  widgets/                      country flag
android/app/src/main/kotlin/com/cadman/veloce/
  MainActivity.kt               MethodChannel bridge, VPN permission, ping, speed
  VeloceVpnService.kt           VpnService + Xray TUN lifecycle + notification
  VeloceTileService.kt          Quick Settings tile
  SecureConfigStore.kt          Keystore-encrypted last-config cache
```

Backend contract used by the client:

- `GET /api/v1/candidates.json` → `{ "data": [{ "id", "city", "country", "country_code" }, ...] }`
- `GET /api/v1/xray/{configId}.json` → `{ "xray_config": { ... } }`
- `GET /api/v1/xray/{configId}.adblock.json` → same shape, ad-block variant

The API client accepts an ordered list of base URLs (`kCentralApiBases` in `lib/services/api_service.dart`). Only the primary host is configured in 1.0.0; additional mirrors can be added there without changing the rest of the app.

---

## Known limitations (1.0.0)

- The throughput indicator uses device-wide `TrafficStats`, not the Xray tunnel only. It is a device activity indicator, not a per-tunnel accounting value.
- There is no automatic reconnect after a network handover or a server-side drop; the app updates the underlying network and asks the user to reconnect.
- The app does not verify a cryptographic signature on downloaded server configurations in addition to HTTPS.
- Split tunneling is per-app, not per-UID/profile; work profiles and secondary users may behave differently depending on the device.
- Android may stop the foreground service on aggressive OEM battery managers. Users can enable Always-on VPN in Android settings for a stronger guarantee.
- The iPhone/iPad, web and desktop folders are not implemented; do not ship them as supported targets.

---

## Contributing

Issues and pull requests are welcome. Please include the Android version, device model, app version and, for connection problems, a redacted logcat snippet. Never paste a full Xray configuration or server credentials into an issue.

For security reports, follow [SECURITY.md](SECURITY.md) instead of opening a public issue.

---

## License

Veloce VPN is licensed under the **GNU Affero General Public License v3.0** (AGPL-3.0). See [LICENSE](LICENSE).

Because the app is distributed under AGPL-3.0, if you modify it and make it available to users over a network, you must offer those users the Corresponding Source of your modified version. The bundled `libXray`/`Xray-core` native library remains subject to its upstream license and notices; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and the upstream projects for details.

## Disclaimer

Veloce is a networking tool, not a guarantee of anonymity. Use it only in compliance with the laws that apply to you and with servers you are authorised to use. The maintainers are not responsible for how third-party servers operate or for misuse of the app.
