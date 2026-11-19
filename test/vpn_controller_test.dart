import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:veloce_vpn/controllers/split_tunneling_controller.dart';
import 'package:veloce_vpn/controllers/vpn_controller.dart';
import 'package:veloce_vpn/services/api_service.dart';
import 'package:veloce_vpn/services/models.dart';

class _FakeApi extends ApiService {
  _FakeApi({this.failNormal = false, this.failAdblock = false});

  final bool failNormal;
  final bool failAdblock;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> fetchXrayConfig(
    String configId, {
    bool adblock = false,
  }) async {
    calls++;
    if (adblock && failAdblock) throw Exception('adblock_missing');
    if (!adblock && failNormal) throw Exception('normal_missing');
    return {
      'outbounds': [
        {'tag': 'proxy', 'protocol': 'freedom'},
      ],
    };
  }
}

class _FakeBridge extends NativeVpnBridge {
  _FakeBridge({this.startResult = true});

  bool startResult;
  bool running = false;
  bool reconnecting = false;
  int startCalls = 0;

  @override
  Future<bool> start({
    required Map<String, dynamic> xrayConfig,
    required int localSocksPort,
    required bool splitEnabled,
    required String splitMode,
    required List<String> selectedApps,
    required List<String> excludedIps,
  }) async {
    startCalls++;
    running = startResult;
    return startResult;
  }

  @override
  Future<void> stop() async {
    running = false;
  }

  @override
  Future<bool> status() async => running;

  @override
  Future<bool> isNativeReconnecting() async => reconnecting;

  @override
  Future<Map<String, int>> speed() async =>
      {'downBps': 1000, 'upBps': 500};
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const meta = SelectedLocationMeta(
    id: 'tehran-1',
    country: 'Iran',
    city: 'Tehran',
    countryCode: 'ir',
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('connect succeeds and records the connected server', () async {
    final bridge = _FakeBridge();
    final api = _FakeApi();
    final vpn = VpnController(api: api, bridge: bridge);
    addTearDown(vpn.dispose);
    addTearDown(api.dispose);

    await vpn.selectLocation(meta);
    final ok = await vpn.connect(SplitTunnelingController());

    expect(ok, isTrue);
    expect(vpn.status, ConnStatus.connected);
    expect(vpn.connectedMeta?.id, meta.id);
    expect(bridge.startCalls, 1);
  });

  test('config download failure is surfaced', () async {
    final bridge = _FakeBridge();
    final api = _FakeApi(failNormal: true);
    final vpn = VpnController(api: api, bridge: bridge);
    addTearDown(vpn.dispose);
    addTearDown(api.dispose);

    await vpn.selectLocation(meta);
    final ok = await vpn.connect(SplitTunnelingController());

    expect(ok, isFalse);
    expect(vpn.status, ConnStatus.disconnected);
    expect(vpn.lastErrorKind, VpnErrorKind.configFailed);
    expect(bridge.startCalls, 0);
  });

  test('adblock variant falls back to the normal config', () async {
    final bridge = _FakeBridge();
    final api = _FakeApi(failAdblock: true);
    final vpn = VpnController(api: api, bridge: bridge);
    addTearDown(vpn.dispose);
    addTearDown(api.dispose);

    vpn.adblockOn = true;
    await vpn.selectLocation(meta);
    final ok = await vpn.connect(SplitTunnelingController());

    expect(ok, isTrue);
    expect(vpn.adblockFallbackUsed, isTrue);
    expect(vpn.status, ConnStatus.connected);
    expect(api.calls, 2);
  });

  test('inclusive mode with no apps is rejected before starting Xray', () async {
    final bridge = _FakeBridge();
    final api = _FakeApi();
    final vpn = VpnController(api: api, bridge: bridge);
    addTearDown(vpn.dispose);
    addTearDown(api.dispose);

    final split = SplitTunnelingController()
      ..isEnabled = true
      ..mode = 'inclusive';
    await vpn.selectLocation(meta);
    final ok = await vpn.connect(split);

    expect(ok, isFalse);
    expect(vpn.lastErrorKind, VpnErrorKind.emptyInclusiveSelection);
    expect(bridge.startCalls, 0);
  });

  test('permission denial maps to permissionDenied', () async {
    final bridge = _FakeBridge(startResult: false);
    final api = _FakeApi();
    final vpn = VpnController(api: api, bridge: bridge);
    addTearDown(vpn.dispose);
    addTearDown(api.dispose);

    await vpn.selectLocation(meta);
    final ok = await vpn.connect(SplitTunnelingController());

    expect(ok, isFalse);
    expect(vpn.lastErrorKind, VpnErrorKind.permissionDenied);
  });

  test('syncStatus follows the native service', () async {
    final bridge = _FakeBridge();
    final vpn = VpnController(api: _FakeApi(), bridge: bridge);
    addTearDown(vpn.dispose);

    bridge.running = true;
    await vpn.syncStatus();
    expect(vpn.status, ConnStatus.connected);

    bridge.running = false;
    bridge.reconnecting = true;
    await vpn.syncStatus();
    expect(vpn.status, ConnStatus.reconnecting);

    bridge.reconnecting = false;
    await vpn.syncStatus();
    expect(vpn.status, ConnStatus.disconnected);
  });

  test('switching location disconnects and reconnects', () async {
    final bridge = _FakeBridge();
    final api = _FakeApi();
    final vpn = VpnController(api: api, bridge: bridge);
    addTearDown(vpn.dispose);
    addTearDown(api.dispose);

    await vpn.selectLocation(meta);
    await vpn.connect(SplitTunnelingController());
    expect(vpn.status, ConnStatus.connected);

    const next = SelectedLocationMeta(
      id: 'berlin-1',
      country: 'Germany',
      city: 'Berlin',
      countryCode: 'de',
    );
    final ok = await vpn.switchLocation(next, SplitTunnelingController());

    expect(ok, isTrue);
    expect(vpn.selectedMeta?.id, next.id);
    expect(vpn.connectedMeta?.id, next.id);
    expect(bridge.startCalls, 2);
  });
}
