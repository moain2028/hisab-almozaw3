import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/ledger.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'lines_editor.dart';

/// حساب التاجر: كل صباح تستلم بضاعة وتدفع له حساب أمس
class TraderTab extends StatelessWidget {
  const TraderTab({super.key});
  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    return TraderScreen(trader: store.mainTrader, isTab: true);
  }
}

class TraderScreen extends StatelessWidget {
  const TraderScreen({super.key, required this.trader, this.isTab = false});
  final Trader trader;
  final bool isTab;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final cs = Theme.of(context).colorScheme;
    final t = store.trader(trader.id) ?? trader;
    final bal = store.traderBalanceOf(t);
    final idx = store.traderIndex(t);
    final rows = [for (var i = 0; i < idx.length; i++) StatementRow(idx.entries[i], idx.balanceAfter(i))];
    final day = store.day;
    final todayPickup = store
        .traderTxsOf(t.id, day: day)
        .where((x) => x.type == TraderTxType.pickup)
        .fold(0, (a, x) => a + x.amount);
    final todayPaid = store
        .traderTxsOf(t.id, day: day)
        .where((x) => x.type == TraderTxType.payment)
        .fold(0, (a, x) => a + x.amount);
    // حساب أمس: ما استلمته أمس (الذي يُدفع عادة صباح اليوم)
    final yesterday = shiftDay(day, -1);
    final yPickup = store
        .traderTxsOf(t.id, day: yesterday)
        .where((x) => x.type != TraderTxType.payment)
        .fold(0, (a, x) => a + x.effect);

    final byDay = <String, List<StatementRow<TraderTx>>>{};
    for (final r in rows) {
      (byDay[r.tx.day] ??= []).add(r);
    }
    final days = byDay.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      appBar: AppBar(
        title: Text(isTab ? 'التاجر' : t.name),
        actions: [
          IconButton(
            tooltip: 'بيانات التاجر',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editTrader(context, store, t),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (isTab) const DayBar(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.local_shipping, color: cs.tertiary),
                        const SizedBox(width: 8),
                        Text(t.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      bal > 0 ? 'عليك للتاجر' : (bal < 0 ? 'لك عند التاجر' : 'الحساب'),
                      style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                    ),
                    MoneyText(
                      bal.abs(),
                      size: 36,
                      color: bal > 0 ? debtColor(context) : paidColor(context),
                      showCurrency: true,
                    ),
                    const Divider(height: 22),
                    KvRow('استلام ${relativeDay(day)}', todayPickup),
                    KvRow('دفعت ${relativeDay(day)}', todayPaid, color: paidColor(context)),
                    if (yPickup > 0) KvRow('بضاعة ${relativeDay(yesterday)}', yPickup),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _pickup(context, store, t),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    icon: const Icon(Icons.inventory_2_outlined),
                    label: const Text('استلام بضاعة'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => _pay(context, store, t, bal, yPickup),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    icon: const Icon(Icons.payments_outlined),
                    label: const Text('دفعة للتاجر'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => LinesEditorScreen(mode: LinesMode.traderReturn, day: day, trader: t),
                ),
              ),
              icon: const Icon(Icons.undo),
              label: const Text('إرجاع بضاعة للتاجر'),
            ),
          ),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: SectionTitle('كشف حساب التاجر')),
          if (rows.isEmpty)
            const EmptyState(icon: Icons.receipt_long_outlined, text: 'سجّل استلام بضاعة الصباح من التاجر'),
          for (final d in days)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: _dayGroup(context, t, d, byDay[d]!)),
        ],
      ),
    );
  }

  Widget _dayGroup(BuildContext context, Trader t, String day, List<StatementRow<TraderTx>> rows) {
    final cs = Theme.of(context).colorScheme;
    final endBal = rows.last.balanceAfter;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            ),
            child: Row(
              children: [
                Text(relativeDay(day), style: const TextStyle(fontWeight: FontWeight.w700)),
                const Spacer(),
                Text('عليك ', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                Text(
                  money(endBal),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: endBal > 0 ? debtColor(context) : paidColor(context),
                  ),
                ),
              ],
            ),
          ),
          for (final r in rows) _tile(context, t, r.tx),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, Trader t, TraderTx x) {
    final cs = Theme.of(context).colorScheme;
    final (IconData icon, Color color) = switch (x.type) {
      TraderTxType.pickup => (Icons.south_west, cs.tertiary),
      TraderTxType.returned => (Icons.undo, AppColors.warn),
      TraderTxType.payment => (Icons.north_east, paidColor(context)),
    };
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 17,
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, size: 18, color: color),
      ),
      title: Text(x.type.label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
      subtitle: Text(
        x.type.hasLines
            ? x.lines.map((l) => '${l.name} ${qtyText(l.qty)}').join('، ')
            : (x.note.isEmpty ? timeOf(x.createdAt) : x.note),
        style: const TextStyle(fontSize: 13),
      ),
      trailing: Text(
        '${x.type.sign > 0 ? '+' : '−'}${money(x.amount)}',
        textDirection: TextDirection.ltr,
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5, color: color),
      ),
      onTap: () async {
        if (x.type.hasLines) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LinesEditorScreen(
                mode: x.type == TraderTxType.pickup ? LinesMode.pickup : LinesMode.traderReturn,
                day: x.day,
                trader: t,
                existingTraderTx: x,
              ),
            ),
          );
        } else {
          final store = context.read<Store>();
          final v = await askMoney(context, 'تعديل الدفعة (اكتب 0 للحذف)', initial: x.amount);
          if (v == null) return;
          if (v <= 0) {
            final old = await store.deleteTraderTx(x.id);
            if (old != null && context.mounted) undoToast(context, 'حُذفت الدفعة', () => store.saveTraderTx(old));
          } else {
            await store.saveTraderTx(
              TraderTx(
                id: x.id,
                traderId: x.traderId,
                type: x.type,
                day: x.day,
                createdAt: x.createdAt,
                amount: v,
                note: x.note,
              ),
            );
          }
        }
      },
    );
  }

  Future<void> _pickup(BuildContext context, Store store, Trader t) async {
    final prev = store.lastPickupBefore(t.id, store.day);
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LinesEditorScreen(
          mode: LinesMode.pickup,
          day: store.day,
          trader: t,
          prefill: prev == null ? null : {for (final l in prev.lines) l.productId: l.qty},
        ),
      ),
    );
  }

  Future<void> _pay(BuildContext context, Store store, Trader t, int bal, int yesterday) async {
    final ctl = TextEditingController();
    final r = await showDialog<int>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final a = parseMoney(ctl.text) ?? 0;
          return AlertDialog(
            title: const Text('دفعة للتاجر'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                KvRow('عليك الآن', bal, bold: true, color: debtColor(ctx)),
                const SizedBox(height: 10),
                NumberField(controller: ctl, autofocus: true, big: true, onChanged: (_) => setS(() {})),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    if (bal > 0)
                      ActionChip(label: Text('الكل ${money(bal)}'), onPressed: () => setS(() => ctl.text = '$bal')),
                    if (yesterday > 0 && yesterday < bal)
                      ActionChip(
                        label: Text('حساب أمس ${money(yesterday)}'),
                        onPressed: () => setS(() => ctl.text = '$yesterday'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('يبقى عليك: ${money(bal - a)}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
              FilledButton(onPressed: a > 0 ? () => Navigator.pop(ctx, a) : null, child: const Text('تسجيل')),
            ],
          );
        },
      ),
    );
    if (r == null || r <= 0) return;
    await store.saveTraderTx(
      TraderTx(id: newId(), traderId: t.id, type: TraderTxType.payment, day: store.day, createdAt: nowMs(), amount: r),
    );
  }

  Future<void> _editTrader(BuildContext context, Store store, Trader t) async {
    final name = TextEditingController(text: t.name);
    final phone = TextEditingController(text: t.phone);
    final ob = TextEditingController(text: t.openingBalance == 0 ? '' : '${t.openingBalance}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('بيانات التاجر'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'اسم التاجر / المؤسسة'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'الجوال'),
              ),
              const SizedBox(height: 10),
              NumberField(controller: ob, label: 'مبلغ سابق عليك قبل البرنامج'),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    t
      ..name = name.text.trim().isEmpty ? 'التاجر' : name.text.trim()
      ..phone = normalizeDigits(phone.text)
      ..openingBalance = parseMoney(ob.text) ?? 0;
    await store.saveTrader(t);
  }
}
