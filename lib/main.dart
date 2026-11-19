import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:veloce_vpn/controllers/split_tunneling_controller.dart';
import 'theme/theme_controller.dart';
import 'theme/i18n.dart';
import 'theme/app_theme.dart';
import 'controllers/update_controller.dart';
import 'controllers/vpn_controller.dart';
import 'screens/splash_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final themeController = ThemeController();
  final i18n = I18n();
  final vpn = VpnController();
  final split = SplitTunnelingController();
  final update = UpdateController();

  await Future.wait([
    themeController.load(),
    i18n.load(),
    vpn.initPreferences(),
    // Split settings must be available before the first connect attempt;
    // otherwise a cold start silently connects with split tunneling disabled.
    split.loadSettings(),
  ]);

  // AGPL-3.0 appropriate legal notices are available from the in-app
  // "Open-source licenses" page.
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/licenses/AGPL-3.0.txt');
    yield LicenseEntryWithLineBreaks(const ['Veloce VPN'], text);
  });

  runApp(VeloceApp(
    themeController: themeController,
    i18n: i18n,
    vpn: vpn,
    split: split,
    update: update,
  ));
}

class VeloceApp extends StatelessWidget {
  final ThemeController themeController;
  final I18n i18n;
  final VpnController vpn;
  final SplitTunnelingController split;
  final UpdateController update;

  /// Optional home widget for widget tests. Defaults to the splash screen.
  final Widget? home;

  const VeloceApp({
    super.key,
    required this.themeController,
    required this.i18n,
    required this.vpn,
    required this.split,
    required this.update,
    this.home,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: themeController),
        ChangeNotifierProvider.value(value: i18n),
        ChangeNotifierProvider.value(value: vpn),
        ChangeNotifierProvider.value(value: split),
        ChangeNotifierProvider.value(value: update),
      ],
      child: Consumer2<ThemeController, I18n>(
        builder: (context, theme, lang, _) {
          return MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Veloce VPN',
            theme: buildAppTheme(theme.colors, theme.brightness),
            locale: Locale(lang.lang),
            supportedLocales:
                kLanguages.map((l) => Locale(l.code)).toList(growable: false),
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            // MaterialApp installs its own Directionality from the locale
            // above; wrapping it from outside the app is not enough.
            builder: (context, child) => Directionality(
              textDirection: lang.dir,
              child: child ?? const SizedBox.shrink(),
            ),
            home: home ?? const SplashScreen(),
          );
        },
      ),
    );
  }
}
