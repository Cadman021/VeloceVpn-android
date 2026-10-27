import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../controllers/split_tunneling_controller.dart';
import '../theme/app_theme.dart';
import '../theme/i18n.dart';
import 'ip_exclusions_screen.dart';

class SplitTunnelingScreen extends StatefulWidget {
  const SplitTunnelingScreen({super.key});

  @override
  State<SplitTunnelingScreen> createState() => _SplitTunnelingScreenState();
}

class _SplitTunnelingScreenState extends State<SplitTunnelingScreen> {
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final controller = context.read<SplitTunnelingController>();
      controller.loadSettings().then((_) => controller.fetchApps());
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SplitTunnelingController>();
    final i18n = context.watch<I18n>();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = isDark ? AppColors.dark : AppColors.light;

    final filteredApps = controller.allApps.where((app) {
      return app.name.toLowerCase().contains(searchQuery.toLowerCase()) ||
          app.packageName.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          i18n.t('splitTunneling'),
          style: TextStyle(color: c.text, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios, color: c.text),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ۱. کارت فعال/غیرفعال‌سازی
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.bgElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.call_split, color: c.accent),
                          const SizedBox(width: 8),
                          Text(
                            i18n.t('splitTunneling'),
                            style: TextStyle(color: c.text, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Switch(
                        value: controller.isEnabled,
                        onChanged: controller.toggleEnabled,
                        activeThumbColor: c.accent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    i18n.t('splitTunnelingDesc'),
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ۲. تنظیمات Mode (Exclusive / Inclusive)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: c.bgElevated,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: c.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(i18n.t('mode'), style: TextStyle(color: c.text, fontSize: 15)),
                  DropdownButton<String>(
                    value: controller.mode,
                    dropdownColor: c.bgElevated2,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                        value: 'exclusive',
                        child: Text(i18n.t('exclusive'), style: TextStyle(color: c.text)),
                      ),
                      DropdownMenuItem(
                        value: 'inclusive',
                        child: Text(i18n.t('inclusive'), style: TextStyle(color: c.text)),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) controller.setMode(val);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ۳. دکمه هدایت به IP Exclusions
            InkWell(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const IpExclusionsScreen())),
              borderRadius: BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: c.bgElevated,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.border),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(i18n.t('ipExclusionsTitle'), style: TextStyle(color: c.text, fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Text('${controller.excludedIpsDomains.length}', style: TextStyle(color: c.textSecondary)),
                        Icon(Icons.chevron_right, color: c.textMuted),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            // ۴. بخش لیست برنامه‌ها
            Text(i18n.t('apps'), style: TextStyle(color: c.textMuted, fontSize: 12, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(i18n.t('showSystemApps'), style: TextStyle(color: c.text)),
                Checkbox(
                  value: controller.showSystemApps,
                  onChanged: (val) => controller.toggleShowSystemApps(val ?? false),
                  activeColor: c.accent,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // فیلد جستجو
            TextField(
              onChanged: (val) => setState(() => searchQuery = val),
              style: TextStyle(color: c.text),
              decoration: InputDecoration(
                hintText: i18n.t('searchApps'),
                hintStyle: TextStyle(color: c.textMuted),
                prefixIcon: Icon(Icons.search, color: c.textMuted),
                filled: true,
                fillColor: c.bgElevated,
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
            const SizedBox(height: 12),

            // لیست برنامه‌ها
            controller.isLoadingApps
                ? Center(child: CircularProgressIndicator(color: c.accent))
                : ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredApps.length,
                    itemBuilder: (context, index) {
                      final app = filteredApps[index];
                      final isSelected = controller.selectedPackages.contains(app.packageName);

                      return ListTile(
                        leading: app.icon != null
                            ? Image.memory(app.icon!, width: 36, height: 36)
                            : Icon(Icons.android, color: c.accent),
                        title: Text(app.name, style: TextStyle(color: c.text, fontSize: 14)),
                        trailing: Checkbox(
                          value: isSelected,
                          onChanged: (_) => controller.toggleAppSelection(app.packageName),
                          activeColor: c.accent,
                        ),
                      );
                    },
                  ),
          ],
        ),
      ),
    );
  }
}