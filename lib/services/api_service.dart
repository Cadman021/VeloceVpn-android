import 'dart:convert';
import 'package:http/http.dart' as http;
import 'models.dart';

const String kCentralApiBase = 'https://api.honeyface.ir';

class ApiService {
  Future<List<CountryGroup>> fetchCandidates() async {
    final res = await http
        .get(Uri.parse('$kCentralApiBase/api/v1/candidates.json'))
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) {
      throw Exception('candidates_fetch_failed_${res.statusCode}');
    }

    final body = jsonDecode(res.body) as Map<String, dynamic>;
    final List<dynamic> items = body['data'] as List<dynamic>? ?? [];

    final Map<String, CountryGroup> grouped = {};
    for (final raw in items) {
      final item = raw as Map<String, dynamic>;
      final code = (item['country_code'] as String?)?.toLowerCase() ?? 'xx';
      final name = item['country'] as String? ?? 'Unknown';

      grouped.putIfAbsent(
        code,
        () => CountryGroup(countryName: name, countryCode: code, locations: []),
      );
      grouped[code]!.locations.add(CityLocation.fromCandidate(item));
    }

    final list = grouped.values.toList()
      ..sort((a, b) => a.countryName.compareTo(b.countryName));
    return list;
  }

  /// JSON آماده‌ی Xray برای یک config_id. بک‌اند استاتیک است (publish.py):
  ///   adblock=false → `/api/v1/xray/ID.json`
  ///   adblock=true  → `/api/v1/xray/ID.adblock.json`
  /// قرارداد قدیمی داینامیک (?config_id=...) روی هاست استاتیک همیشه
  /// صفحه‌ی index.html را برمی‌گرداند و باعث FormatException می‌شد.
  Future<Map<String, dynamic>> fetchXrayConfig(String configId, {bool adblock = false}) async {
    final suffix = adblock ? '.adblock' : '';
    final uri = Uri.parse('$kCentralApiBase/api/v1/xray/$configId$suffix.json');
    final res = await http.get(uri).timeout(const Duration(seconds: 10));

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
    return config;
  }

  /// JSON را با خطای معنادار دیکد می‌کند تا HTML سرور به‌جای
  /// FormatException گنگ، با پیش‌نمایش بدنه گزارش شود.
  static Map<String, dynamic> _decodeJsonBody(http.Response res, String what) {
    try {
      return jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      final preview = res.body.length > 120 ? '${res.body.substring(0, 120)}...' : res.body;
      throw Exception(
        '$what is not JSON (HTTP ${res.statusCode}, '
        'content-type: ${res.headers['content-type'] ?? 'unknown'}): $preview',
      );
    }
  }
}
