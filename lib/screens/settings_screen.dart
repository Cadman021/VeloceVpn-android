import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/theme_controller.dart';
import '../theme/app_theme.dart';
import '../theme/i18n.dart';
import '../controllers/vpn_controller.dart';
import '../controllers/split_tunneling_controller.dart';
import 'split_tunneling_screen.dart';

const String kAppVersion = '0.1.0';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

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
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // مسدودساز تبلیغات (AdBlock)
            _row(
              colors,
              label: t.t('adblock'),
              subtitle: t.t('adblockDesc'),
              trailing: Switch(
                value: vpn.adblockOn,
                activeThumbColor: colors.accent,
                onChanged: (v) => vpn.setAdblock(v),
              ),
            ),
            const SizedBox(height: 12),

            // تونل‌بندی اختصاصی (Split Tunneling) - هدایت به صفحه تنظیمات پیشرفته
            Consumer<SplitTunnelingController>(
              builder: (context, splitController, child) {
                final statusText = splitController.isEnabled
                    ? '${splitController.mode.toUpperCase()} (${splitController.selectedPackages.length} apps)'
                    : 'Disabled';

                return _linkRow(
                  colors,
                  label: t.t('splitTunneling'),
                  subtitle: statusText,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SplitTunnelingScreen()),
                    );
                  },
                );
              },
            ),
            const SizedBox(height: 16),

            // انتخاب زبان با منوی دراپ‌داون
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

            // انتخاب پوسته (تیره / روشن)
            _dropdownRow(
              colors,
              label: t.t('theme'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _themePill(colors, t.t('dark'), themeController.isDark, () => themeController.setDark(true)),
                  const SizedBox(width: 6),
                  _themePill(colors, t.t('light'), !themeController.isDark, () => themeController.setDark(false)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            _linkRow(colors, label: t.t('privacyPolicy'), onTap: () => _openLink('https://example.com/privacy')),
            _linkRow(colors, label: t.t('termsOfService'), onTap: () => _openLink('https://example.com/terms')),

            const Spacer(),

            Center(
              child: Column(
                children: [
                  Text('v$kAppVersion', style: TextStyle(color: colors.textMuted, fontSize: 11)),
                  Text(t.t('poweredBy'), style: TextStyle(color: colors.textMuted, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(AppColors colors, {required String label, required String subtitle, required Widget trailing}) {
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
                Text(label, style: TextStyle(color: colors.text, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _dropdownRow(AppColors colors, {required String label, required Widget trailing}) {
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
          Text(label, style: TextStyle(color: colors.text, fontSize: 13, fontWeight: FontWeight.w600)),
          trailing,
        ],
      ),
    );
  }

  Widget _linkRow(AppColors colors, {required String label, String? subtitle, required VoidCallback onTap}) {
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(color: colors.text, fontSize: 13, fontWeight: FontWeight.w600)),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: colors.textSecondary, fontSize: 11)),
                  ],
                ],
              ),
              Icon(Icons.chevron_right, color: colors.textSecondary, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _themePill(AppColors colors, String label, bool active, VoidCallback onTap) {
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
        child: Text(label, style: TextStyle(fontSize: 11, color: active ? Colors.white : colors.textSecondary)),
      ),
    );
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}