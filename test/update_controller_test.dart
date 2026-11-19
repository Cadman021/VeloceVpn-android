import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veloce_vpn/controllers/update_controller.dart';
import 'package:veloce_vpn/services/update_service.dart';

class _FakeUpdateService extends UpdateService {
  _FakeUpdateService(this.release);
  ReleaseInfo? release;
  int calls = 0;

  @override
  Future<ReleaseInfo?> fetchLatest({String? currentVersion}) async {
    calls++;
    return release;
  }

  @override
  void dispose() {}
}

const _release = ReleaseInfo(
  version: '1.1.0',
  tag: 'v1.1.0',
  htmlUrl: 'https://example.invalid/release',
  notes: 'Release notes',
);

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('shows and dismisses an available update', () async {
    final service = _FakeUpdateService(_release);
    final controller = UpdateController(
      service: service,
      currentVersionLoader: () async => '1.0.0',
    );
    addTearDown(controller.dispose);

    await controller.check(force: true);
    expect(controller.available?.version, '1.1.0');
    expect(controller.error, isNull);

    await controller.dismiss();
    expect(controller.available, isNull);

    final next = UpdateController(
      service: _FakeUpdateService(_release),
      currentVersionLoader: () async => '1.0.0',
    );
    addTearDown(next.dispose);
    await next.load();
    expect(next.available, isNull, reason: 'ignored release must stay hidden');
  });

  test('does not hit the network twice within 24 hours', () async {
    final service = _FakeUpdateService(_release);
    final controller = UpdateController(
      service: service,
      currentVersionLoader: () async => '1.0.0',
    );
    addTearDown(controller.dispose);

    await controller.check(force: true);
    expect(service.calls, 1);

    final second = UpdateController(
      service: service,
      currentVersionLoader: () async => '1.0.0',
    );
    addTearDown(second.dispose);
    await second.check();
    expect(service.calls, 1);
  });

  test('clear result when the installed version is current', () async {
    final service = _FakeUpdateService(null);
    final controller = UpdateController(
      service: service,
      currentVersionLoader: () async => '1.1.0',
    );
    addTearDown(controller.dispose);

    await controller.check(force: true);
    expect(controller.available, isNull);
    expect(controller.error, isNull);
  });
}
