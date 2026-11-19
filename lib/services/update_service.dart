import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_version.dart';

const String kGithubRepository = 'Cadman021/VeloceVpn-android';
const String kGithubReleasesUrl =
    'https://github.com/Cadman021/VeloceVpn-android/releases';
const String _latestReleaseApi =
    'https://api.github.com/repos/Cadman021/VeloceVpn-android/releases/latest';

class ReleaseInfo {
  const ReleaseInfo({
    required this.version,
    required this.tag,
    required this.htmlUrl,
    required this.notes,
    this.publishedAt,
  });

  /// Clean version without a leading `v` (e.g. `1.1.0`).
  final String version;
  final String tag;
  final String htmlUrl;
  final String notes;
  final DateTime? publishedAt;

  Map<String, dynamic> toJson() => {
        'version': version,
        'tag': tag,
        'htmlUrl': htmlUrl,
        'notes': notes,
        'publishedAt': publishedAt?.toIso8601String(),
      };

  static ReleaseInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final map = Map<String, dynamic>.from(json);
    final version = map['version'];
    final tag = map['tag'];
    final htmlUrl = map['htmlUrl'];
    if (version is! String || tag is! String || htmlUrl is! String) {
      return null;
    }
    return ReleaseInfo(
      version: version,
      tag: tag,
      htmlUrl: htmlUrl,
      notes: map['notes'] is String ? map['notes'] as String : '',
      publishedAt: DateTime.tryParse(
        map['publishedAt'] is String ? map['publishedAt'] as String : '',
      ),
    );
  }
}

class UpdateCheckException implements Exception {
  const UpdateCheckException(this.message);
  final String message;

  @override
  String toString() => 'UpdateCheckException($message)';
}

class UpdateService {
  UpdateService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Returns the latest public release, or `null` when the installed version
  /// is already current (or the repository has no published release yet).
  Future<ReleaseInfo?> fetchLatest({String? currentVersion}) async {
    final response = await _client.get(
      Uri.parse(_latestReleaseApi),
      headers: const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
        'User-Agent': 'Veloce-VPN-Android-Updater',
      },
    ).timeout(const Duration(seconds: 12));

    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw UpdateCheckException('http_${response.statusCode}');
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw const UpdateCheckException('invalid_json');
    }
    if (decoded is! Map) throw const UpdateCheckException('invalid_release');

    final tag = decoded['tag_name'];
    final htmlUrl = decoded['html_url'];
    if (tag is! String || htmlUrl is! String) {
      throw const UpdateCheckException('invalid_release');
    }

    final parsed = AppVersion.tryParse(tag);
    if (parsed == null) return null;

    final release = ReleaseInfo(
      version: parsed.toString(),
      tag: tag,
      htmlUrl: htmlUrl,
      notes: decoded['body'] is String ? decoded['body'] as String : '',
      publishedAt: DateTime.tryParse(
        decoded['published_at'] is String
            ? decoded['published_at'] as String
            : '',
      ),
    );

    if (currentVersion != null && !parsed.isNewerThan(currentVersion)) {
      return null;
    }
    return release;
  }

  void dispose() => _client.close();
}
