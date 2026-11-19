import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/split_tunneling_controller.dart';
import '../controllers/update_controller.dart';
import '../controllers/vpn_controller.dart';
import '../theme/app_theme.dart';
import '../theme/i18n.dart';
import '../theme/theme_controller.dart';
import '../services/update_service.dart';
import '../widgets/directional_chevron.dart';
import 'split_tunneling_screen.dart';

const String kGithubProfileUrl = 'https://github.com/Cadman021';
const String kPrivacyPolicyUrl =
    'https://github.com/Cadman021/VeloceVpn-android/blob/main/docs/privacy-policy.md';
const String kTermsOfServiceUrl =
    'https://github.com/Cadman021/VeloceVpn-android/blob/main/docs/terms-of-service.md';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final Future<PackageInfo> _packageInfo = PackageInfo.fromPlatform();

  @override
  Widget build(BuildContext context) {
    final colors = context.watch<ThemeController>().colors;
    final themeController = context.watch<ThemeController>();
    final t = context.watch<I18n>();
    final vpn = context.watch<VpnController>();
    final update = context.watch<UpdateController>();

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        title: Text(t.t('settings'), style: TextStyle(color: colors.text)),
        iconTheme: IconThemeData(color: colors.text),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // مسدودساز تبلیغات (AdBlock)
          _row(
            colors,
            label: t.t('adblock'),
            subtitle: t.t('adblockDesc'),
            trailing: Switch(
              value: vpn.adblockOn,
              activeThumbColor: colors.accent,
              onChanged: (v) => _setAdblock(v, vpn),
            ),
          ),
          if (vpn.needsReconnect) ...[
            const SizedBox(height: 10),
            _reconnectBanner(colors, t, vpn),
          ],
          const SizedBox(height: 12),

          // تونل‌بندی اختصاصی - هدایت به صفحه تنظیمات پیشرفته
          Consumer<SplitTunnelingController>(
            builder: (context, splitController, child) {
              final statusText = splitController.isEnabled
                  ? '${splitController.mode.toUpperCase()} '
                      '(${splitController.selectedPackages.length} ${t.t('apps')})'
                  : t.t('disabled');

              return _linkRow(
                colors,
                label: t.t('splitTunneling'),
                subtitle: statusText,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SplitTunnelingScreen(),
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),

          // انتخاب زبان
          _dropdownRow(
            colors,
            label: t.t('language'),
            trailing: DropdownButton<String>(
              value: t.lang,
              dropdownColor: colors.bgElevated2,
              underline: const SizedBox(),
              style: TextStyle(color: colors.text, fontSize: 13),
              items: kLanguages
                  .map((l) => DropdownMenuItem(value: l.code, child: Text(l.label)))
                  .toList(),
              onChanged: (v) {
                if (v != null) context.read<I18n>().setLang(v);
              },
            ),
          ),
          const SizedBox(height: 16),

          // انتخاب پوسته
          _dropdownRow(
            colors,
            label: t.t('theme'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _themePill(
                  colors,
                  t.t('dark'),
                  themeController.isDark,
                  () => themeController.setDark(true),
                ),
                const SizedBox(width: 6),
                _themePill(
                  colors,
                  t.t('light'),
                  !themeController.isDark,
                  () => themeController.setDark(false),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          _linkRow(
            colors,
            label: t.t('checkForUpdates'),
            subtitle: update.isChecking
                ? t.t('checking')
                : update.available != null
                    ? 'v${update.available!.version} ${t.t('updateAvailableShort')}'
                    : t.t('upToDate'),
            onTap: _checkUpdates,
          ),
          _linkRow(
            colors,
            label: t.t('diagnostics'),
            subtitle: t.t('diagnosticsHint'),
            onTap: _openDiagnostics,
          ),
          _linkRow(
            colors,
            label: t.t('privacyPolicy'),
            onTap: () => _openLink(kPrivacyPolicyUrl),
          ),
          _linkRow(
            colors,
            label: t.t('termsOfService'),
            onTap: () => _openLink(kTermsOfServiceUrl),
          ),
          _linkRow(
            colors,
            label: t.t('licenses'),
            onTap: _openLicenses,
          ),
          _linkRow(
            colors,
            label: t.t('sourceCode'),
            subtitle: 'AGPL-3.0',
            onTap: () => _openLink(
              'https://github.com/Cadman021/VeloceVpn-android',
            ),
          ),

          const SizedBox(height: 28),

          Center(
            child: Column(
              children: [
                FutureBuilder<PackageInfo>(
                  future: _packageInfo,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return Text(
                        'v…',
                        style: TextStyle(color: colors.textMuted, fontSize: 11),
                      );
                    }
                    final info = snapshot.data!;
                    final build = info.buildNumber.isEmpty
                        ? ''
                        : ' (${info.buildNumber})';
                    return Text(
                      'v${info.version}$build',
                      style: TextStyle(color: colors.textMuted, fontSize: 11),
                    );
                  },
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: () => _openLink(kGithubProfileUrl),
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          t.t('poweredBy'),
                          style: TextStyle(
                            color: colors.textMuted,
                            fontSize: 11,
                            decoration: TextDecoration.underline,
                            decorationColor: colors.textMuted,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.open_in_new,
                          size: 11,
                          color: colors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _setAdblock(bool value, VpnController vpn) async {
    final wasConnected = vpn.status == ConnStatus.connected;
    await vpn.setAdblock(value);
    if (!wasConnected || !mounted) return;

    // Ad-block is part of the downloaded Xray config, so it only applies
    // after a reconnect. Do it immediately instead of silently keeping the
    // old config.
    final split = context.read<SplitTunnelingController>();
    final ok = await vpn.reconnect(split);
    if (!ok && mounted) {
      final t = context.read<I18n>();
      final colors = context.read<ThemeController>().colors;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Text(
            t.t('errStartFailed'),
            style: TextStyle(color: colors.text),
          ),
          backgroundColor: colors.bgElevated,
          behavior: SnackBarBehavior.floating,
        ));
    }
  }

  Widget _row(
    AppColors colors, {
    required String label,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: colors.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _reconnectBanner(
    AppColors colors,
    I18n t,
    VpnController vpn,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.bgElevated2,
        border: Border.all(color: colors.warning.withValues(alpha: 0.5)),
        borderRadius: BorderRadius.circular(12),
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
            onPressed: () async {
              await vpn.reconnect(context.read<SplitTunnelingController>());
            },
            child: Text(t.t('reconnect')),
          ),
        ],
      ),
    );
  }

  Widget _dropdownRow(
    AppColors colors, {
    required String label,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: colors.text,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _linkRow(
    AppColors colors, {
    required String label,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: colors.bgElevated,
            border: Border.all(color: colors.border),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: colors.text,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              DirectionalChevron(color: colors.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _themePill(
    AppColors colors,
    String label,
    bool active,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          gradient: active ? AppColors.brandGradient : null,
          color: active ? null : colors.bgElevated2,
          borderRadius: BorderRadius.circular(20),
          border: active ? null : Border.all(color: colors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: active ? Colors.white : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Future<void> _checkUpdates() async {
    final update = context.read<UpdateController>();
    final t = context.read<I18n>();
    await update.check(force: true);
    if (!mounted) return;

    if (update.available != null) {
      _showUpdateDialog(update.available!);
      return;
    }
    if (update.error != null) {
      _showSnack(t.t('updateCheckFailed'));
      return;
    }
    _showSnack(t.t('upToDate'));
  }

  Future<void> _openDiagnostics() async {
    final vpn = context.read<VpnController>();
    final t = context.read<I18n>();
    final colors = context.read<ThemeController>().colors;
    Map<String, dynamic> native = const {};
    try {
      native = await vpn.bridge.diagnostics();
    } catch (e) {
      debugPrint('[Diagnostics] native snapshot unavailable: $e');
    }
    if (!mounted) return;

    String version = '?';
    String build = '';
    try {
      final info = await _packageInfo;
      version = info.version;
      build = info.buildNumber;
    } catch (_) {}

    String bytes(Object? value) {
      final n = value is num ? value.toInt() : 0;
      if (n < 1024) return '$n B';
      if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
      return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    final lastError = (native['lastError'] as String?)?.trim() ?? '';
    final lastErrorLabel = lastError.isEmpty ? 'none' : lastError;
    final buildLabel = build.isEmpty ? '' : ' ($build)';
    final report = [
      'Veloce VPN diagnostics',
      'App version: $version$buildLabel',
      'Android SDK: ${native['androidSdk'] ?? '?'}',
      'ABI: ${native['abi'] ?? '?'}',
      'VPN running: ${native['running'] ?? '?'}',
      'Starting: ${native['starting'] ?? '?'}',
      'Reconnecting: ${native['reconnecting'] ?? '?'}',
      'Reconnect attempts: ${native['reconnectAttempts'] ?? '?'}',
      'Health failures: ${native['healthFailures'] ?? '?'}',
      'Tunnel stats available: ${native['statsAvailable'] ?? '?'}',
      'Tunnel down: ${bytes(native['totalDownBytes'])}',
      'Tunnel up: ${bytes(native['totalUpBytes'])}',
      'Last error: $lastErrorLabel',
    ].join('\n');

    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.bgElevated,
        title: Text(t.t('diagnostics'), style: TextStyle(color: colors.text)),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480, maxHeight: 380),
          child: SingleChildScrollView(
            child: SelectableText(
              report,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                height: 1.45,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t.t('later')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.accent),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: report)).ignore();
              Navigator.of(dialogContext).pop();
              _showSnack(t.t('copied'));
            },
            child: Text(t.t('copy')),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog(ReleaseInfo release) {
    final t = context.read<I18n>();
    final colors = context.read<ThemeController>().colors;
    final notes = release.notes.trim();

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.bgElevated,
        title: Text(
          '${t.t('updateAvailable')} v${release.version}',
          style: TextStyle(color: colors.text),
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420, maxHeight: 300),
          child: SingleChildScrollView(
            child: SelectableText(
              notes.isEmpty ? t.t('updateAvailable') : notes,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 12,
                height: 1.45,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t.t('later')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: colors.accent),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _openLink(release.htmlUrl);
            },
            child: Text(t.t('updateNow')),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    final colors = context.read<ThemeController>().colors;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, style: TextStyle(color: colors.text)),
        backgroundColor: colors.bgElevated,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Future<void> _openLicenses() async {
    String version = '';
    try {
      final info = await _packageInfo;
      version = info.version;
    } catch (_) {
      // Show the license page even if package metadata is unavailable.
    }
    if (!mounted) return;

    showLicensePage(
      context: context,
      applicationName: 'Veloce VPN',
      applicationVersion: version.isEmpty ? null : 'v$version',
      applicationLegalese: 'Copyright © 2026 Cadman — AGPL-3.0',
      applicationIcon: Padding(
        padding: const EdgeInsets.all(8),
        child: Image.asset(
          'assets/images/logo.png',
          width: 48,
          height: 48,
        ),
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        final colors = context.read<ThemeController>().colors;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: Text(
              url,
              style: TextStyle(color: colors.text, fontSize: 12),
            ),
            backgroundColor: colors.bgElevated,
            behavior: SnackBarBehavior.floating,
          ));
      }
    } catch (e) {
      debugPrint('[Settings] open link failed: $e');
    }
  }
}
