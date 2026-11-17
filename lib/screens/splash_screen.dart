import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/vpn_controller.dart';
import '../theme/theme_controller.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final vpn = context.read<VpnController>();

    // Do not hold the splash screen hostage to a slow/blocked network. The
    // preload keeps running in the background and Home/Locations update when
    // it finishes (or show the offline cache/retry state).
    await Future.wait([
      Future<void>.delayed(const Duration(milliseconds: 800)),
      vpn
          .preloadLocations()
          .timeout(const Duration(seconds: 2), onTimeout: () => false),
    ]);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, animation, __, child) =>
              FadeTransition(opacity: animation, child: child),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;

    return Scaffold(
      backgroundColor: colors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Image.asset(
                'assets/images/logo.png',
                width: 140,
                height: 140,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              bottom: 30,
              left: 40,
              right: 40,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: colors.border,
                  valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
