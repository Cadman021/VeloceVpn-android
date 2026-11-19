# Security Policy

## Supported versions

Security fixes are applied to the latest released version (1.1.x). Development builds from `main` are not supported releases and may not receive backports.

## Reporting a vulnerability

Please **do not** open a public issue for a vulnerability that could expose users, server credentials or traffic.

Use GitHub's private vulnerability reporting:

1. Open the repository's **Security** tab.
2. Choose **Report a vulnerability**.
3. Include the app version, Android version, reproduction steps and a redacted proof of concept.

Do not include real Xray configurations, server addresses, credentials or personal traffic captures. If a configuration is required, replace hosts, UUIDs, passwords and keys with dummy values while preserving the structure.

You can expect an initial acknowledgement within a few days. Please allow time for a fix and a coordinated disclosure before publishing details.

## Scope

In scope:

- VPN permission, tunnel lifecycle and kill-switch/leak behaviour
- Storage of downloaded Xray configurations and credentials
- MethodChannel/native bridge input validation
- Network request handling, TLS usage and downloaded-config trust
- Split-tunneling and IP/domain exclusion bypasses
- Sensitive data in logs, backups or notifications

Out of scope:

- The security or logging policy of third-party VPN servers
- Blocking or censorship performed by network operators
- Device rooting, custom ROMs or malware with root access
- Denial of service against the public backend
