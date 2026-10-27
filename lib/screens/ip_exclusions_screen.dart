import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/split_tunneling_controller.dart';
import '../theme/app_theme.dart';
import '../theme/i18n.dart';

class IpExclusionsScreen extends StatefulWidget {
  const IpExclusionsScreen({super.key});

  @override
  State<IpExclusionsScreen> createState() => _IpExclusionsScreenState();
}

class _IpExclusionsScreenState extends State<IpExclusionsScreen> {
  final TextEditingController _textController = TextEditingController();

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SplitTunnelingController>();
    final i18n = context.watch<I18n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? AppColors.dark : AppColors.light;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          i18n.t('ipExclusionsTitle'),
          style: TextStyle(color: c.text, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: c.text),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              i18n.t('ipExclusionsDesc'),
              style: TextStyle(color: c.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 16),

            // ورودی اضافه کردن IP یا Domain
            TextField(
              controller: _textController,
              style: TextStyle(color: c.text),
              decoration: InputDecoration(
                hintText: i18n.t('ipHint'),
                hintStyle: TextStyle(color: c.textMuted),
                filled: true,
                fillColor: c.bgElevated,
                suffixIcon: IconButton(
                  icon: Icon(Icons.add, color: c.accent),
                  onPressed: () {
                    controller.addIpExclusion(_textController.text);
                    _textController.clear();
                  },
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.border),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // دکمه‌ی حذف همه
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: controller.excludedIpsDomains.isEmpty ? null : controller.clearAllIpExclusions,
                icon: Icon(Icons.delete_outline, color: c.danger),
                label: Text(i18n.t('deleteAll'), style: TextStyle(color: c.danger)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: c.bgElevated,
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
                      child: Text(i18n.t('noExcludedIps'), style: TextStyle(color: c.textMuted)),
                    )
                  : ListView.builder(
                      itemCount: controller.excludedIpsDomains.length,
                      itemBuilder: (context, index) {
                        final item = controller.excludedIpsDomains[index];
                        return ListTile(
                          title: Text(item, style: TextStyle(color: c.text)),
                          trailing: IconButton(
                            icon: Icon(Icons.close, color: c.textMuted),
                            onPressed: () => controller.removeIpExclusion(item),
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