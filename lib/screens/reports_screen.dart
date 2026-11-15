import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/ledger.dart';
import '../data/store.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'today_screen.dart';

enum _Period { today, week, month, custom }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});
  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _Period period = _Period.week;
  DateTimeRange? custom;

  (String, String) get range {
    final t = todayKey();
    return switch (period) {
      _Period.today => (t, t),
      _Period.week => (shiftDay(t, -6), t),
      _Period.month => ('${t.substring(0, 8)}01', t),
      _Period.custom => custom == null ? (shiftDay(t, -6), t) : (dayKey(custom!.start), dayKey(custom!.end)),
    };
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final cs = Theme.of(context).colorScheme;
    final (from, to) = range;
    final r = store.report(from, to);
    final products = r.products.values.where((p) => p.qty != 0).toList()..sort((a, b) => b.profit.compareTo(a.profit));
    final shops = r.shops.values.toList()..sort((a, b) => b.net.compareTo(a.net));
    final days = <String>[];
    final n = parseDay(to).difference(parseDay(from)).inDays + 1;
    if (n > 1 && n <= 31) {
      for (var i = 0; i < n; i++) {
        days.add(shiftDay(from, i));
      }
    }

    return Scaffold(
      appBar: AppBar(
        leading: const MenuButton(),
        title: const Text('التقارير والأرباح'),
        actions: const [SettingsButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'exp',
        onPressed: () async {
          final res = await showDialog<(int, String, String)>(context: context, builder: (_) => const ExpenseDialog());
          if (res != null) await store.addExpense(todayKey(), res.$1, res.$2, res.$3);
        },
        icon: const Icon(Icons.add),
        label: const Text('مصروف'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
        children: [
          SegmentedButton<_Period>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: _Period.today, label: Text('اليوم')),
              ButtonSegment(value: _Period.week, label: Text('7 أيام')),
              ButtonSegment(value: _Period.month, label: Text('الشهر')),
              ButtonSegment(value: _Period.custom, label: Text('فترة')),
            ],
            selected: {period},
            onSelectionChanged: (v) async {
              if (v.first == _Period.custom) {
                final res = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2022),
                  lastDate: DateTime.now(),
                );
                if (res == null) return;
                setState(() {
                  custom = res;
                  period = _Period.custom;
                });
              } else {
                setState(() => period = v.first);
              }
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                from == to ? arDay(from) : 'من ${arDay(from)} إلى ${arDay(to)}',
                style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          // ---------------- صافي الربح
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: cs.primary, borderRadius: BorderRadius.circular(22)),
            child: DefaultTextStyle(
              style: TextStyle(color: cs.onPrimary, fontSize: 14.5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('صافي الربح', style: TextStyle(color: cs.onPrimary.withValues(alpha: 0.85))),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: MoneyText(r.netProfit, size: 34, color: cs.onPrimary, showCurrency: true),
                  ),
                  Divider(color: cs.onPrimary.withValues(alpha: 0.3), height: 22),
                  _line(context, 'المبيعات (العطاء)', r.delivered),
                  if (r.returned > 0) _line(context, 'المرتجعات', -r.returned),
                  if (r.discounts > 0) _line(context, 'الخصومات', -r.discounts),
                  _line(context, 'تكلفة البضاعة (سعر التاجر)', -r.costOfSold),
                  _line(context, 'الربح من البضاعة', r.grossProfit, bold: true),
                  _line(context, 'المصاريف', -r.expenses),
                ],
              ),
            ),
          ),
          // ---------------- النقد
          const SectionTitle('حركة الفلوس'),
          Row(
            children: [
              Expanded(
                child: StatBox(
                  label: 'حصّلت من البقالات',
                  value: r.collected,
                  icon: Icons.south_west,
                  color: paidColor(context),
                ),
              ),
              Expanded(
                child: StatBox(label: 'دفعت للتاجر', value: r.traderPaid, icon: Icons.north_east, color: cs.tertiary),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: StatBox(
                  label: 'المصاريف',
                  value: r.expenses,
                  icon: Icons.local_gas_station_outlined,
                  color: AppColors.warn,
                ),
              ),
              Expanded(
                child: StatBox(
                  label: 'الصافي في يدك',
                  value: r.cashFlow,
                  icon: Icons.account_balance_wallet_outlined,
                  color: balanceColor(context, -r.cashFlow),
                ),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: StatBox(
                  label: 'الباقي عند البقالات الآن',
                  value: store.totalOwed,
                  icon: Icons.storefront,
                  color: debtColor(context),
                ),
              ),
              Expanded(
                child: StatBox(
                  label: 'عليك للتاجر الآن',
                  value: store.totalToTraders,
                  icon: Icons.local_shipping,
                  color: debtColor(context),
                ),
              ),
            ],
          ),
          // ---------------- يومي
          if (days.isNotEmpty) ...[
            const SectionTitle('المبيعات يوماً بيوم'),
            Card(
              child: Padding(padding: const EdgeInsets.all(14), child: _bars(context, days, r.dailySales)),
            ),
          ],
          // ---------------- الأصناف
          if (products.isNotEmpty) ...[
            const SectionTitle('الأصناف'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    for (final p in products) ...[
                      Row(
                        children: [
                          Expanded(
                            child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                          Text('${qtyText(p.qty)} ${p.unit}', style: TextStyle(color: cs.onSurfaceVariant)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: products.first.profit <= 0
                                    ? 0
                                    : (p.profit / products.first.profit).clamp(0, 1).toDouble(),
                                minHeight: 8,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'مبيعات ${money(p.sales)} · ربح ${money(p.profit)}',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          ],
          // ---------------- البقالات
          if (shops.isNotEmpty) ...[
            const SectionTitle('البقالات في الفترة'),
            Card(
              child: Column(
                children: [
                  for (final s in shops)
                    ListTile(
                      dense: true,
                      title: Text(s.shop.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                      subtitle: Text('عطاء ${money(s.net)} · دفع ${money(s.paid)}'),
                      trailing: Text(
                        money(s.net - s.paid),
                        style: TextStyle(fontWeight: FontWeight.w700, color: balanceColor(context, s.net - s.paid)),
                      ),
                    ),
                ],
              ),
            ),
          ],
          // ---------------- المصاريف
          const SectionTitle('المصاريف'),
          ..._expenses(context, store, from, to),
        ],
      ),
    );
  }

  List<Widget> _expenses(BuildContext context, Store store, String from, String to) {
    final list = store.expensesOf(from: from, to: to);
    if (list.isEmpty) {
      return [const Padding(padding: EdgeInsets.all(12), child: Text('لا توجد مصاريف في هذه الفترة'))];
    }
    return [
      Card(
        child: Column(
          children: [
            for (final e in list)
              ListTile(
                dense: true,
                leading: const Icon(Icons.receipt_outlined, color: AppColors.warn),
                title: Text(
                  e.note.isEmpty ? e.category : '${e.category} · ${e.note}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(relativeDay(e.day)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(money(e.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () async {
                        final old = await store.deleteExpense(e.id);
                        if (old != null && context.mounted) {
                          undoToast(context, 'حُذف المصروف', () => store.saveExpense(old));
                        }
                      },
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _line(BuildContext c, String a, int v, {bool bold = false}) {
    final on = Theme.of(c).colorScheme.onPrimary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              a,
              style: TextStyle(color: on, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
          Text(
            v < 0 ? '− ${money(-v)}' : money(v),
            textDirection: TextDirection.ltr,
            style: TextStyle(color: on, fontWeight: FontWeight.w700, fontSize: bold ? 16 : 14.5),
          ),
        ],
      ),
    );
  }

  Widget _bars(BuildContext c, List<String> days, Map<String, int> data) {
    final maxV = days.fold<int>(1, (m, d) => (data[d] ?? 0) > m ? data[d]! : m);
    final color = Theme.of(c).colorScheme.primary;
    final showEvery = days.length > 14 ? 3 : 1;
    return SizedBox(
      height: 160,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Tooltip(
                message: '${arDay(days[i])}\n${money(data[days[i]] ?? 0)}',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: 120.0 * ((data[days[i]] ?? 0).clamp(0, maxV)) / maxV + 2,
                        decoration: BoxDecoration(
                          color: days[i] == todayKey() ? color : color.withValues(alpha: 0.55),
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(i % showEvery == 0 ? '${parseDay(days[i]).day}' : '', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// يستخدم في الاختبارات
PeriodReport reportFor(Store s, String from, String to) => s.report(from, to);
