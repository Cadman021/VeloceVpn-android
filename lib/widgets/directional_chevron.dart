import 'package:flutter/material.dart';

/// Chevron that points in the reading direction (RTL-aware).
class DirectionalChevron extends StatelessWidget {
  final Color color;
  final double size;

  const DirectionalChevron({
    super.key,
    required this.color,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Icon(
      isRtl ? Icons.chevron_left : Icons.chevron_right,
      color: color,
      size: size,
    );
  }
}
