import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../controllers/split_tunneling_controller.dart';
import '../controllers/vpn_controller.dart';
import '../theme/app_theme.dart';
import '../theme/i18n.dart';
import '../theme/theme_controller.dart';
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
