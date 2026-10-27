import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/vpn_controller.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))..repeat();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    final vpn = context.read<VpnController>();
    
    // پیش‌بارگذاری لوکیشن‌ها همزمان با انیمیشن ورود
    await Future.wait([
      vpn.preloadLocations(),
      Future.delayed(const Duration(milliseconds: 1200)),
    ]);

    if (mounted) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 400),
          pageBuilder: (_, __, ___) => const HomeScreen(),
          transitionsBuilder: (_, animation, __, child) => FadeTransition(opacity: animation, child: child),
        ),
      );
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF16171B), // رنگ پس‌زمینه لودینگ (مشابه طراحی Veloce)
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              // فراخوانی تصویر لوگوی اختصاصی شما
              child: Image.asset(
                'assets/images/logo.png',
                width: 140, // عرض لوگو
                height: 140, // ارتفاع لوگو
                fit: BoxFit.contain, // حفظ تناسب ابعاد تصویر
              ),
            ),
            Positioned(
              bottom: 30,
              left: 40,
              right: 40,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: const LinearProgressIndicator(
                  minHeight: 3,
                  backgroundColor: Color(0xFF232630),
                  valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2563EB)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}