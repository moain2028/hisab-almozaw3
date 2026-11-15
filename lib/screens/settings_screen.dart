import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/license_service.dart';
import '../core/update_service.dart';
import '../data/store.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'backups_screen.dart';
import 'products_screen.dart';
import 'trader_screen.dart';
import 'developer_screen.dart';
import 'update_screen.dart';

/// مركز الإعدادات — يُفتح من زر ⚙ في رأس كل شاشة رئيسية، ومن آخر القائمة الجانبية.
/// الأقسام مرتّبة من الأكثر استخداماً للأقل: الحساب ← المظهر ← الحماية ← التحديث والترخيص ← متقدم.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final cs = Theme.of(context).colorScheme;
    final last = store.lastBackup;
    final oldBackup = last == 0 || DateTime.now().millisecondsSinceEpoch - last > 3 * 86400000;

    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          const SectionTitle('الحساب والبيانات'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: const Text('الأصناف والأسعار', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text('${store.products.length} صنف'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.local_shipping_outlined),
                  title: const Text('التاجر', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(store.mainTrader.name),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => TraderScreen(trader: store.mainTrader)),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.badge_outlined),
                  title: const Text('اسمك (يظهر في الكشوفات)', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(store.distributorName.isEmpty ? 'غير محدد' : store.distributorName),
                  onTap: () async {
                    final v = await askText(context, 'اسم الموزع', initial: store.distributorName);
                    if (v != null) await store.setMeta('distributorName', v);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.currency_exchange),
                  title: const Text('العملة', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(store.currency),
                  onTap: () async {
                    final v = await askText(context, 'اسم العملة', initial: store.currency, hint: 'ريال');
                    if (v != null && v.isNotEmpty) await store.setMeta('currency', v);
                  },
                ),
              ],
            ),
          ),
          const SectionTitle('المظهر'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 0, label: Text('تلقائي'), icon: Icon(Icons.brightness_auto)),
                      ButtonSegment(value: 1, label: Text('فاتح'), icon: Icon(Icons.light_mode)),
                      ButtonSegment(value: 2, label: Text('داكن'), icon: Icon(Icons.dark_mode)),
                    ],
                    selected: {store.themeMode},
                    onSelectionChanged: (v) => store.setMeta('themeMode', v.first),
                  ),
                  const SizedBox(height: 12),
                  const Text('حجم الخط', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SegmentedButton<double>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 1.0, label: Text('عادي')),
                      ButtonSegment(value: 1.12, label: Text('كبير')),
                      ButtonSegment(value: 1.25, label: Text('كبير جداً')),
                    ],
                    selected: {store.textScale},
                    onSelectionChanged: (v) => store.setMeta('textScale', v.first),
                  ),
                  const SizedBox(height: 6),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: store.haptics,
                    onChanged: (v) => store.setMeta('haptics', v),
                    title: const Text('اهتزاز خفيف عند الضغط', style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ),
          const SectionTitle('الحماية والنسخ الاحتياطي'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(
                    oldBackup ? Icons.warning_amber : Icons.cloud_done_outlined,
                    color: oldBackup ? AppColors.warn : paidColor(context),
                  ),
                  title: const Text('النسخ الاحتياطي على الجوال', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                    last == 0
                        ? 'لم تُحفظ نسخة بعد'
                        : 'آخر نسخة: ${relativeDay(dayKey(DateTime.fromMillisecondsSinceEpoch(last)))} · ${store.autoBackup ? 'تلقائي مفعّل' : 'تلقائي متوقف'}',
                    style: TextStyle(color: oldBackup ? AppColors.warn : null),
                  ),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupsScreen())),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.copy_all),
                  title: const Text('نسخ البيانات كنص', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('ينسخ كل الحسابات كنص، الصقه في واتساب أو ملاحظات'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: store.exportJson()));
                    await store.markBackup();
                    if (context.mounted) toast(context, 'تم النسخ. الصقه الآن في محادثتك مع نفسك في واتساب');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('استرجاع من نص', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('الصق النص المحفوظ لاسترجاع الحسابات'),
                  onTap: () => _restore(context, store),
                ),
              ],
            ),
          ),
          const SectionTitle('التحديث والترخيص'),
          const _RemoteCard(),
          const SectionTitle('متقدم'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: const Text('تحميل بيانات تجريبية', style: TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: const Text('أسبوع كامل لتجربة البرنامج (يمسح البيانات الحالية)'),
                  onTap: () async {
                    if (!await confirm(
                      context,
                      'سيتم مسح كل البيانات الحالية وتحميل بيانات تجريبية. متأكد؟',
                      ok: 'تحميل',
                    )) {
                      return;
                    }
                    await store.loadDemo();
                    if (context.mounted) toast(context, 'تم تحميل البيانات التجريبية');
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.delete_forever_outlined, color: debtColor(context)),
                  title: Text(
                    'مسح كل البيانات',
                    style: TextStyle(fontWeight: FontWeight.w700, color: debtColor(context)),
                  ),
                  onTap: () async {
                    if (!await confirm(context, 'مسح كل البقالات والحسابات نهائياً؟')) return;
                    if (!context.mounted) return;
                    if (!await confirm(context, 'تأكيد أخير: لا يمكن التراجع!', ok: 'مسح الكل')) return;
                    await store.wipeAll();
                  },
                ),
              ],
            ),
          ),
          const SectionTitle('حول'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.support_agent_rounded),
              title: const Text('تواصل مع المطوّر', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: const Text('واتساب · اتصال · الموقع'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DeveloperScreen())),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'حساب الموزع · الإصدار $kAppVersion · ${store.recordCount} سجل',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _restore(BuildContext context, Store store) async {
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    if (!context.mounted) return;
    final ctl = TextEditingController(text: (clip?.text ?? '').contains('hisab_almozaw3') ? clip!.text : '');
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استرجاع البيانات'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ctl,
              maxLines: 5,
              style: const TextStyle(fontSize: 11),
              textDirection: TextDirection.ltr,
              decoration: const InputDecoration(hintText: 'الصق نص النسخة الاحتياطية هنا'),
            ),
            const SizedBox(height: 8),
            const Text(
              'دمج: يضيف ويحدّث بدون مسح.\nاستبدال: يمسح الحالي ويرجع النسخة.',
              style: TextStyle(fontSize: 12.5),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('استبدال')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'merge'), child: const Text('دمج')),
        ],
      ),
    );
    if (mode == null || !context.mounted) return;
    try {
      final n = await store.importJson(ctl.text, replace: mode == 'replace');
      if (context.mounted) toast(context, 'تم استرجاع $n سجل');
    } catch (e) {
      if (context.mounted) toast(context, 'النص غير صالح. تأكد أنك لصقت النسخة كاملة.');
    }
  }
}

/// بطاقة التحديث عن بعد + حالة الترخيص
class _RemoteCard extends StatelessWidget {
  const _RemoteCard();

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseService>();
    final upd = context.watch<UpdateService>();
    final st = lic.state;
    final checked = lic.lastCheck;
    return Card(
      child: Column(
        children: [
          if (UpdateService.supported) ...[
            ListTile(
              leading: Badge(
                isLabelVisible: upd.last?.available == true,
                smallSize: 9,
                child: const Icon(Icons.system_update_rounded),
              ),
              title: const Text('تحديث التطبيق', style: TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                upd.last?.available == true
                    ? 'الإصدار ${upd.last!.info!.version} متاح للتنزيل'
                    : 'الإصدار الحالي $kAppVersion · يُفحص تلقائياً كل 24 ساعة',
              ),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const UpdateScreen())),
            ),
            const Divider(height: 1),
          ],
          ListTile(
            leading: Icon(
              st.allowed ? Icons.verified_user_rounded : Icons.gpp_bad_rounded,
              color: st.allowed ? paidColor(context) : debtColor(context),
            ),
            title: const Text('الترخيص', style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
              '${st.allowed ? 'مفعّل' : 'موقوف'}'
              '${st.offline ? ' · بدون اتصال (آخر حالة معروفة)' : ''}'
              '${checked == null ? '' : ' · آخر فحص ${relativeDay(dayKey(checked))} ${timeOf(checked.millisecondsSinceEpoch)}'}',
            ),
            trailing: IconButton(
              tooltip: 'فحص الآن',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () async {
                final r = await lic.refresh();
                if (context.mounted) toast(context, r.offline ? 'لا يوجد اتصال، بقيت آخر حالة معروفة' : 'تم الفحص');
              },
            ),
          ),
        ],
      ),
    );
  }
}
