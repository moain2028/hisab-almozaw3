/// reports_screen.dart — التقارير بهيكلية تطبيق (لا صفحة ويب طويلة).
///
/// الرئيسية للتقارير (تُرى كاملة بلا تمرير تقريباً):
///   1. الفترة **مثبّتة** في الأعلى (اليوم · 7 أيام · الشهر · فترة)
///   2. بطاقة صافي الربح (رقم واحد كبير + سطرين)
///   3. شبكة 2×2 لحركة الفلوس
///   4. قائمة أقسام — كل قسم **يفتح صفحته**: تفاصيل الربح، الأصناف، البقالات، المبيعات اليومية، المصاريف
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/ledger.dart';
import '../data/store.dart';
import '../ui/pinned.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'expenses_screen.dart';
import 'shop_detail_screen.dart';

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

  Future<void> _pick(_Period p) async {
    if (p != _Period.custom) return setState(() => period = p);
    final res = await showDateRangePicker(context: context, firstDate: DateTime(2022), lastDate: DateTime.now());
    if (res == null) return;
    setState(() {
      custom = res;
      period = _Period.custom;
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final cs = Theme.of(context).colorScheme;
    final (from, to) = range;
    final r = store.report(from, to);
    final label = from == to ? arDay(from) : '${shortDay(from)} ← ${shortDay(to)}';
    void open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    final products = r.products.values.where((p) => p.qty != 0).length;
    final shops = r.shops.length;
    final expCount = store.expensesOf(from: from, to: to).length;

    return Scaffold(
      appBar: AppBar(leading: const MenuButton(), title: const Text('التقارير'), actions: const [SettingsButton()]),
      body: CustomScrollView(
        slivers: [
          PinnedHeader(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: Column(
                children: [
                  SegmentedButton<_Period>(
                    showSelectedIcon: false,
                    style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
                    segments: const [
                      ButtonSegment(value: _Period.today, label: Text('اليوم')),
                      ButtonSegment(value: _Period.week, label: Text('7 أيام')),
                      ButtonSegment(value: _Period.month, label: Text('الشهر')),
                      ButtonSegment(value: _Period.custom, icon: Icon(Icons.date_range_rounded, size: 18)),
                    ],
                    selected: {period},
                    onSelectionChanged: (v) => _pick(v.first),
                  ),
                  const SizedBox(height: Space.sm),
                  Text(
                    label,
                    style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, Space.xl),
            sliver: SliverList.list(
              children: [
                // ---------------- صافي الربح
                Material(
                  borderRadius: BorderRadius.circular(Radii.lg),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: BoxDecoration(gradient: heroGradient(cs)),
                    child: InkWell(
                      onTap: () => open(_ProfitPage(r: r, label: label)),
                      child: Padding(
                        padding: const EdgeInsets.all(Space.lg),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('صافي الربح', style: TextStyle(color: kOnHero.withValues(alpha: .85))),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: MoneyText(r.netProfit, size: 32, color: kOnHero, showCurrency: true),
                                  ),
                                  const SizedBox(height: Space.xs),
                                  Text(
                                    'مبيعات ${money(r.netSales)} · مصاريف ${money(r.expenses)}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: kOnHero.withValues(alpha: .85), fontSize: 13),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_left_rounded, color: kOnHero),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: Space.md),

                // ---------------- حركة الفلوس 2×2
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: Space.sm,
                  crossAxisSpacing: Space.sm,
                  childAspectRatio: 2.1,
                  children: [
                    _Kpi('حصّلت', r.collected, Icons.south_west_rounded, paidColor(context)),
                    _Kpi('دفعت للتاجر', r.traderPaid, Icons.north_east_rounded, cs.tertiary),
                    _Kpi('الباقي عند البقالات', store.totalOwed, Icons.storefront_rounded, debtColor(context)),
                    _Kpi(
                      'في يدك',
                      r.cashFlow,
                      Icons.account_balance_wallet_rounded,
                      balanceColor(context, -r.cashFlow),
                    ),
                  ],
                ),

                // ---------------- الأقسام
                const SectionTitle('التفاصيل'),
                Card(
                  margin: EdgeInsets.zero,
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      _Nav(Icons.calculate_rounded, 'تفاصيل الربح', 'المبيعات − التكلفة − المصاريف', () {
                        open(_ProfitPage(r: r, label: label));
                      }),
                      const Divider(height: 1, indent: 56),
                      _Nav(Icons.inventory_2_rounded, 'الأصناف', '$products صنف مباع', () {
                        open(_ProductsPage(r: r, label: label));
                      }),
                      const Divider(height: 1, indent: 56),
                      _Nav(Icons.storefront_rounded, 'البقالات', '$shops بقالة في الفترة', () {
                        open(_ShopsPage(r: r, label: label));
                      }),
                      const Divider(height: 1, indent: 56),
                      _Nav(Icons.bar_chart_rounded, 'المبيعات يوماً بيوم', label, () {
                        open(_DailyPage(r: r, from: from, to: to, label: label));
                      }),
                      const Divider(height: 1, indent: 56),
                      _Nav(Icons.receipt_long_rounded, 'المصاريف', '$expCount مصروف · ${money(r.expenses)}', () {
                        open(const ExpensesScreen());
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  const _Kpi(this.label, this.value, this.icon, this.color);
  final String label;
  final int value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
      decoration: BoxDecoration(color: cs.surfaceContainerHigh, borderRadius: BorderRadius.circular(Radii.md)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: Space.xs),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
          FittedBox(child: MoneyText(value, size: 19, color: color)),
        ],
      ),
    );
  }
}

class _Nav extends StatelessWidget {
  const _Nav(this.icon, this.title, this.sub, this.onTap);
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: cs.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: const Icon(Icons.chevron_left_rounded),
    );
  }
}

/// غلاف موحّد لصفحات التفاصيل: عنوان + الفترة تحته
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.label, required this.children});
  final String title;
  final String label;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xl), children: children),
    );
  }
}

class _ProfitPage extends StatelessWidget {
  const _ProfitPage({required this.r, required this.label});
  final PeriodReport r;
  final String label;
  @override
  Widget build(BuildContext context) {
    Widget row(String a, int v, {bool bold = false, Color? c}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      child: Row(
        children: [
          Expanded(
            child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ),
          Text(
            v < 0 ? '− ${money(-v)}' : money(v),
            textDirection: TextDirection.ltr,
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: bold ? 17 : 15, color: c, fontFeatures: tabular),
          ),
        ],
      ),
    );
    return _Page(
      title: 'تفاصيل الربح',
      label: label,
      children: [
        Card(
          child: Column(
            children: [
              row('المبيعات (العطاء)', r.delivered),
              if (r.returned > 0) row('المرتجعات', -r.returned),
              if (r.discounts > 0) row('الخصومات', -r.discounts),
              const Divider(height: 1),
              row('صافي المبيعات', r.netSales, bold: true),
              row('تكلفة البضاعة (سعر التاجر)', -r.costOfSold),
              const Divider(height: 1),
              row('الربح من البضاعة', r.grossProfit, bold: true),
              row('المصاريف', -r.expenses),
              const Divider(height: 1),
              row('صافي الربح', r.netProfit, bold: true, c: balanceColor(context, -r.netProfit)),
            ],
          ),
        ),
        const SectionTitle('حركة التاجر'),
        Card(
          child: Column(
            children: [
              row('استلمت بضاعة', r.traderPickups),
              if (r.traderReturns > 0) row('أرجعت للتاجر', -r.traderReturns),
              row('دفعت للتاجر', r.traderPaid),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductsPage extends StatelessWidget {
  const _ProductsPage({required this.r, required this.label});
  final PeriodReport r;
  final String label;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final list = r.products.values.where((p) => p.qty != 0).toList()..sort((a, b) => b.profit.compareTo(a.profit));
    final top = list.isEmpty || list.first.profit <= 0 ? 1 : list.first.profit;
    return _Page(
      title: 'الأصناف',
      label: label,
      children: [
        if (list.isEmpty) const EmptyState(icon: Icons.inventory_2_outlined, text: 'لا مبيعات في هذه الفترة'),
        for (final p in list)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      ),
                      Text('${qtyText(p.qty)} ${p.unit}', style: TextStyle(color: cs.onSurfaceVariant)),
                    ],
                  ),
                  const SizedBox(height: Space.sm),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: LinearProgressIndicator(value: (p.profit / top).clamp(0, 1).toDouble(), minHeight: 8),
                  ),
                  const SizedBox(height: Space.sm),
                  Row(
                    children: [
                      Expanded(
                        child: Text('مبيعات ${money(p.sales)}', style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                      Text(
                        'ربح ${money(p.profit)}',
                        style: TextStyle(fontWeight: FontWeight.w700, color: paidColor(context)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ShopsPage extends StatelessWidget {
  const _ShopsPage({required this.r, required this.label});
  final PeriodReport r;
  final String label;
  @override
  Widget build(BuildContext context) {
    final list = r.shops.values.toList()..sort((a, b) => b.net.compareTo(a.net));
    return _Page(
      title: 'البقالات',
      label: label,
      children: [
        if (list.isEmpty) const EmptyState(icon: Icons.storefront_outlined, text: 'لا حركة في هذه الفترة'),
        for (final s in list)
          Card(
            child: ListTile(
              leading: ShopAvatar(s.shop.name, active: s.net - s.paid > 0),
              title: Text(s.shop.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('عطاء ${money(s.net)} · دفع ${money(s.paid)}'),
              trailing: BalanceBadge(s.net - s.paid, size: 15),
              onTap: () =>
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: s.shop.id))),
            ),
          ),
      ],
    );
  }
}

class _DailyPage extends StatelessWidget {
  const _DailyPage({required this.r, required this.from, required this.to, required this.label});
  final PeriodReport r;
  final String from;
  final String to;
  final String label;
  @override
  Widget build(BuildContext context) {
    final n = parseDay(to).difference(parseDay(from)).inDays + 1;
    final days = [for (var i = 0; i < n.clamp(1, 62); i++) shiftDay(from, i)];
    final cs = Theme.of(context).colorScheme;
    return _Page(
      title: 'المبيعات يوماً بيوم',
      label: label,
      children: [
        if (days.length > 1)
          Card(
            child: Padding(padding: const EdgeInsets.all(Space.md), child: salesBars(context, days, r.dailySales)),
          ),
        Card(
          child: Column(
            children: [
              for (final d in days.reversed)
                ListTile(
                  dense: true,
                  title: Text(relativeDay(d), style: const TextStyle(fontWeight: FontWeight.w600)),
                  trailing: Text(
                    money(r.dailySales[d] ?? 0),
                    style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSurface, fontFeatures: tabular),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

Widget salesBars(BuildContext c, List<String> days, Map<String, int> data) {
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

// يستخدم في الاختبارات
PeriodReport reportFor(Store s, String from, String to) => s.report(from, to);
