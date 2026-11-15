/// app_drawer.dart — القائمة الجانبية.
///
/// المبدأ (مثل منظومة الضيافة): **كل وجهة في مكان واحد فقط**.
///   - الشريط السفلي = عمل اليوم المتكرر (اليوم، البقالات، التاجر، التقارير).
///   - القائمة الجانبية = البيانات الأساسية والأدوات والإعدادات (أقل تكراراً).
///   - الإعدادات دائماً في النهاية + زر ⚙ في رأس كل شاشة رئيسية.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/update_service.dart';
import '../data/store.dart';
import '../screens/backups_screen.dart';
import '../screens/expenses_screen.dart';
import '../screens/products_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/shop_form.dart';
import '../screens/update_screen.dart';
import 'theme.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.onNavigate, required this.current});

  /// للتنقل إلى تبويب في الشريط السفلي
  final ValueChanged<int> onNavigate;
  final int current;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final upd = context.watch<UpdateService>();
    final cs = Theme.of(context).colorScheme;

    void open(Widget page) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }

    void tab(int i) {
      Navigator.pop(context);
      onNavigate(i);
    }

    final last = store.lastBackup;
    final backupSub = last == 0
        ? 'لم تُحفظ نسخة بعد'
        : 'آخر نسخة: ${relativeDay(dayKey(DateTime.fromMillisecondsSinceEpoch(last)))}';

    return NavigationDrawer(
      backgroundColor: cs.surface,
      selectedIndex: null,
      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
      children: [
        // ---------------- الترويسة
        Container(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [cs.primary, Color.lerp(cs.primary, Colors.black, .3)!],
              begin: AlignmentDirectional.topStart,
              end: AlignmentDirectional.bottomEnd,
            ),
            borderRadius: BorderRadius.circular(Radii.lg),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.onPrimary.withValues(alpha: .15),
                  borderRadius: BorderRadius.circular(Radii.md),
                ),
                child: Icon(Icons.local_shipping_rounded, color: cs.onPrimary, size: 26),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      store.distributorName.isEmpty ? 'حساب الموزع' : store.distributorName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700, fontSize: 17),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${store.shops.length} بقالة · ${store.products.length} صنف',
                      style: TextStyle(color: cs.onPrimary.withValues(alpha: .8), fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        const _Header('العمل اليومي'),
        _Item(Icons.today_rounded, 'اليوم', selected: current == 0, onTap: () => tab(0)),
        _Item(Icons.storefront_rounded, 'البقالات', selected: current == 1, onTap: () => tab(1)),
        _Item(Icons.local_shipping_rounded, 'التاجر', selected: current == 2, onTap: () => tab(2)),
        _Item(Icons.insights_rounded, 'التقارير', selected: current == 3, onTap: () => tab(3)),

        const _Header('البيانات'),
        _Item(
          Icons.inventory_2_rounded,
          'الأصناف والأسعار',
          sub: '${store.products.length} صنف',
          onTap: () => open(const ProductsScreen()),
        ),
        _Item(Icons.add_business_rounded, 'إضافة بقالة', onTap: () => open(const ShopFormScreen())),
        _Item(Icons.receipt_long_rounded, 'المصاريف', onTap: () => open(const ExpensesScreen())),

        const _Header('الحماية'),
        _Item(
          Icons.cloud_done_rounded,
          'النسخ الاحتياطي',
          sub: backupSub,
          warn: store.lastBackup == 0,
          onTap: () => open(const BackupsScreen()),
        ),
        if (UpdateService.supported)
          _Item(
            Icons.system_update_rounded,
            'تحديث التطبيق',
            sub: upd.last?.available == true ? 'الإصدار ${upd.last!.info!.version} متاح' : 'فحص التحديثات',
            badge: upd.last?.available == true,
            onTap: () => open(const UpdateScreen()),
          ),

        const Padding(padding: EdgeInsets.fromLTRB(28, 8, 28, 8), child: Divider()),
        _Item(Icons.settings_rounded, 'الإعدادات', onTap: () => open(const SettingsScreen())),
        const SizedBox(height: 12),
        Center(
          child: Text('الإصدار $kAppVersion', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(28, 16, 16, 6),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.primary,
        letterSpacing: .2,
      ),
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item(
    this.icon,
    this.title, {
    this.sub,
    this.onTap,
    this.selected = false,
    this.badge = false,
    this.warn = false,
  });
  final IconData icon;
  final String title;
  final String? sub;
  final VoidCallback? onTap;
  final bool selected;
  final bool badge;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
      child: Material(
        color: selected ? cs.secondaryContainer : Colors.transparent,
        borderRadius: BorderRadius.circular(Radii.pill),
        child: InkWell(
          borderRadius: BorderRadius.circular(Radii.pill),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 52),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  Badge(
                    isLabelVisible: badge,
                    smallSize: 9,
                    child: Icon(icon, color: fg, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: fg),
                        ),
                        if (sub != null)
                          Text(
                            sub!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12, color: warn ? AppColors.warn : cs.onSurfaceVariant),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
