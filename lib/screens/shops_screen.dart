import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../ui/pinned.dart';
import '../ui/shell.dart';
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
    final lastPay = {for (final s in all) s.id: store.lastPaymentOf(s)};
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
        leading: const MenuButton(),
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
          const SettingsButton(),
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
                action: FilledButton.icon(
                  onPressed: () => openShopForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة بقالة'),
                ),
              ),
            )
          : reorder
          ? _reorderList(store, all)
          : CustomScrollView(
              slivers: [
                // الرأس المثبّت: المجموع + البحث + الترتيب — لا يختفي عند النزول
                PinnedHeader(
                  height: 166,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.md),
                    child: Column(
                      children: [
                        Container(
                          height: 52,
                          padding: const EdgeInsets.symmetric(horizontal: Space.md),
                          decoration: BoxDecoration(
                            color: debtColor(context).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(Radii.md),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.account_balance_wallet_outlined, color: debtColor(context), size: 20),
                              const SizedBox(width: Space.sm),
                              Expanded(
                                child: Text(
                                  'الباقي عند $debtors من ${all.length}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                                ),
                              ),
                              MoneyText(total, size: 20, color: debtColor(context), showCurrency: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                        SizedBox(
                          height: 48,
                          child: TextField(
                            onChanged: (v) => setState(() => q = v.trim()),
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.search_rounded),
                              hintText: 'ابحث بالاسم أو الحي',
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(height: Space.xs),
                        SizedBox(
                          height: 48,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final e in {
                                _Sort.route: 'خط السير',
                                _Sort.debt: 'الأكثر ديناً',
                                _Sort.late: 'المتأخرين',
                                _Sort.name: 'أبجدي',
                              }.entries)
                                Padding(
                                  padding: const EdgeInsetsDirectional.only(end: Space.sm),
                                  child: ChoiceChip(
                                    label: Text(e.value),
                                    selected: sort == e.key,
                                    onSelected: (_) => setState(() => sort = e.key),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // تُبنى فقط البطاقات الظاهرة على الشاشة
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  sliver: SliverList.builder(
                    itemCount: list.length,
                    itemBuilder: (_, i) => RepaintBoundary(
                      child: _tile(
                        context,
                        list[i],
                        balances[list[i].id]!,
                        lastPay[list[i].id],
                        daysSince(lastPay[list[i].id]),
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
                  sliver: SliverList.list(
                    children: [
                      if (store.archivedShops.isNotEmpty) ...[
                        const SectionTitle('بقالات موقوفة'),
                        for (final s in store.archivedShops)
                          Card(
                            child: ListTile(
                              title: Text(s.name, style: TextStyle(color: cs.onSurfaceVariant)),
                              trailing: BalanceBadge(store.balanceOf(s), size: 14),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: s.id)),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
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
        title: Text(s.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5)),
        subtitle: Text(
          [
            if (s.area.isNotEmpty) s.area,
            lastPay == null ? 'لم يدفع بعد' : 'آخر دفعة ${relativeDay(lastPay)}',
          ].join(' · '),
          style: TextStyle(
            color: late ? AppColors.warn : cs.onSurfaceVariant,
            fontWeight: late ? FontWeight.w700 : null,
          ),
        ),
        trailing: BalanceBadge(bal),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: s.id))),
      ),
    );
  }

  Widget _reorderList(Store store, List<Shop> all) {
    return Column(
      children: [
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
      ],
    );
  }
}
