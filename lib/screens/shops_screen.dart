import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/ledger.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'shop_detail_screen.dart';
import 'shop_form.dart';

enum _Sort { route, debt, name, late }

/// كل البقالات وأرصدتها: من عليه، كم، ومن تأخر في الدفع
class ShopsScreen extends StatefulWidget {
  const ShopsScreen({super.key});
  @override
  State<ShopsScreen> createState() => _ShopsScreenState();
}

class _ShopsScreenState extends State<ShopsScreen> {
  String q = '';
  _Sort sort = _Sort.route;
  bool reorder = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final cs = Theme.of(context).colorScheme;
    final all = store.shops;
    final balances = {for (final s in all) s.id: store.balanceOf(s)};
    final lastPay = {for (final s in all) s.id: lastPaymentDay(s.id, store.shopTxs)};
    final today = todayKey();
    int daysSince(String? d) => d == null ? 9999 : parseDay(today).difference(parseDay(d)).inDays;

    var list = all.where((s) => q.isEmpty || s.name.contains(q) || s.owner.contains(q) || s.area.contains(q)).toList();
    switch (sort) {
      case _Sort.route:
        break;
      case _Sort.debt:
        list.sort((a, b) => balances[b.id]!.compareTo(balances[a.id]!));
      case _Sort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _Sort.late:
        list = list.where((s) => balances[s.id]! > 0).toList()
          ..sort((a, b) => daysSince(lastPay[b.id]).compareTo(daysSince(lastPay[a.id])));
    }
    final total = balances.values.where((v) => v > 0).fold(0, (a, b) => a + b);
    final debtors = balances.values.where((v) => v > 0).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('البقالات'),
        actions: [
          IconButton(
            tooltip: reorder ? 'تم' : 'ترتيب خط السير',
            onPressed: () => setState(() {
              reorder = !reorder;
              if (reorder) sort = _Sort.route;
            }),
            icon: Icon(reorder ? Icons.check : Icons.swap_vert),
          ),
        ],
      ),
      floatingActionButton: reorder
          ? null
          : FloatingActionButton.extended(
              onPressed: () => openShopForm(context),
              icon: const Icon(Icons.add),
              label: const Text('بقالة جديدة'),
            ),
      body: all.isEmpty
          ? Center(
              child: EmptyState(
                icon: Icons.storefront_outlined,
                text: 'لا توجد بقالات بعد',
                action: FilledButton.icon(onPressed: () => openShopForm(context), icon: const Icon(Icons.add), label: const Text('إضافة بقالة')),
              ),
            )
          : reorder
              ? _reorderList(store, all)
              : ListView(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  children: [
                    Card(
                      color: debtColor(context).withValues(alpha: 0.07),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('مجموع الباقي عند البقالات', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                              MoneyText(total, size: 28, color: debtColor(context), showCurrency: true),
                            ]),
                          ),
                          Column(children: [
                            Text('$debtors', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: debtColor(context))),
                            Text('من ${all.length} عليهم', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                          ]),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      onChanged: (v) => setState(() => q = v.trim()),
                      decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث بالاسم أو الحي'),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final e in {
                          _Sort.route: 'خط السير',
                          _Sort.debt: 'الأكثر ديناً',
                          _Sort.late: 'المتأخرين',
                          _Sort.name: 'أبجدي',
                        }.entries)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(end: 6),
                            child: ChoiceChip(label: Text(e.value), selected: sort == e.key, onSelected: (_) => setState(() => sort = e.key)),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 4),
                    for (final s in list) _tile(context, s, balances[s.id]!, lastPay[s.id], daysSince(lastPay[s.id])),
                    if (store.archivedShops.isNotEmpty) ...[
                      const SectionTitle('بقالات موقوفة'),
                      for (final s in store.archivedShops)
                        Card(
                          child: ListTile(
                            title: Text(s.name, style: TextStyle(color: cs.onSurfaceVariant)),
                            trailing: BalanceBadge(store.balanceOf(s), size: 14),
                            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: s.id))),
                          ),
                        ),
                    ],
                  ],
                ),
    );
  }

  Widget _tile(BuildContext context, Shop s, int bal, String? lastPay, int since) {
    final cs = Theme.of(context).colorScheme;
    final late = bal > 0 && since >= 3;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
        leading: ShopAvatar(s.name, active: bal > 0),
        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16.5)),
        subtitle: Text(
          [
            if (s.area.isNotEmpty) s.area,
            lastPay == null ? 'لم يدفع بعد' : 'آخر دفعة ${relativeDay(lastPay)}',
          ].join(' · '),
          style: TextStyle(color: late ? AppColors.warn : cs.onSurfaceVariant, fontWeight: late ? FontWeight.w700 : null),
        ),
        trailing: BalanceBadge(bal),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: s.id))),
      ),
    );
  }

  Widget _reorderList(Store store, List<Shop> all) {
    return Column(children: [
      const Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Text('اسحب البقالات لترتيبها حسب طريقك اليومي. هذا الترتيب يظهر في شاشة اليوم.'),
      ),
      Expanded(
        child: ReorderableListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
          itemCount: all.length,
          onReorder: (a, b) {
            final l = [...all];
            if (b > a) b--;
            l.insert(b, l.removeAt(a));
            store.reorderShops(l);
          },
          itemBuilder: (_, i) => Card(
            key: ValueKey(all[i].id),
            child: ListTile(
              leading: CircleAvatar(child: Text('${i + 1}')),
              title: Text(all[i].name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: all[i].area.isEmpty ? null : Text(all[i].area),
              trailing: const Icon(Icons.drag_handle),
            ),
          ),
        ),
      ),
    ]);
  }
}
