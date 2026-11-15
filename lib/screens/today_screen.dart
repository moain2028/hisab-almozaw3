import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/ledger.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'collect_sheet.dart';
import 'lines_editor.dart';
import 'shop_detail_screen.dart';
import 'shop_form.dart';
import 'trader_screen.dart';

/// الشاشة الرئيسية: يوم العمل كاملاً
/// الصباح: عطاء للبقالات ، الليل: تحصيل ومعرفة الباقي.
class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  /// false = وضع العطاء (الصباح) ، true = وضع التحصيل (الليل)
  bool collectMode = DateTime.now().hour >= 15;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final shops = store.shops;
    final s = store.summary();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(store.distributorName.isEmpty ? 'حساب الموزع' : store.distributorName),
        actions: [
          IconButton(
            tooltip: 'إضافة بقالة',
            onPressed: () => openShopForm(context),
            icon: const Icon(Icons.add_business_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const DayBar(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _HeroCard(summary: s, shopsCount: shops.length),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Row(children: [
              Expanded(
                child: StatBox(
                  label: 'استلام من التاجر',
                  value: s.picked,
                  icon: Icons.local_shipping_outlined,
                  color: cs.tertiary,
                  onTap: () => _pickup(context, store),
                  sub: s.picked == 0 ? 'اضغط للتسجيل' : null,
                ),
              ),
              Expanded(
                child: StatBox(
                  label: 'المصاريف',
                  value: s.expenses,
                  icon: Icons.local_gas_station_outlined,
                  color: AppColors.warn,
                  onTap: () => _addExpense(context, store),
                  sub: s.expenses == 0 ? 'اضغط للإضافة' : null,
                ),
              ),
            ]),
          ),
          if (store.products.isNotEmpty && s.picked > 0) _StockCard(rows: store.stockOf()),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: SegmentedButton<bool>(
              style: SegmentedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                textStyle: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800),
              ),
              segments: [
                ButtonSegment(
                  value: false,
                  icon: const Icon(Icons.wb_sunny_outlined),
                  label: Text('العطاء (${s.deliveredShops.length}/${shops.length})'),
                ),
                ButtonSegment(
                  value: true,
                  icon: const Icon(Icons.nightlight_outlined),
                  label: Text('التحصيل (${s.paidShops.length})'),
                ),
              ],
              selected: {collectMode},
              onSelectionChanged: (v) => setState(() => collectMode = v.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 4, 18, 4),
            child: Text(
              collectMode
                  ? 'اضغط على البقالة لتسجيل ما دفعه، ويظهر لك الباقي عنده.'
                  : 'اضغط على البقالة لتسجيل ما أعطيته اليوم.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ),
          if (shops.isEmpty)
            EmptyState(
              icon: Icons.storefront_outlined,
              text: 'ابدأ بإضافة البقالات التي توزع عليها',
              action: FilledButton.icon(
                onPressed: () => openShopForm(context),
                icon: const Icon(Icons.add),
                label: const Text('إضافة بقالة'),
              ),
            ),
          for (final shop in shops)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: collectMode
                  ? _CollectTile(shop: shop, day: store.dayOf(shop))
                  : _DeliverTile(shop: shop, day: store.dayOf(shop)),
            ),
        ],
      ),
    );
  }

  Future<void> _pickup(BuildContext context, Store store) async {
    final trader = store.mainTrader;
    final today = store.traderTxsOf(trader.id, day: store.day).where((t) => t.type == TraderTxType.pickup).toList();
    if (today.isNotEmpty) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => TraderScreen(trader: trader)));
      return;
    }
    // اقتراح: كميات آخر استلام
    final prev = store.traderTxs.where((t) => t.type == TraderTxType.pickup && t.traderId == trader.id && t.day.compareTo(store.day) < 0).toList()
      ..sort((a, b) => b.day.compareTo(a.day));
    Map<String, double>? prefill;
    if (prev.isNotEmpty) {
      prefill = {for (final l in prev.first.lines) l.productId: l.qty};
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LinesEditorScreen(mode: LinesMode.pickup, day: store.day, trader: trader, prefill: prefill),
      ),
    );
  }

  Future<void> _addExpense(BuildContext context, Store store) async {
    final r = await showDialog<(int, String, String)>(context: context, builder: (_) => const ExpenseDialog());
    if (r != null) await store.addExpense(store.day, r.$1, r.$2, r.$3);
  }
}

// ------------------------------------------------------------------ بطاقة الملخص

class _HeroCard extends StatelessWidget {
  const _HeroCard({required this.summary, required this.shopsCount});
  final DaySummary summary;
  final int shopsCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = summary;
    final netDelivered = s.delivered - s.returned;
    // نسبة ما حُصّل من إجمالي المطلوب اليوم
    final base = s.collected + (s.remainingEndOfDay > 0 ? s.remainingEndOfDay : 0);
    final progress = base <= 0 ? 0.0 : (s.collected / base).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primary, Color.lerp(cs.primary, Colors.black, 0.25)!],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: DefaultTextStyle(
        style: TextStyle(color: cs.onPrimary, fontSize: 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('الباقي عند البقالات', style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.85), fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          MoneyText(s.remainingEndOfDay, size: 36, color: cs.onPrimary, showCurrency: true),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress.toDouble(),
              minHeight: 7,
              backgroundColor: cs.onPrimary.withValues(alpha: 0.2),
              valueColor: AlwaysStoppedAnimation(cs.onPrimary),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            _mini(context, 'العطاء', netDelivered, Icons.arrow_upward),
            _mini(context, 'المحصّل', s.collected, Icons.arrow_downward),
            _mini(context, 'في جيبك', s.collected - s.traderPaid - s.expenses, Icons.account_balance_wallet_outlined),
          ]),
        ]),
      ),
    );
  }

  Widget _mini(BuildContext c, String label, int v, IconData icon) {
    final on = Theme.of(c).colorScheme.onPrimary;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 14, color: on.withValues(alpha: 0.8)),
          const SizedBox(width: 3),
          Text(label, style: TextStyle(fontSize: 12.5, color: on.withValues(alpha: 0.85))),
        ]),
        FittedBox(fit: BoxFit.scaleDown, child: MoneyText(v, size: 17, color: on)),
      ]),
    );
  }
}

// ------------------------------------------------------------------ البضاعة في السيارة

class _StockCard extends StatelessWidget {
  const _StockCard({required this.rows});
  final List<StockRow> rows;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        child: ExpansionTile(
          shape: const Border(),
          leading: Icon(Icons.inventory_outlined, color: cs.tertiary),
          title: const Text('البضاعة الباقية في السيارة', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          subtitle: Text(rows.map((r) => '${r.name} ${qtyText(r.onHand)}').join(' · '),
              maxLines: 1, overflow: TextOverflow.ellipsis),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Table(
                columnWidths: const {0: FlexColumnWidth(1.6)},
                children: [
                  TableRow(
                    children: ['الصنف', 'استلمت', 'وزّعت', 'الباقي']
                        .map((t) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Text(t, style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurfaceVariant, fontSize: 13)),
                            ))
                        .toList(),
                  ),
                  for (final r in rows)
                    TableRow(children: [
                      Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(r.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(qtyText(r.picked - r.traderReturns))),
                      Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Text(qtyText(r.delivered - r.shopReturns))),
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Text(qtyText(r.onHand),
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: r.onHand < 0 ? debtColor(context) : (r.onHand > 0 ? AppColors.warn : paidColor(context)))),
                      ),
                    ]),
                ],
              ),
            ),
            if (rows.any((r) => r.onHand < 0))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text('تنبيه: وزّعت أكثر مما استلمت في بعض الأصناف. راجع الاستلام.',
                    style: TextStyle(color: debtColor(context), fontSize: 12.5, fontWeight: FontWeight.w600)),
              ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ بطاقات البقالات

class _DeliverTile extends StatelessWidget {
  const _DeliverTile({required this.shop, required this.day});
  final Shop shop;
  final ShopDay day;

  @override
  Widget build(BuildContext context) {
    final store = context.read<Store>();
    final cs = Theme.of(context).colorScheme;
    final txs = store.shopTxsOf(shop.id, day: store.day).where((t) => t.type == ShopTxType.delivery).toList();
    final summary = <String>[];
    for (final t in txs) {
      for (final l in t.lines) {
        summary.add('${l.name} ${qtyText(l.qty)}');
      }
    }
    final done = txs.isNotEmpty;
    return Card(
      color: done ? cs.primaryContainer.withValues(alpha: 0.35) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LinesEditorScreen(
              mode: LinesMode.delivery,
              day: store.day,
              shop: shop,
              existingShopTx: txs.isNotEmpty ? txs.first : null,
            ),
          ),
        ),
        onLongPress: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: shop.id))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(children: [
            ShopAvatar(shop.name, active: done, done: done),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shop.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
                const SizedBox(height: 2),
                Text(
                  done ? summary.join(' · ') : (day.before > 0 ? 'عليه من قبل ${money(day.before)}' : 'لم يُعطَ بعد'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5),
                ),
              ]),
            ),
            const SizedBox(width: 8),
            if (done)
              MoneyText(day.delivered, size: 18, color: cs.primary)
            else
              FilledButton.tonalIcon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LinesEditorScreen(mode: LinesMode.delivery, day: store.day, shop: shop),
                  ),
                ),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('عطاء'),
              ),
          ]),
        ),
      ),
    );
  }
}

class _CollectTile extends StatelessWidget {
  const _CollectTile({required this.shop, required this.day});
  final Shop shop;
  final ShopDay day;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rem = day.remaining;
    final paid = day.hasPayment;
    final lines = <String>[];
    if (day.before != 0) lines.add('${day.before > 0 ? 'سابق' : 'رصيد له'} ${money(day.before.abs())}');
    if (day.delivered > 0) lines.add('عطاء ${money(day.delivered)}');
    if (day.returned > 0) lines.add('مرتجع ${money(day.returned)}');
    if (paid) lines.add('دفع ${money(day.paid)}');
    return Card(
      color: paid ? paidColor(context).withValues(alpha: 0.08) : null,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => showCollectSheet(context, shop),
        onLongPress: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: shop.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            ShopAvatar(shop.name, active: day.hasDelivery, done: paid),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shop.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
                const SizedBox(height: 2),
                Text(lines.isEmpty ? 'لا شيء' : lines.join(' · '),
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5)),
              ]),
            ),
            const SizedBox(width: 8),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(paid ? 'الباقي' : 'المطلوب', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
              BalanceBadge(rem),
            ]),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ نافذة المصروف

class ExpenseDialog extends StatefulWidget {
  const ExpenseDialog({super.key});
  @override
  State<ExpenseDialog> createState() => _ExpenseDialogState();
}

class _ExpenseDialogState extends State<ExpenseDialog> {
  final amount = TextEditingController();
  final note = TextEditingController();
  String cat = expenseCategories.first;

  @override
  void dispose() {
    amount.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('مصروف'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final c in expenseCategories)
              ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => setState(() => cat = c)),
          ]),
          const SizedBox(height: 12),
          NumberField(controller: amount, autofocus: true, big: true, hint: 'المبلغ'),
          const SizedBox(height: 10),
          TextField(controller: note, decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('إلغاء')),
        FilledButton(
          onPressed: () {
            final a = parseMoney(amount.text) ?? 0;
            if (a <= 0) return;
            Navigator.pop(context, (a, cat, note.text.trim()));
          },
          child: const Text('حفظ'),
        ),
      ],
    );
  }
}
