# Veloce VPN — Privacy Policy

**Last updated: 2026-11-18**

This policy describes what the Veloce VPN Android application (“Veloce”, “the app”) does with information. It does not describe the independent logging practices of third-party VPN servers or network operators.

## Summary

- The app contains **no analytics, advertising or crash-reporting SDKs**.
- The app does not require an account and does not ask for your name, email address or phone number.
- To show the server list and connect, the app downloads data from the Veloce backend. That backend receives your IP address and standard HTTPS request metadata.
- VPN traffic is carried by third-party servers. Veloce does not control every server and cannot guarantee an operator's logging policy.
- Preferences and the last-used connection configuration are stored locally in the app's private storage on your device.

## Information the app stores on your device

The app stores the following locally:

- Language, theme, ad-block preference
- Selected server, favorites and recent connections
- Split-tunneling mode, selected apps and IP/domain exclusions
- The last downloaded Xray configuration, so the Quick Settings tile can reconnect without reopening the app

This information stays in the app's private storage. It is not sent to Veloce and is removed when you clear the app's data or uninstall it. Android cloud backup and device-to-device transfer of app data are disabled in the app manifest. The last Xray configuration contains server credentials and is encrypted at rest with a key held by Android Keystore; the temporary working config is kept in `noBackupFilesDir` and deleted when the tunnel stops.

## Information processed when you use the service

### Server list and configuration requests

When you open the app or connect, it sends HTTPS requests to `api.honeyface.ir` for the candidate server list and for the Xray configuration of the selected server. Like any web request, these requests expose to the server:

- Your public IP address and approximate network location
- The time of the request and the requested country/city or configuration ID
- Standard HTTP metadata such as the client user agent and TLS information

This data is used to serve the requested content, keep the service healthy and prevent abuse. Veloce does not sell it. Server-side logs, if any, are retained only as long as needed for operation and security.

### VPN traffic

When connected, your internet traffic is carried by the VPN server you selected. Veloce's app does not record your browsing history or traffic content. However, the operator of the selected server may process connection metadata or traffic according to its own policy. Do not use a server you do not trust for sensitive traffic.

### Third-party content

- Country flags are rendered locally as Unicode emoji. The app does not request flag images from an external CDN.
- The app checks the public GitHub Releases API at most once per day. GitHub receives your IP address and a generic User-Agent; no account, device identifier or analytics identifier is sent. Opening a release link is served by GitHub under its privacy policy.
- Throughput is read from a loopback-only metrics endpoint inside the app. If those metrics are unavailable, the app falls back to Android's device-wide traffic counters; neither value is transmitted.

The app does not integrate Telegram. The backend may collect publicly available server configurations from public channels; this happens outside your device and is not linked to your app usage.

## Permissions

- **VPN (BIND_VPN_SERVICE):** required to create the system tunnel. Android shows a separate consent dialog.
- **Notifications:** used to show the ongoing VPN status and the disconnect action. On Android 13+ this is a runtime permission.
- **Query all packages:** used only to display installed apps for split tunneling. The list is processed on-device and is not uploaded.
- **Internet / network state:** required to download the server list and detect connectivity changes.

## Children

The app is not directed to children under 13. Do not use it to process a child's personal data.

## Security

The app uses HTTPS for backend requests and keeps its local data in app-private storage. No method of transmission or storage is completely secure. A VPN protects traffic between your device and the selected server; it does not make you anonymous and does not protect data after it leaves that server.

## Changes

Material changes to this policy will be published in this repository and in the release notes. Continued use after a change means you accept the updated policy.

## Contact

Open an issue at <https://github.com/Cadman021/VeloceVpn-android/issues> for privacy questions. For vulnerabilities, use the private reporting process in [SECURITY.md](../SECURITY.md).

---

This document is a project policy, not legal advice. Have it reviewed for the jurisdictions where you distribute the app.
