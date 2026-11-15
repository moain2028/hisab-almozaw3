/// day_log_screen.dart — سجل اليوم: كل البقالات للعطاء أو التحصيل.
///
/// منفصل عن الرئيسية حتى تبقى الرئيسية ثابتة ومختصرة.
/// الرأس (اليوم + عطاء/تحصيل + بحث) **مثبّت** — لا يختفي عند النزول.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../ui/pinned.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'day_widgets.dart';
import 'shop_form.dart';

enum DayMode { deliver, collect }

Future<void> openDayLog(BuildContext context, DayMode mode) =>
    Navigator.push(context, MaterialPageRoute(builder: (_) => DayLogScreen(initial: mode)));

class DayLogScreen extends StatefulWidget {
  const DayLogScreen({super.key, this.initial = DayMode.deliver});
  final DayMode initial;
  @override
  State<DayLogScreen> createState() => _DayLogScreenState();
}

class _DayLogScreenState extends State<DayLogScreen> {
  late DayMode mode = widget.initial;
  String q = '';
  bool pendingOnly = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final cs = Theme.of(context).colorScheme;
    final s = store.summary();
    final all = store.shops;
    final collect = mode == DayMode.collect;
    var list = all.where((x) => q.isEmpty || x.name.contains(q) || x.area.contains(q)).toList();
    if (pendingOnly) {
      list = list.where((x) {
        final d = store.dayOf(x);
        return collect ? (!d.hasPayment && d.remaining > 0) : !d.hasDelivery;
      }).toList();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('سجل اليوم')),
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'addShop',
        tooltip: 'إضافة بقالة',
        onPressed: () => openShopForm(context),
        child: const Icon(Icons.add_business_rounded),
      ),
      body: CustomScrollView(
        slivers: [
          PinnedHeader(
            height: 184,
            child: Column(
              children: [
                const DayBar(),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.md),
                  child: SegmentedButton<DayMode>(
                    style: SegmentedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    segments: [
                      ButtonSegment(
                        value: DayMode.deliver,
                        icon: const Icon(Icons.wb_sunny_outlined),
                        label: Text('العطاء ${s.deliveredShops.length}/${all.length}'),
                      ),
                      ButtonSegment(
                        value: DayMode.collect,
                        icon: const Icon(Icons.nightlight_outlined),
                        label: Text('التحصيل ${s.paidShops.length}/${all.length}'),
                      ),
                    ],
                    selected: {mode},
                    onSelectionChanged: (v) => setState(() => mode = v.first),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.md, Space.sm),
                  child: Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: TextField(
                            onChanged: (v) => setState(() => q = v.trim()),
                            decoration: const InputDecoration(
                              isDense: true,
                              prefixIcon: Icon(Icons.search_rounded),
                              hintText: 'ابحث عن بقالة',
                              contentPadding: EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      FilterChip(
                        label: Text(collect ? 'لم يدفع' : 'لم يُعطَ'),
                        selected: pendingOnly,
                        onSelected: (v) => setState(() => pendingOnly = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (all.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.storefront_outlined,
                text: 'ابدأ بإضافة البقالات التي توزع عليها',
                action: FilledButton.icon(
                  onPressed: () => openShopForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة بقالة'),
                ),
              ),
            )
          else if (list.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(Space.xl),
                child: Center(
                  child: Text(
                    pendingOnly ? 'تم الانتهاء من كل البقالات 👍' : 'لا نتائج',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.md, Space.xs, Space.md, 88),
            sliver: SliverList.builder(
              itemCount: list.length,
              itemBuilder: (_, i) {
                final shop = list[i];
                return RepaintBoundary(
                  child: collect
                      ? CollectTile(key: ValueKey('c${shop.id}'), shop: shop, day: store.dayOf(shop))
                      : DeliverTile(key: ValueKey('d${shop.id}'), shop: shop, day: store.dayOf(shop)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
