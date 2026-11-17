import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:veloce_vpn/services/api_service.dart';

void main() {
  test('candidates parsing skips malformed items and duplicate ids', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/candidates.json');
      return http.Response(
        jsonEncode({
          'data': [
            {
              'id': 'tehran-1',
              'city': 'Tehran',
              'country': 'Iran',
              'country_code': 'IR',
            },
            {
              'id': 42,
              'city': 'Berlin',
              'country': 'Germany',
              'country_code': 'DE',
            },
            {'city': 'No id'},
            {'id': 'tehran-1', 'city': 'Duplicate'},
            {'id': '../bad', 'city': 'Traversal'},
          ],
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = ApiService(
      client: client,
      baseUrls: ['https://example.test/'],
    );
    addTearDown(api.dispose);

    final groups = await api.fetchCandidates();
    expect(groups.length, 2);

    final iran = groups.firstWhere((g) => g.countryCode == 'ir');
    expect(iran.countryName, 'Iran');
    expect(iran.locations.single.id, 'tehran-1');

    final germany = groups.firstWhere((g) => g.countryCode == 'de');
    expect(germany.locations.single.id, '42');
  });

  test('xray config is validated and cached', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          jsonEncode({
            'xray_config': {'outbounds': []},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('server error', 500);
    });

    final api = ApiService(
      client: client,
      baseUrls: ['https://example.test'],
    );
    addTearDown(api.dispose);

    final first = await api.fetchXrayConfig('abc_123');
    expect(first['outbounds'], isEmpty);

    // The second request fails; the last successful config is returned from
    // the in-memory cache instead of breaking a reconnect.
    final second = await api.fetchXrayConfig('abc_123');
    expect(second['outbounds'], isEmpty);
    expect(calls, greaterThanOrEqualTo(2));
  });

  test('unsafe config ids are rejected', () async {
    final api = ApiService(
      client: MockClient((_) async => http.Response('{}', 200)),
      baseUrls: ['https://example.test'],
    );
    addTearDown(api.dispose);

    expect(
      () => api.fetchXrayConfig('../secret'),
      throwsA(isA<Exception>()),
    );
  });
}
