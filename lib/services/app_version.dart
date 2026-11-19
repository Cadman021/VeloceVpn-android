/// Lightweight semantic-version comparison for GitHub release tags.
///
/// The app only needs to answer one question: is the release tag newer than
/// the installed `versionName`? Build metadata (`+1`) and a leading `v` are
/// ignored; malformed tags never trigger an update prompt.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.parts, {this.preRelease = false});

  final List<int> parts;
  final bool preRelease;

  static AppVersion? tryParse(String raw) {
    var value = raw.trim();
    if (value.toLowerCase().startsWith('v')) value = value.substring(1);
    value = value.split('+').first;
    if (value.isEmpty) return null;

    final prerelease = value.contains('-');
    final core = value.split('-').first;
    final pieces = core.split('.');
    if (pieces.isEmpty || pieces.length > 4) return null;

    final numbers = <int>[];
    for (final piece in pieces) {
      if (piece.isEmpty || !RegExp(r'^\d+$').hasMatch(piece)) return null;
      final parsed = int.tryParse(piece);
      if (parsed == null || parsed < 0) return null;
      numbers.add(parsed);
    }
    while (numbers.length < 3) {
      numbers.add(0);
    }
    return AppVersion(numbers, preRelease: prerelease);
  }

  @override
  int compareTo(AppVersion other) {
    for (var i = 0; i < 3; i++) {
      final diff = parts[i].compareTo(other.parts[i]);
      if (diff != 0) return diff;
    }
    // 1.0.0-beta is older than 1.0.0.
    if (preRelease == other.preRelease) return 0;
    return preRelease ? -1 : 1;
  }

  bool isNewerThan(String current) {
    final installed = AppVersion.tryParse(current);
    if (installed == null) return false;
    return compareTo(installed) > 0;
  }

  @override
  String toString() => parts.take(3).join('.');
}
