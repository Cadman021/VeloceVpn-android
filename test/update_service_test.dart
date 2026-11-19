import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloce_vpn/services/app_version.dart';
import 'package:veloce_vpn/services/update_service.dart';

UpdateService _serviceFor(
  Map<String, dynamic> release, {
  int statusCode = 200,
}) {
  return UpdateService(
    client: MockClient((request) async {
      expect(request.url.path,
          '/repos/Cadman021/VeloceVpn-android/releases/latest');
      expect(request.headers['Accept'], 'application/vnd.github+json');
      return http.Response(
        jsonEncode(release),
        statusCode,
        headers: {'content-type': 'application/json'},
      );
    }),
  );
}

void main() {
  test('version comparison handles v-prefix and build metadata', () {
    expect(AppVersion.tryParse('v1.1.0')!.isNewerThan('1.0.0'), isTrue);
    expect(AppVersion.tryParse('1.0.1')!.isNewerThan('1.0.0+1'), isTrue);
    expect(AppVersion.tryParse('1.0.0')!.isNewerThan('1.0.0+1'), isFalse);
    expect(AppVersion.tryParse('1.0.0-beta')!.isNewerThan('1.0.0'), isFalse);
    expect(AppVersion.tryParse('not-a-version'), isNull);
  });

  test('returns a newer GitHub release', () async {
    final service = _serviceFor({
      'tag_name': 'v1.1.0',
      'html_url':
          'https://github.com/Cadman021/VeloceVpn-android/releases/tag/v1.1.0',
      'body': 'What is new',
      'published_at': '2026-11-18T10:00:00Z',
    });
    addTearDown(service.dispose);

    final release = await service.fetchLatest(currentVersion: '1.0.0');

    expect(release, isNotNull);
    expect(release!.version, '1.1.0');
    expect(release.notes, 'What is new');
    expect(release.publishedAt, isNotNull);
  });

  test('returns null when the installed version is current', () async {
    final service = _serviceFor({
      'tag_name': 'v1.0.0',
      'html_url':
          'https://github.com/Cadman021/VeloceVpn-android/releases/tag/v1.0.0',
    });
    addTearDown(service.dispose);

    expect(await service.fetchLatest(currentVersion: '1.0.0'), isNull);
  });

  test('rejects malformed tags instead of prompting', () async {
    final service = _serviceFor({
      'tag_name': 'latest',
      'html_url': 'https://example.invalid',
    });
    addTearDown(service.dispose);

    expect(await service.fetchLatest(currentVersion: '1.0.0'), isNull);
  });

  test('surfaces GitHub API failures', () async {
    final service = _serviceFor({}, statusCode: 403);
    addTearDown(service.dispose);

    expect(
      () => service.fetchLatest(currentVersion: '1.0.0'),
      throwsA(isA<UpdateCheckException>()),
    );
  });
}
