import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'models.dart';

/// Primary backend. Keep the list ordered: the next entry is only tried when
/// the previous one fails with a retryable error.
const List<String> kCentralApiBases = ['https://api.honeyface.ir'];

const Duration kApiTimeout = Duration(seconds: 10);
const Duration _retryDelay = Duration(milliseconds: 300);

final RegExp _configIdPattern = RegExp(r'^[A-Za-z0-9._-]+$');

class ApiService {
  ApiService({http.Client? client, List<String>? baseUrls})
      : _client = client ?? http.Client(),
        _baseUrls = (baseUrls ?? kCentralApiBases)
            .map((e) => e.replaceAll(RegExp(r'/+$'), ''))
            .where((e) => e.isNotEmpty)
            .toList(growable: false);

  final http.Client _client;
  final List<String> _baseUrls;

  /// Last successfully downloaded config per config id/variant. This makes
  /// reconnect/ping resilient to a short backend outage without writing
  /// credentials to disk.
  final Map<String, Map<String, dynamic>> _configCache = {};

  Future<List<CountryGroup>> fetchCandidates() async {
    final res = await _get('/api/v1/candidates.json');

    if (res.statusCode != 200) {
      throw Exception('candidates_fetch_failed_${res.statusCode}');
    }

    final body = _decodeJsonBody(res, 'candidates');
    final rawItems = body['data'];
    if (rawItems is! List) {
      throw Exception('candidates_invalid_data');
    }

    final grouped = <String, CountryGroup>{};
    final seenIds = <String>{};

    for (final raw in rawItems) {
      if (raw is! Map) continue;
      final item = Map<String, dynamic>.from(raw);

      final rawId = item['id'];
      final id = rawId is String ? rawId : rawId?.toString();
      if (id == null || !_isSafeConfigId(id) || !seenIds.add(id)) {
        continue;
      }

      final rawCode = item['country_code'];
      final code = (rawCode is String ? rawCode : rawCode?.toString() ?? 'xx')
          .trim()
          .toLowerCase();
      final safeCode = code.isEmpty ? 'xx' : code;
      final rawCountry = item['country'];
      final name =
          (rawCountry is String ? rawCountry : rawCountry?.toString() ?? '')
              .trim();
      final rawCity = item['city'];
      final city =
          (rawCity is String ? rawCity : rawCity?.toString() ?? '').trim();

      // Keep the normalized id/code in the map so CityLocation.fromCandidate
      // sees the same values we validated.
      item['id'] = id;
      item['country_code'] = safeCode;
      item['country'] = name.isEmpty ? 'Unknown' : name;
      item['city'] = city.isEmpty ? 'Unknown City' : city;

      grouped.putIfAbsent(
        safeCode,
        () => CountryGroup(
          countryName: name.isEmpty ? 'Unknown' : name,
          countryCode: safeCode,
          locations: [],
        ),
      );
      grouped[safeCode]!.locations.add(CityLocation.fromCandidate(item));
    }

    return grouped.values.toList()
      ..sort((a, b) => a.countryName.compareTo(b.countryName));
  }

  /// JSON آماده‌ی Xray برای یک config_id. بک‌اند استاتیک است (publish.py):
  ///   adblock=false → `/api/v1/xray/ID.json`
  ///   adblock=true  → `/api/v1/xray/ID.adblock.json`
  /// قرارداد قدیمی داینامیک (?config_id=...) روی هاست استاتیک همیشه
  /// صفحه‌ی index.html را برمی‌گرداند و باعث FormatException می‌شد.
  Future<Map<String, dynamic>> fetchXrayConfig(
    String configId, {
    bool adblock = false,
  }) async {
    if (!_isSafeConfigId(configId)) {
      throw Exception('invalid_config_id');
    }

    final suffix = adblock ? '.adblock' : '';
    final cacheKey = '$configId$suffix';

    try {
      final res = await _get('/api/v1/xray/$configId$suffix.json');
      if (res.statusCode != 200) {
        throw Exception('xray_config_fetch_failed_${res.statusCode}');
      }

      final body = _decodeJsonBody(res, 'xray-config for $configId');
      final config = body['xray_config'];
      if (config is! Map<String, dynamic>) {
        throw Exception(
          'xray_config_missing_key for $configId (keys: ${body.keys.join(',')})',
        );
      }

      final result = Map<String, dynamic>.from(config);
      _configCache[cacheKey] = result;
      return result;
    } catch (e) {
      final cached = _configCache[cacheKey];
      if (cached != null) {
        debugPrint('[Api] using cached config for $cacheKey after error: $e');
        return Map<String, dynamic>.from(cached);
      }
      rethrow;
    }
  }

  static bool _isSafeConfigId(String id) {
    if (id.isEmpty || id.length > 128) return false;
    if (id.contains('..') || id.contains('/') || id.contains('\\')) {
      return false;
    }
    return _configIdPattern.hasMatch(id);
  }

  Future<http.Response> _get(String path) async {
    if (_baseUrls.isEmpty) {
      throw Exception('no_api_base_url_configured');
    }

    Object? lastError;
    http.Response? lastResponse;

    for (final base in _baseUrls) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final res = await _client
              .get(Uri.parse('$base$path'))
              .timeout(kApiTimeout);

          if (res.statusCode == 200) return res;

          lastResponse = res;

          // A missing config/variant is a definitive answer; don't retry it.
          if (res.statusCode == 400 ||
              res.statusCode == 401 ||
              res.statusCode == 403 ||
              res.statusCode == 404) {
            return res;
          }

          if (res.statusCode != 429 && res.statusCode < 500) {
            return res;
          }
        } catch (e) {
          lastError = e;
        }

        if (attempt == 0) {
          await Future<void>.delayed(_retryDelay);
        }
      }
    }

    if (lastResponse != null) return lastResponse;
    throw Exception('network_error: $lastError');
  }

  /// JSON را با خطای معنادار دیکد می‌کند تا HTML سرور به‌جای
  /// FormatException گنگ، با پیش‌نمایش بدنه گزارش شود.
  static Map<String, dynamic> _decodeJsonBody(http.Response res, String what) {
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('expected a JSON object');
      }
      return decoded;
    } catch (_) {
      final preview = res.body.length > 120
          ? '${res.body.substring(0, 120)}...'
          : res.body;
      throw Exception(
        '$what is not JSON (HTTP ${res.statusCode}, '
        'content-type: ${res.headers['content-type'] ?? 'unknown'}): $preview',
      );
    }
  }

  void dispose() => _client.close();
}
