import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:veloce_vpn/controllers/split_tunneling_controller.dart';
import 'theme/theme_controller.dart';
import 'theme/i18n.dart';
import 'theme/app_theme.dart';
import 'controllers/vpn_controller.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = ThemeController();
  final i18n = I18n();
  final vpn = VpnController();

  await themeController.load();
  await i18n.load();
  await vpn.initPreferences();

  runApp(VeloceApp(themeController: themeController, i18n: i18n, vpn: vpn));
}

class VeloceApp extends StatelessWidget {
  final ThemeController themeController;
  final I18n i18n;
  final VpnController vpn;

  const VeloceApp({
    super.key,
    required this.themeController,
    required this.i18n,
    required this.vpn,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider.value(value: i18n),
        ChangeNotifierProvider.value(value: vpn),
        ChangeNotifierProvider(create: (_) => SplitTunnelingController()),
      ],
      child: Consumer2<ThemeController, I18n>(
        builder: (context, theme, lang, _) {
          return Directionality(
            textDirection: lang.dir,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              title: 'Veloce VPN',
              theme: buildAppTheme(theme.colors, theme.brightness),
              home: const SplashScreen(),
            ),
          );
        },
      ),
    );
  }
}