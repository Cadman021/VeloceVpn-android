import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/split_tunneling_controller.dart';
import '../controllers/vpn_controller.dart';
import '../services/models.dart';
import '../theme/app_theme.dart';
import '../theme/i18n.dart';
import '../theme/theme_controller.dart';
import '../widgets/country_flag.dart';

enum LocationTab { locations, favorite, recent }

class LocationsScreen extends StatefulWidget {
  const LocationsScreen({super.key});

  @override
  State<LocationsScreen> createState() => _LocationsScreenState();
}

class _LocationsScreenState extends State<LocationsScreen> {
  LocationTab _activeTab = LocationTab.locations;
  String _search = '';
  String? _openCountry;
  final Set<String> _testingIds = {};
  bool _isTestingBatch = false;

  late VpnController vpn;

  @override
  void initState() {
    super.initState();
    vpn = context.read<VpnController>();
    if (!vpn.isLocationsLoaded) {
      vpn.preloadLocations().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  Future<void> _retryLoad() async {
    await vpn.preloadLocations(force: true);
    if (mounted) setState(() {});
  }

  Future<void> _testAllPings() async {
    if (_isTestingBatch) return;
    setState(() => _isTestingBatch = true);

    final allLocs = vpn.cachedLocations.expand((c) => c.locations).toList();
    setState(() {
      _testingIds.addAll(allLocs.map((l) => l.id));
    });

    await vpn.pingLocationsInParallel(
      allLocs,
      concurrency: 4,
      onProgress: (loc) {
        if (mounted) {
          setState(() {
            _testingIds.remove(loc.id);
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _testingIds.clear();
        _isTestingBatch = false;
      });
    }
  }

  Future<void> _testSinglePing(CityLocation loc) async {
    if (_testingIds.contains(loc.id)) return;
    setState(() => _testingIds.add(loc.id));
    final ms = await vpn.pingLocation(loc.id);
    if (mounted) {
      setState(() {
        loc.ping = ms;
        loc.unreachable = (ms == null);
        _testingIds.remove(loc.id);
      });
    }
  }

  Future<void> _select(CityLocation loc) async {
    final meta = SelectedLocationMeta(
      id: loc.id,
      country: loc.country,
      city: loc.city,
      countryCode: loc.countryCode,
    );

    final wasActive = vpn.status == ConnStatus.connected ||
        vpn.status == ConnStatus.connecting ||
        vpn.status == ConnStatus.switching;

    if (!wasActive) {
      await vpn.selectLocation(meta);
      if (mounted) Navigator.of(context).pop(true);
      return;
    }

    // The selected server and the server actually carrying the tunnel must
    // not diverge. Switch immediately and keep this screen open if it fails.
    final split = context.read<SplitTunnelingController>();
    final ok = await vpn.switchLocation(meta, split);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(true);
    } else {
      _showVpnError();
    }
  }

  void _showVpnError() {
    if (!mounted || vpn.lastErrorKind == null) return;
    final t = context.read<I18n>();
    final colors = context.read<ThemeController>().colors;
    final message = switch (vpn.lastErrorKind!) {
      VpnErrorKind.configFailed => t.t('errConfigFailed'),
      VpnErrorKind.permissionDenied => t.t('errPermissionDenied'),
      VpnErrorKind.startFailed => t.t('errStartFailed'),
      VpnErrorKind.emptyInclusiveSelection => t.t('errEmptyInclusive'),
      VpnErrorKind.unknown => t.t('errUnknown'),
    };
    vpn.clearError();
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message, style: TextStyle(color: colors.text)),
        backgroundColor: colors.bgElevated,
        behavior: SnackBarBehavior.floating,
      ));
  }

  void _selectOptimal() {
    final best = vpn.getOptimalLocation();
    if (best != null) {
      _select(best);
      return;
    }
    final t = context.read<I18n>();
    final colors = context.read<ThemeController>().colors;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          t.t('pingFirst'),
          style: TextStyle(color: colors.text),
        ),
        backgroundColor: colors.bgElevated,
        behavior: SnackBarBehavior.floating,
      ));
  }

  Color _getPingColor(int ping, AppColors colors) {
    if (ping < 700) return colors.success;
    if (ping < 1000) return colors.warning;
    return colors.danger;
  }

  List<CountryGroup> get _filteredGroups {
    final groups = vpn.cachedLocations;
    if (_search.isEmpty) return groups;
    final q = _search.toLowerCase();
    return groups
        .map((c) {
          final nameMatch = c.countryName.toLowerCase().contains(q);
          final locs = c.locations
              .where((l) =>
                  nameMatch || l.city.toLowerCase().contains(q))
              .toList();
          if (locs.isEmpty) return null;
          return CountryGroup(
            countryName: c.countryName,
            countryCode: c.countryCode,
            locations: locs,
          );
        })
        .whereType<CountryGroup>()
        .toList();
  }

  List<CityLocation> get _favoriteLocations {
    final all = vpn.cachedLocations.expand((c) => c.locations).toList();
    return all.where((l) => vpn.favoriteIds.contains(l.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    // Rebuild when the background preload (started from the splash screen)
    // completes, and when another screen changes the connected server.
    vpn = context.watch<VpnController>();
    final colors = context.watch<ThemeController>().colors;
    final t = context.watch<I18n>();

    return Scaffold(
      backgroundColor: colors.bg,
      appBar: AppBar(
        backgroundColor: colors.bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, size: 24),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.language, size: 20),
            const SizedBox(width: 8),
            Text(
              t.t('location'),
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: t.t('pingAll'),
            icon: _isTestingBatch
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(Icons.bolt, color: colors.accent3),
            onPressed: vpn.cachedLocations.isEmpty ? null : _testAllPings,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            // ── تب‌های سه‌گانه (Locations / Favorite / Recent) ───────────
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: colors.bgElevated,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  _buildTabPill(
                      LocationTab.locations, t.t('locations'), colors),
                  _buildTabPill(LocationTab.favorite, t.t('favorite'), colors),
                  _buildTabPill(LocationTab.recent, t.t('recent'), colors),
                ],
              ),
            ),

            if (vpn.usingCachedLocations)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.bgElevated2,
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: colors.warning.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.cloud_off, size: 16, color: colors.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        t.t('staleData'),
                        style:
                            TextStyle(color: colors.textSecondary, fontSize: 11),
                      ),
                    ),
                    TextButton(
                      onPressed: _retryLoad,
                      child: Text(t.t('retry')),
                    ),
                  ],
                ),
              ),

            // ── فیلد جستجو ─────────────────────────────────────────────
            if (_activeTab == LocationTab.locations)
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 10),
                child: TextField(
                  style: TextStyle(color: colors.text, fontSize: 14),
                  decoration: InputDecoration(
                    hintText: t.t('searchPlaceholder'),
                    hintStyle: TextStyle(color: colors.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: colors.bgElevated,
                    prefixIcon: Icon(Icons.search,
                        color: colors.textSecondary, size: 20),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _search = v),
                ),
              ),

            // ── محتوای اصلی تب‌ها ───────────────────────────────────────
            Expanded(
              child: vpn.loadFailed
                  ? _buildLoadError(colors, t)
                  : (vpn.isLoadingLocations && vpn.cachedLocations.isEmpty)
                      ? Center(
                          child: CircularProgressIndicator(color: colors.accent),
                        )
                      : _buildTabContent(colors, t),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadError(AppColors colors, I18n t) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.t('loadError'),
            textAlign: TextAlign.center,
            style: TextStyle(color: colors.danger),
          ),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: _retryLoad,
            icon: const Icon(Icons.refresh),
            label: Text(t.t('retry')),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill(LocationTab tab, String title, AppColors colors) {
    final active = _activeTab == tab;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = tab),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: active ? colors.bgElevated2 : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
              color: active ? colors.text : colors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(AppColors colors, I18n t) {
    switch (_activeTab) {
      case LocationTab.locations:
        return ListView(
          children: [
            _buildOptimalCard(colors, t),
            const SizedBox(height: 10),
            ..._filteredGroups
                .map((country) => _buildCountryAccordion(country, colors, t)),
          ],
        );
      case LocationTab.favorite:
        final favs = _favoriteLocations;
        if (favs.isEmpty) {
          return Center(
            child: Text(
              t.t('noFavorites'),
              style: TextStyle(color: colors.textSecondary),
            ),
          );
        }
        return ListView.builder(
          itemCount: favs.length,
          itemBuilder: (_, i) => _buildLocationTile(favs[i], colors, t),
        );
      case LocationTab.recent:
        if (vpn.recentLocations.isEmpty) {
          return Center(
            child: Text(
              t.t('noRecents'),
              style: TextStyle(color: colors.textSecondary),
            ),
          );
        }
        return ListView.builder(
          itemCount: vpn.recentLocations.length,
          itemBuilder: (_, i) {
            final rec = vpn.recentLocations[i];
            final matched = vpn.cachedLocations
                .expand((c) => c.locations)
                .firstWhere(
                  (l) => l.id == rec.id,
                  orElse: () => CityLocation(
                    id: rec.id,
                    city: rec.city,
                    country: rec.country,
                    countryCode: rec.countryCode,
                  ),
                );
            return _buildLocationTile(matched, colors, t);
          },
        );
    }
  }

  // ── کارت بهترین لوکیشن (Optimal) ─────────────────────────────────────────
  Widget _buildOptimalCard(AppColors colors, I18n t) {
    final best = vpn.getOptimalLocation();
    final isSelected =
        vpn.selectedMeta != null && best != null && vpn.selectedMeta!.id == best.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected ? colors.accent : colors.border,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: ListTile(
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.flash_on, color: colors.accent, size: 20),
          ),
          title: Row(
            children: [
              Text(
                t.t('optimalLocation'),
                style: TextStyle(
                  color: colors.text,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
              if (vpn.connectedMeta != null &&
                  vpn.status == ConnStatus.connected &&
                  vpn.connectedMeta!.id == best?.id) ...[
                const SizedBox(width: 8),
                _buildActiveBadge(colors, t),
              ],
            ],
          ),
          subtitle: Text(
            best != null
                ? '${best.country} - ${best.city} (${best.ping} ms)'
                : t.t('fastestServer'),
            style: TextStyle(color: colors.textSecondary, fontSize: 11),
          ),
          onTap: _selectOptimal,
        ),
      ),
    );
  }

  // ── آکاردئون هر کشور ────────────────────────────────────────────────────
  Widget _buildCountryAccordion(
    CountryGroup country,
    AppColors colors,
    I18n t,
  ) {
    final isOpen = _openCountry == country.countryCode;
    final hasActiveServer = vpn.status == ConnStatus.connected &&
        vpn.connectedMeta != null &&
        country.locations.any((l) => vpn.connectedMeta!.id == l.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.bgElevated,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasActiveServer
              ? colors.accent.withValues(alpha: 0.5)
              : colors.border,
        ),
      ),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(14),
            child: ListTile(
              leading: CountryFlag(countryCode: country.countryCode),
              title: Row(
                children: [
                  Text(
                    country.countryName,
                    style: TextStyle(
                      color: colors.text,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  if (hasActiveServer && !isOpen) ...[
                    const SizedBox(width: 8),
                    _buildActiveBadge(colors, t),
                  ],
                ],
              ),
              subtitle: Text(
                '${country.locations.length} ${t.t('serversCount')}',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
              trailing: Icon(
                isOpen ? Icons.expand_less : Icons.expand_more,
                color: colors.textSecondary,
              ),
              onTap: () => setState(
                () => _openCountry = isOpen ? null : country.countryCode,
              ),
            ),
          ),
          if (isOpen)
            ...country.locations.map(
              (loc) => _buildLocationTile(loc, colors, t, inAccordion: true),
            ),
        ],
      ),
    );
  }

  // ── سطر هر شهر و سرور ────────────────────────────────────────────────────
  Widget _buildLocationTile(
    CityLocation loc,
    AppColors colors,
    I18n t, {
    bool inAccordion = false,
  }) {
    final isSelected = vpn.selectedMeta?.id == loc.id;
    final isActive =
        vpn.status == ConnStatus.connected && vpn.connectedMeta?.id == loc.id;
    final isFav = vpn.favoriteIds.contains(loc.id);
    final isTesting = _testingIds.contains(loc.id);

    return Material(
      color: Colors.transparent,
      child: ListTile(
        contentPadding:
            EdgeInsets.only(left: inAccordion ? 28 : 16, right: 14),
        leading: CountryFlag(
          countryCode: loc.countryCode,
          width: 22,
          height: 16,
        ),
        title: Row(
          children: [
            Text(
              loc.city,
              style: TextStyle(
                color: isSelected ? colors.accent : colors.text,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 8),
              _buildActiveBadge(colors, t),
            ],
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isTesting)
              const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else if (loc.unreachable)
              Text(
                t.t('timeout'),
                style: TextStyle(
                  color: colors.danger,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              )
            else if (loc.ping != null)
              Row(
                children: [
                  Icon(
                    Icons.wifi,
                    size: 14,
                    color: _getPingColor(loc.ping!, colors),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${loc.ping} ms',
                    style: TextStyle(
                      color: _getPingColor(loc.ping!, colors),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            else
              IconButton(
                icon: Icon(Icons.speed, size: 17, color: colors.textSecondary),
                onPressed: () => _testSinglePing(loc),
              ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                isFav ? Icons.star : Icons.star_border,
                color: isFav ? Colors.amber : colors.textSecondary,
                size: 20,
              ),
              onPressed: () async {
                await vpn.toggleFavorite(loc.id);
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
        onTap: () => _select(loc),
      ),
    );
  }

  Widget _buildActiveBadge(AppColors colors, I18n t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.accent.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.accent.withValues(alpha: 0.4)),
      ),
      child: Text(
        t.t('active'),
        style: TextStyle(
          color: colors.accent,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
