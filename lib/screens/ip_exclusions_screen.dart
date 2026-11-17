import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/split_tunneling_controller.dart';
import '../controllers/vpn_controller.dart';
import '../theme/i18n.dart';
import '../theme/theme_controller.dart';

class IpExclusionsScreen extends StatefulWidget {
  const IpExclusionsScreen({super.key});

  @override
  State<IpExclusionsScreen> createState() => _IpExclusionsScreenState();
}

class _IpExclusionsScreenState extends State<IpExclusionsScreen> {
  final TextEditingController _textController = TextEditingController();
  bool _invalid = false;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  bool _isValid(String raw) {
    final value = raw.trim();
    if (value.isEmpty || value.contains(RegExp(r'\s'))) return false;

    // IPv4, optionally with a /prefix.
    final ipv4 =
        RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})(/(\d{1,2}))?$');
    final match = ipv4.firstMatch(value);
    if (match != null) {
      for (var i = 1; i <= 4; i++) {
        final octet = int.tryParse(match.group(i)!);
        if (octet == null || octet > 255) return false;
      }
      final prefix = match.group(6);
      if (prefix != null && (int.tryParse(prefix) ?? 33) > 32) return false;
      return true;
    }

    // IPv6 (Xray supports IP rules for it as well).
    if (value.contains(':') &&
        RegExp(r'^[0-9a-fA-F:]+$').hasMatch(value)) {
      return true;
    }

    // Hostname / domain, optionally with a leading wildcard.
    return RegExp(r'^(\*\.)?([a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}$')
        .hasMatch(value);
  }

  void _add() {
    final value = _textController.text;
    if (!_isValid(value)) {
      setState(() => _invalid = true);
      return;
    }
    final controller = context.read<SplitTunnelingController>();
    controller.addIpExclusion(value);
    context.read<VpnController>().markSettingsChanged();
    _textController.clear();
    setState(() => _invalid = false);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SplitTunnelingController>();
    final i18n = context.watch<I18n>();
    final colors = context.watch<ThemeController>().colors;

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          i18n.t('ipExclusionsTitle'),
          style: TextStyle(color: colors.text, fontWeight: FontWeight.bold),
        ),
        leading: BackButton(color: colors.text),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              i18n.t('ipExclusionsDesc'),
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // ورودی اضافه کردن IP یا Domain
            TextField(
              controller: _textController,
              style: TextStyle(color: colors.text),
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(),
              onChanged: (_) {
                if (_invalid) setState(() => _invalid = false);
              },
              decoration: InputDecoration(
                hintText: i18n.t('ipHint'),
                hintStyle: TextStyle(color: colors.textMuted),
                errorText: _invalid ? i18n.t('invalidIp') : null,
                filled: true,
                fillColor: colors.bgElevated,
                suffixIcon: IconButton(
                  icon: Icon(Icons.add, color: colors.accent),
                  onPressed: _add,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colors.border),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // دکمه‌ی حذف همه
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: controller.excludedIpsDomains.isEmpty
                    ? null
                    : () {
                        controller.clearAllIpExclusions();
                        context.read<VpnController>().markSettingsChanged();
                      },
                icon: Icon(Icons.delete_outline, color: colors.danger),
                label: Text(
                  i18n.t('deleteAll'),
                  style: TextStyle(color: colors.danger),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.bgElevated,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  elevation: 0,
                ),
              ),
            ),
            const SizedBox(height: 24),

            // نمایش لیست یا وضعیت خالی
            Expanded(
              child: controller.excludedIpsDomains.isEmpty
                  ? Center(
                      child: Text(
                        i18n.t('noExcludedIps'),
                        style: TextStyle(color: colors.textMuted),
                      ),
                    )
                  : ListView.builder(
                      itemCount: controller.excludedIpsDomains.length,
                      itemBuilder: (context, index) {
                        final item = controller.excludedIpsDomains[index];
                        return ListTile(
                          title: Text(
                            item,
                            style: TextStyle(color: colors.text),
                          ),
                          trailing: IconButton(
                            icon: Icon(Icons.close, color: colors.textMuted),
                            onPressed: () {
                              controller.removeIpExclusion(item);
                              context
                                  .read<VpnController>()
                                  .markSettingsChanged();
                            },
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
