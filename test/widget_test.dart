import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veloce_vpn/controllers/split_tunneling_controller.dart';
import 'package:veloce_vpn/controllers/update_controller.dart';
import 'package:veloce_vpn/controllers/vpn_controller.dart';
import 'package:veloce_vpn/main.dart';
import 'package:veloce_vpn/theme/i18n.dart';
import 'package:veloce_vpn/theme/theme_controller.dart';

Future<TextDirection> _directionFor(WidgetTester tester, String lang) async {
  SharedPreferences.setMockInitialValues({});
  final i18n = I18n();
  await i18n.setLang(lang);

  TextDirection? captured;
  await tester.pumpWidget(
    VeloceApp(
      themeController: ThemeController(),
      i18n: i18n,
      vpn: VpnController(),
      split: SplitTunnelingController(),
      update: UpdateController(),
      home: Builder(
        builder: (context) {
          captured = Directionality.of(context);
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  return captured ?? TextDirection.ltr;
}

void main() {
  testWidgets('Persian app content is RTL', (tester) async {
    expect(await _directionFor(tester, 'fa'), TextDirection.rtl);
  });

  testWidgets('English app content is LTR', (tester) async {
    expect(await _directionFor(tester, 'en'), TextDirection.ltr);
  });

  test('all translations contain the English key set', () {
    final i18n = I18n();
    final english = i18n.keysFor('en');
    expect(english, isNotEmpty);
    for (final language in kLanguages) {
      expect(
        i18n.keysFor(language.code),
        containsAll(english),
        reason: 'missing keys in ${language.code}',
      );
    }
  });
}
