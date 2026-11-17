# Third-party notices

Veloce VPN itself is licensed under the GNU Affero General Public License v3.0
(see [LICENSE](LICENSE)). It is built with open-source software; this file is a
summary and the upstream license text prevails in every case.

| Component | License | Upstream |
| --- | --- | --- |
| Flutter / Dart | BSD-3-Clause | https://github.com/flutter/flutter |
| provider | MIT | https://pub.dev/packages/provider |
| http | BSD-3-Clause | https://pub.dev/packages/http |
| shared_preferences | BSD-3-Clause | https://pub.dev/packages/shared_preferences |
| url_launcher | BSD-3-Clause | https://pub.dev/packages/url_launcher |
| package_info_plus | BSD-3-Clause | https://pub.dev/packages/package_info_plus |
| Material Icons | Apache-2.0 | https://fonts.google.com/icons |
| Xray-core | MPL-2.0 | https://github.com/XTLS/Xray-core |
| libXray (bundled `libXray.aar`) | See upstream | https://github.com/XTLS/libXray |

The Android build bundles `android/app/libs/libXray.aar`, which contains
`libgojni.so` built from Xray-core/libXray. Before publishing a release,
verify the exact license and notice requirements of the AAR version in use and
include the upstream license text if required.

Country flags are rendered locally from Unicode emoji; no external flag CDN is
contacted.

If you add or replace a dependency, update this file and the release notes.
