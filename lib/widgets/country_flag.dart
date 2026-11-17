import 'package:flutter/material.dart';

/// A bundled, network-free country flag.
///
/// Flags are rendered as Unicode regional-indicator emoji. This avoids a
/// request to a third-party CDN for every row in the server list (privacy,
/// startup latency and reliability on filtered networks).
class CountryFlag extends StatelessWidget {
  final String countryCode;
  final double width;
  final double height;

  const CountryFlag({
    super.key,
    required this.countryCode,
    this.width = 28,
    this.height = 20,
  });

  static const Map<String, String> _aliases = {
    'uk': 'gb',
    'el': 'gr',
  };

  String _normalized(String code) {
    final lower = code.trim().toLowerCase();
    return _aliases[lower] ?? lower;
  }

  String _toEmoji(String code) {
    if (code.length != 2 ||
        !RegExp(r'^[a-z]{2}$').hasMatch(code)) {
      return '🌐';
    }
    final int first = code.toUpperCase().codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int second = code.toUpperCase().codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  @override
  Widget build(BuildContext context) {
    final code = _normalized(countryCode);
    final colors = Theme.of(context).colorScheme;

    if (code == 'xx' || code.isEmpty) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: colors.onSurface.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          Icons.public,
          size: height * 0.7,
          color: colors.onSurface.withValues(alpha: 0.5),
        ),
      );
    }

    return Semantics(
      label: code.toUpperCase(),
      child: SizedBox(
        width: width,
        height: height,
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: Text(
              _toEmoji(code),
              style: TextStyle(fontSize: height * 0.95),
            ),
          ),
        ),
      ),
    );
  }
}
