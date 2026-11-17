import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veloce_vpn/controllers/split_tunneling_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'split_enabled': true,
      'split_mode': 'inclusive',
      'split_show_system': true,
      'selected_packages': ['com.example.bank'],
      'excluded_ips': ['example.com'],
    });
  });

  test('cold-start loadSettings restores saved split configuration', () async {
    final controller = SplitTunnelingController();
    await controller.loadSettings();

    expect(controller.settingsLoaded, isTrue);
    expect(controller.isEnabled, isTrue);
    expect(controller.mode, 'inclusive');
    expect(controller.showSystemApps, isTrue);
    expect(controller.selectedPackages, ['com.example.bank']);
    expect(controller.excludedIpsDomains, ['example.com']);
  });

  test('addIpExclusion trims and de-duplicates', () async {
    final controller = SplitTunnelingController();
    await controller.loadSettings();

    controller.addIpExclusion('  10.0.0.1/24  ');
    controller.addIpExclusion('10.0.0.1/24');

    expect(controller.excludedIpsDomains, contains('10.0.0.1/24'));
    expect(
      controller.excludedIpsDomains.where((e) => e == '10.0.0.1/24').length,
      1,
    );
  });
}
