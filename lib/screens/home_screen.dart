import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../controllers/split_tunneling_controller.dart';
import '../controllers/vpn_controller.dart';
import '../theme/app_theme.dart';
import '../theme/i18n.dart';
import '../theme/theme_controller.dart';
import '../widgets/country_flag.dart';
import '../widgets/directional_chevron.dart';
import 'locations_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  StreamSubscription<void>? _speedSub;
  int _downBps = 0;
  int _upBps = 0;
  bool _isResumed = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startSpeedPolling();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<VpnController>().syncStatus();
    });
  }

  void _startSpeedPolling() {
    _speedSub = Stream.periodic(const Duration(seconds: 1)).listen((_) async {
      if (!mounted || !_isResumed) return;
      final vpn = context.read<VpnController>();
      if (vpn.status == ConnStatus.connected) {
        try {
          final sp = await vpn.getSpeed();
          if (!mounted) return;
          setState(() {
            _downBps = sp['downBps'] ?? 0;
            _upBps = sp['upBps'] ?? 0;
          });
        } catch (_) {
          // Ignore speed errors while connected.
        }
      } else if (_downBps != 0 || _upBps != 0) {
        setState(() {
          _downBps = 0;
          _upBps = 0;
        });
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isResumed = state == AppLifecycleState.resumed;
    if (_isResumed) {
      context.read<VpnController>().syncStatus();
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speedSub?.cancel();
    super.dispose();
  }

  String _formatSpeed(int bps) {
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  Future<void> _togglePower() async {
    HapticFeedback.mediumImpact();

    final vpn = context.read<VpnController>();
    if (vpn.status == ConnStatus.connected ||
        vpn.status == ConnStatus.connecting ||
        vpn.status == ConnStatus.switching) {
      await vpn.disconnect(waitForNative: true);
      HapticFeedback.lightImpact();
      return;
    }

    if (vpn.selectedMeta == null) {
      final res = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => const LocationsScreen()),
      );
      if (res == true && mounted) {
        final splitController = context.read<SplitTunnelingController>();
        await context.read<VpnController>().connect(splitController);
        _showConnectResult();
      }
    } else {
      final splitController = context.read<SplitTunnelingController>();
      await context.read<VpnController>().connect(splitController);
      _showConnectResult();
    }
  }

  Future<void> _reconnect() async {
    final vpn = context.read<VpnController>();
    final split = context.read<SplitTunnelingController>();
    await vpn.reconnect(split);
    _showConnectResult();
  }

  /// خطای آخرین تلاش اتصال یا هشدار adblock را نشان می‌دهد.
  void _showConnectResult() {
    if (!mounted) return;
    final vpn = context.read<VpnController>();
    final t = context.read<I18n>();

    if (vpn.lastErrorKind != null) {
      final kind = vpn.lastErrorKind!;
      final String message;
      switch (kind) {
        case VpnErrorKind.configFailed:
          message = t.t('errConfigFailed');
          break;
        case VpnErrorKind.permissionDenied:
          message = t.t('errPermissionDenied');
          break;
        case VpnErrorKind.startFailed:
          final reason = (vpn.lastErrorDetail ?? '').trim();
          message = reason.isEmpty
              ? t.t('errStartFailed')
              : '${t.t('errStartFailed')} ($reason)';
          break;
        case VpnErrorKind.emptyInclusiveSelection:
          message = t.t('errEmptyInclusive');
          break;
        case VpnErrorKind.unknown:
          message = t.t('errUnknown');
          break;
      }
      vpn.clearError();
      _showSnack(message);
    } else if (vpn.adblockFallbackUsed) {
      _showSnack(t.t('adblockUnavailable'));
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    final colors = context.read<ThemeController>().colors;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, style: TextStyle(color: colors.text)),
        backgroundColor: colors.bgElevated,
        behavior: SnackBarBehavior.floating,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final t = context.watch<I18n>();
    final vpn = context.watch<VpnController>();

    final isConn = vpn.status == ConnStatus.connected;
    final isConnecting = vpn.status == ConnStatus.connecting;
    final isSwitching = vpn.status == ConnStatus.switching;
    final isBusy = isConnecting || isSwitching;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        title: Text(
          t.t('appTitle'),
          style: TextStyle(color: colors.text, fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.settings_outlined, color: colors.text),
            tooltip: t.t('settings'),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight:
                      (constraints.maxHeight - 32).clamp(0, double.infinity).toDouble(),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── کارت انتخاب لوکیشن ────────────────────────────────
                    InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LocationsScreen(),
                        ),
                      ),
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: colors.bgElevated,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: colors.border),
                        ),
                        child: Row(
                          children: [
                            if (vpn.selectedMeta != null)
                              CountryFlag(
                                countryCode: vpn.selectedMeta!.countryCode,
                                width: 28,
                                height: 20,
                              )
                            else
                              Icon(Icons.public,
                                  color: colors.accent, size: 24),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    vpn.selectedMeta != null
                                        ? '${vpn.selectedMeta!.country} - ${vpn.selectedMeta!.city}'
                                        : t.t('selectLocation'),
                                    style: TextStyle(
                                      color: colors.text,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    vpn.selectedMeta != null
                                        ? t.t('clickToChoose')
                                        : t.t('selectLocation'),
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            DirectionalChevron(color: colors.textSecondary),
                          ],
                        ),
                      ),
                    ),

                    if (vpn.needsReconnect) ...[
                      const SizedBox(height: 10),
                      _buildReconnectBanner(colors, t),
                    ],

                    const SizedBox(height: 40),

                    // ── دکمه مرکزی Power ────────────────────────────────
                    Center(
                      child: Semantics(
                        button: true,
                        label: isConn
                            ? t.t('disconnect')
                            : t.t('connect'),
                        child: GestureDetector(
                          onTap: _togglePower,
                          child: Container(
                            width: 170,
                            height: 170,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.bgElevated,
                              border: Border.all(
                                color: isConn
                                    ? colors.success
                                    : (isBusy ? colors.warning : colors.border),
                                width: 4,
                              ),
                              boxShadow: isConn
                                  ? [
                                      BoxShadow(
                                        color: colors.success
                                            .withValues(alpha: 0.3),
                                        blurRadius: 30,
                                        spreadRadius: 5,
                                      )
                                    ]
                                  : [],
                            ),
                            child: Center(
                              child: isBusy
                                  ? SizedBox(
                                      width: 60,
                                      height: 60,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 4,
                                        color: colors.warning,
                                      ),
                                    )
                                  : Icon(
                                      Icons.power_settings_new_rounded,
                                      size: 70,
                                      color: isConn
                                          ? colors.success
                                          : colors.textMuted,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        isConn
                            ? t.t('connected')
                            : isSwitching
                                ? t.t('switching')
                                : isConnecting
                                    ? t.t('connecting')
                                    : t.t('disconnected'),
                        style: TextStyle(
                          color: isConn ? colors.success : colors.textSecondary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),

                    // ── متریک زنده سرعت دانلود و آپلود ───────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                        horizontal: 20,
                      ),
                      decoration: BoxDecoration(
                        color: colors.bgElevated,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.arrow_downward_rounded,
                                  color: colors.accent, size: 20),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.t('download'),
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 11,
                                      )),
                                  Text(
                                    _formatSpeed(_downBps),
                                    style: TextStyle(
                                      color: colors.text,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Container(width: 1, height: 28, color: colors.border),
                          Row(
                            children: [
                              Icon(Icons.arrow_upward_rounded,
                                  color: colors.accent3, size: 20),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(t.t('upload'),
                                      style: TextStyle(
                                        color: colors.textSecondary,
                                        fontSize: 11,
                                      )),
                                  Text(
                                    _formatSpeed(_upBps),
                                    style: TextStyle(
                                      color: colors.text,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildReconnectBanner(AppColors colors, I18n t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.bgElevated2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: colors.warning, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              t.t('reconnectToApply'),
              style: TextStyle(color: colors.textSecondary, fontSize: 11),
            ),
          ),
          TextButton(
            onPressed: _reconnect,
            child: Text(t.t('reconnect')),
          ),
        ],
      ),
    );
  }
}
