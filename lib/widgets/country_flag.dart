import 'package:flutter/material.dart';

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

  static final Map<String, ImageProvider> _providerCache = {};

  ImageProvider _providerFor(String code) {
    return _providerCache.putIfAbsent(
      code,
      () => NetworkImage('https://flagcdn.com/w40/$code.png'),
    );
  }

  String _toEmoji(String code) {
    if (code.length != 2) return '🌐';
    final int first = code.toUpperCase().codeUnitAt(0) - 0x41 + 0x1F1E6;
    final int second = code.toUpperCase().codeUnitAt(1) - 0x41 + 0x1F1E6;
    return String.fromCharCode(first) + String.fromCharCode(second);
  }

  @override
  Widget build(BuildContext context) {
    final code = countryCode.trim().toLowerCase();
    if (code == 'xx' || code.isEmpty) {
      return Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFF2A2D37),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.public, size: 14, color: Colors.white54),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Image(
        image: _providerFor(code),
        width: width,
        height: height,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        filterQuality: FilterQuality.low,
        errorBuilder: (_, __, ___) => Text(
          _toEmoji(code),
          style: TextStyle(fontSize: height * 0.75),
        ),
      ),
    );
  }
}