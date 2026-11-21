/// app_drawer.dart — القائمة الجانبية (منذ 2.7.0).
///
/// المعيار (docs/standards/navigation.md):
///   - **العرض ≈ نصف الشاشة** (50%، بين 200 و300dp) بدل 80% الافتراضية.
///   - **بلا تمرير**: 6 وجهات فقط تتسع في أصغر جوال شائع (360×740) حتى بخط كبير.
///   - **لا تكرار**: اليوم/البقالات/التاجر/التقارير موجودة في الشريط السفلي فلا تُكرَّر هنا،
///     و«إضافة بقالة» موجودة في الرئيسية.
///   - ثلاث مجموعات: البيانات (الأصناف، المصاريف) · الحماية (النسخ، التحديث) · النظام (الإعدادات، المطوّر).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/license_service.dart';
import '../data/store.dart';
import '../screens/backups_screen.dart';
import '../screens/developer_screen.dart';
import '../screens/expenses_screen.dart';
import '../screens/products_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/update_screen.dart';
import 'theme.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.onNavigate, required this.current});

  /// للتنقل إلى تبويب في الشريط السفلي (محفوظ للتوافق)
  final ValueChanged<int> onNavigate;
  final int current;

  /// عرض القائمة: نصف الشاشة بين 200 و300
  static double widthFor(double screen) => (screen * .5).clamp(200.0, 300.0);

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final lic = context.watch<LicenseService>();
    final cs = Theme.of(context).colorScheme;

    void open(Widget page) {
      Navigator.pop(context);
      Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    }

    final last = store.lastBackup;
    final backupSub = last == 0 ? 'لا نسخة بعد' : relativeDay(dayKey(DateTime.fromMillisecondsSinceEpoch(last)));
    final hasUpdate = lic.updateAvailable;

    return Drawer(
      width: widthFor(MediaQuery.sizeOf(context).width),
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadiusDirectional.horizontal(end: Radius.circular(Radii.xl)),
      ),
      child: SafeArea(
        child: CustomScrollView(
          // يتسع بلا تمرير على الجوالات الشائعة؛ التمرير احتياط للشاشات الصغيرة جداً فقط
          physics: const ClampingScrollPhysics(),
          slivers: [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // الترويسة: الاسم فقط (العدّادات في الرئيسية)
                  Container(
                    margin: const EdgeInsets.fromLTRB(Space.sm, Space.sm, Space.sm, Space.xs),
                    padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
                    decoration: BoxDecoration(
                      gradient: heroGradient(cs),
                      borderRadius: BorderRadius.circular(Radii.lg),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.local_shipping_rounded, color: AppColors.goldLight, size: 24),
                        const SizedBox(width: Space.sm),
                        Expanded(
                          child: Text(
                            store.distributorName.isEmpty ? 'حساب الموزع' : store.distributorName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kOnHero, fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _Header('البيانات'),
                  _Item(Icons.inventory_2_rounded, 'الأصناف', onTap: () => open(const ProductsScreen())),
                  _Item(Icons.receipt_long_rounded, 'المصاريف', onTap: () => open(const ExpensesScreen())),
                  const _Header('الحماية'),
                  _Item(
                    Icons.cloud_done_rounded,
                    'النسخ',
                    sub: backupSub,
                    warn: last == 0,
                    onTap: () => open(const BackupsScreen()),
                  ),
                  _Item(
                    Icons.system_update_rounded,
                    'التحديث',
                    sub: hasUpdate ? 'متاح ${lic.release.value!.version}' : null,
                    badge: hasUpdate,
                    onTap: () => open(const UpdateScreen()),
                  ),
                  const _Header('النظام'),
                  _Item(Icons.settings_rounded, 'الإعدادات', onTap: () => open(const SettingsScreen())),
                  _Item(Icons.support_agent_rounded, 'المطوّر', onTap: () => open(const DeveloperScreen())),
                  const Spacer(),
                  Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: Text(
                      'الإصدار $kAppVersion',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(Space.lg + 4, Space.md, Space.md, Space.xs),
    child: Text(
      text,
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.primary),
    ),
  );
}

class _Item extends StatelessWidget {
  const _Item(this.icon, this.title, {this.sub, this.onTap, this.badge = false, this.warn = false});
  final IconData icon;
  final String title;
  final String? sub;
  final VoidCallback? onTap;
  final bool badge;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.pill),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: 4),
            child: Row(
              children: [
                Badge(
                  isLabelVisible: badge,
                  smallSize: 9,
                  child: Icon(icon, color: cs.onSurface, size: 22),
                ),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                      ),
                      if (sub != null)
                        Text(
                          sub!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: warn ? warnColor(context) : cs.onSurfaceVariant),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
