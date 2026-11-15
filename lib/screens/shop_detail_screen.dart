import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../data/ledger.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'collect_sheet.dart';
import 'lines_editor.dart';
import 'shop_form.dart';

/// كشف حساب البقالة: الرصيد + كل الحركات يوماً بيوم مع الرصيد الجاري
class ShopDetailScreen extends StatelessWidget {
  const ShopDetailScreen({super.key, required this.shopId});
  final String shopId;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final shop = store.shop(shopId);
    if (shop == null) return const Scaffold(body: Center(child: Text('البقالة محذوفة')));
    final cs = Theme.of(context).colorScheme;
    final bal = store.balanceOf(shop);
    final rows = shopStatement(shop, store.shopTxs);
    final lastPay = lastPaymentDay(shop.id, store.shopTxs);

    // تجميع حسب اليوم (الأحدث أولاً)
    final byDay = <String, List<StatementRow<ShopTx>>>{};
    for (final r in rows) {
      (byDay[r.tx.day] ??= []).add(r);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: Text(shop.name),
        actions: [
          IconButton(
            tooltip: 'إرسال الكشف',
            icon: const Icon(Icons.share_outlined),
            onPressed: () => _share(context, store, shop),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'edit') await openShopForm(context, shop: shop);
              if (v == 'return' && context.mounted) {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => LinesEditorScreen(mode: LinesMode.shopReturn, day: store.day, shop: shop)));
              }
              if (v == 'archive') {
                shop.archived = !shop.archived;
                await store.saveShop(shop);
                if (context.mounted) Navigator.pop(context);
              }
              if (v == 'delete' && context.mounted) {
                if (await confirm(context, 'حذف "${shop.name}" نهائياً مع كل حساباته؟\nلا يمكن التراجع.')) {
                  await store.deleteShop(shop.id);
                  if (context.mounted) Navigator.pop(context);
                }
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('تعديل البيانات'))),
              const PopupMenuItem(value: 'return', child: ListTile(leading: Icon(Icons.undo), title: Text('تسجيل مرتجع'))),
              PopupMenuItem(
                  value: 'archive',
                  child: ListTile(
                      leading: const Icon(Icons.archive_outlined), title: Text(shop.archived ? 'إرجاع للقائمة' : 'إيقاف التعامل (أرشفة)'))),
              PopupMenuItem(
                  value: 'delete',
                  child: ListTile(leading: Icon(Icons.delete_outline, color: debtColor(context)), title: const Text('حذف نهائي'))),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(bal > 0 ? 'الباقي عليه' : (bal < 0 ? 'له رصيد عندك' : 'الحساب'),
                    style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  MoneyText(bal.abs(), size: 38, color: balanceColor(context, bal), showCurrency: true),
                  const Spacer(),
                  if (bal == 0) Icon(Icons.verified, color: paidColor(context), size: 32),
                ]),
                const SizedBox(height: 8),
                Wrap(spacing: 14, runSpacing: 4, children: [
                  if (shop.owner.isNotEmpty) _info(context, Icons.person_outline, shop.owner),
                  if (shop.area.isNotEmpty) _info(context, Icons.place_outlined, shop.area),
                  _info(context, Icons.event_available, lastPay == null ? 'لم يدفع بعد' : 'آخر دفعة: ${relativeDay(lastPay)}'),
                ]),
                if (shop.phone.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => launchUrl(Uri.parse('tel:${shop.phone}')),
                        icon: const Icon(Icons.call_outlined),
                        label: const Text('اتصال'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _share(context, store, shop),
                        icon: const Icon(Icons.chat_outlined),
                        label: const Text('واتساب'),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
          ),
          if (shop.notes.isNotEmpty)
            Card(
              child: ListTile(leading: const Icon(Icons.sticky_note_2_outlined), title: Text(shop.notes)),
            ),
          SectionTitle('كشف الحساب', trailing: Text('${rows.length} حركة', style: TextStyle(color: cs.onSurfaceVariant))),
          if (rows.isEmpty && shop.openingBalance == 0)
            const EmptyState(icon: Icons.receipt_long_outlined, text: 'لا توجد حركات بعد'),
          for (final d in days) _dayGroup(context, shop, d, byDay[d]!),
          if (shop.openingBalance != 0)
            Card(
              child: ListTile(
                leading: const Icon(Icons.history),
                title: const Text('دين سابق (قبل البرنامج)'),
                trailing: MoneyText(shop.openingBalance, color: debtColor(context)),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                    context, MaterialPageRoute(builder: (_) => LinesEditorScreen(mode: LinesMode.delivery, day: store.day, shop: shop))),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('عطاء'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: () => showCollectSheet(context, shop),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('تحصيل'),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _info(BuildContext c, IconData i, String t) {
    final cs = Theme.of(c).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(i, size: 16, color: cs.onSurfaceVariant),
      const SizedBox(width: 4),
      Text(t, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5)),
    ]);
  }

  Widget _dayGroup(BuildContext context, Shop shop, String day, List<StatementRow<ShopTx>> rows) {
    final cs = Theme.of(context).colorScheme;
    final endBal = rows.last.balanceAfter;
    return Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Row(children: [
            Text(relativeDay(day), style: const TextStyle(fontWeight: FontWeight.w800)),
            if (relativeDay(day) != arDay(day))
              Text('  ${shortDay(day)}', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            const Spacer(),
            Text('الرصيد ', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
            Text(money(endBal), style: TextStyle(fontWeight: FontWeight.w800, color: balanceColor(context, endBal))),
          ]),
        ),
        for (final r in rows) _txTile(context, shop, r),
      ]),
    );
  }

  Widget _txTile(BuildContext context, Shop shop, StatementRow<ShopTx> r) {
    final t = r.tx;
    final cs = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (t.type) {
      ShopTxType.delivery => (Icons.north_east, cs.primary),
      ShopTxType.returned => (Icons.undo, AppColors.warn),
      ShopTxType.payment => (Icons.south_west, paidColor(context)),
      ShopTxType.discount => (Icons.discount_outlined, creditColor(context)),
    };
    final detail = t.type.hasLines
        ? t.lines.map((l) => '${l.name} ${qtyText(l.qty)}×${money(l.price)}').join('، ')
        : (t.note.isEmpty ? timeOf(t.createdAt) : t.note);
    return ListTile(
      dense: true,
      leading: CircleAvatar(radius: 17, backgroundColor: color.withValues(alpha: 0.12), child: Icon(icon, size: 18, color: color)),
      title: Text(t.type.label, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
      subtitle: Text(detail, style: const TextStyle(fontSize: 13)),
      trailing: Text('${t.type.sign > 0 ? '+' : '−'}${money(t.amount)}',
          textDirection: TextDirection.ltr, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: color)),
      onTap: () {
        if (t.type.hasLines) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LinesEditorScreen(
                mode: t.type == ShopTxType.delivery ? LinesMode.delivery : LinesMode.shopReturn,
                day: t.day,
                shop: shop,
                existingShopTx: t,
              ),
            ),
          );
        } else {
          showCollectSheet(context, shop, day: t.day, edit: t);
        }
      },
    );
  }

  Future<void> _share(BuildContext context, Store store, Shop shop) async {
    final text = buildShopStatementText(store, shop);
    if (shop.phone.isNotEmpty) {
      var p = shop.phone.replaceAll(RegExp(r'[^0-9]'), '');
      if (p.startsWith('0')) p = p.substring(1);
      final uri = Uri.parse('https://wa.me/$p?text=${Uri.encodeComponent(text)}');
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) toast(context, 'تم نسخ الكشف، الصقه في واتساب');
  }
}

/// نص كشف الحساب لإرساله لصاحب البقالة (آخر 7 أيام)
String buildShopStatementText(Store store, Shop shop) {
  final cur = store.currency;
  final bal = store.balanceOf(shop);
  final from = shiftDay(todayKey(), -6);
  final rows = shopStatement(shop, store.shopTxs).where((r) => r.tx.day.compareTo(from) >= 0).toList();
  final b = StringBuffer()
    ..writeln('كشف حساب: ${shop.name}')
    ..writeln(store.distributorName.isEmpty ? '' : 'من: ${store.distributorName}')
    ..writeln('—————————');
  String? lastDay;
  for (final r in rows) {
    if (r.tx.day != lastDay) {
      lastDay = r.tx.day;
      b.writeln('📅 ${arDay(r.tx.day)}');
    }
    final t = r.tx;
    if (t.type.hasLines) {
      b.writeln('${t.type.label}: ${t.lines.map((l) => '${l.name} ${qtyText(l.qty)}').join('، ')} = ${money(t.amount)}');
    } else {
      b.writeln('${t.type.label}: ${money(t.amount)}');
    }
  }
  b
    ..writeln('—————————')
    ..writeln(bal > 0 ? 'الباقي عليكم: ${money(bal)} $cur' : (bal < 0 ? 'رصيدكم عندنا: ${money(-bal)} $cur' : 'الحساب مسدّد ✅'));
  return b.toString().replaceAll('\n\n', '\n');
}
