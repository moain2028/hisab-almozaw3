/// today_screen.dart — الرئيسية: ثابتة، مختصرة، بلا قوائم طويلة.
///
/// الهيكل (من الأعلى للأسفل، كل شيء يظهر بدون تمرير على 360×740):
///   1. شريط اليوم
///   2. البطاقة البطلة: الباقي عند البقالات + العطاء/المحصّل/في جيبك
///   3. إجراءات سريعة (شبكة 3×2): عطاء · تحصيل · استلام · مصروف · صنف جديد · بقالة جديدة
///   4. صف «سجل اليوم» (تقدّم العطاء/التحصيل) → يفتح القائمة الكاملة
///   5. البضاعة في السيارة (إن وُجد استلام)
/// القوائم الطويلة لها صفحاتها: سجل اليوم، البقالات، التاجر، التقارير.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';
import '../models/models.dart';
import '../ui/shell.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'day_log_screen.dart';
import 'day_widgets.dart';
import 'lines_editor.dart';
import 'product_form.dart';
import 'shop_form.dart';
import 'trader_screen.dart';

export 'day_widgets.dart' show ExpenseDialog;

class TodayScreen extends StatefulWidget {
  const TodayScreen({super.key});
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

class _TodayScreenState extends State<TodayScreen> {
  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final shops = store.shops;
    final s = store.summary();
    final cs = Theme.of(context).colorScheme;
    final night = DateTime.now().hour >= 15;

    return Scaffold(
      appBar: AppBar(
        leading: const MenuButton(),
        title: Text(store.distributorName.isEmpty ? 'حساب الموزع' : store.distributorName),
        actions: const [SettingsButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: Space.xl),
        children: [
          const DayBar(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: HeroCard(summary: s, shopsCount: shops.length),
          ),
          const SizedBox(height: Space.md),

          // ---------------- إجراءات سريعة
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: _QuickGrid(
              items: [
                _Quick(
                  Icons.wb_sunny_rounded,
                  'عطاء',
                  cs.primary,
                  () => openDayLog(context, DayMode.deliver),
                  highlight: !night,
                  badge: '${s.deliveredShops.length}/${shops.length}',
                ),
                _Quick(
                  Icons.payments_rounded,
                  'تحصيل',
                  paidColor(context),
                  () => openDayLog(context, DayMode.collect),
                  highlight: night,
                  badge: '${s.paidShops.length}/${shops.length}',
                ),
                _Quick(Icons.local_shipping_rounded, 'استلام', cs.tertiary, () => _pickup(context, store)),
                _Quick(Icons.receipt_long_rounded, 'مصروف', warnColor(context), () => _addExpense(context, store)),
                _Quick(Icons.add_box_rounded, 'صنف جديد', cs.secondary, () => openProductForm(context)),
                _Quick(Icons.add_business_rounded, 'بقالة جديدة', cs.secondary, () => openShopForm(context)),
              ],
            ),
          ),

          // ---------------- سجل اليوم (صف واحد: تقدّم العطاء والتحصيل) — لا قوائم في الرئيسية
          const SizedBox(height: Space.md),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: _DayLogRow(
              delivered: s.deliveredShops.length,
              paid: s.paidShops.length,
              total: shops.length,
              onTap: () => openDayLog(context, night ? DayMode.collect : DayMode.deliver),
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
          if (store.products.isNotEmpty && s.picked > 0) ...[
            const SizedBox(height: Space.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              child: StockCard(rows: store.stockOf()),
            ),
          ],
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
    final prev = store.lastPickupBefore(trader.id, store.day);
    final prefill = prev == null ? null : {for (final l in prev.lines) l.productId: l.qty};
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

class _Quick {
  const _Quick(this.icon, this.label, this.color, this.onTap, {this.highlight = false, this.badge});
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final bool highlight;

  /// عدّاد صغير في الزاوية (مثلاً 4/6 بقالات أُعطيت)
  final String? badge;
}

/// شبكة 3 أعمدة بارتفاع يتبع الخط — أهداف لمس كبيرة ومتساوية
class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.items});
  final List<_Quick> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    // الارتفاع يتبع حجم خط النظام (لا نسبة عرض/ارتفاع ثابتة → لا overflow عند ×1.25)
    final extent = 64 + MediaQuery.textScalerOf(context).scale(20);
    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: Space.sm,
        crossAxisSpacing: Space.sm,
        mainAxisExtent: extent,
      ),
      children: [
        for (final q in items)
          Material(
            color: q.highlight ? q.color.withValues(alpha: .16) : cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(Radii.lg),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                haptic(context);
                q.onTap();
              },
              child: Stack(
                children: [
                  if (q.badge != null)
                    PositionedDirectional(
                      top: Space.sm,
                      end: Space.sm,
                      child: Text(
                        q.badge!,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                          fontFeatures: tabular,
                        ),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(Space.sm),
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // مربع ممتلئ بلون الإجراء + أيقونة بيضاء/داكنة حسب السطوع (تباين ≥ 3:1 للأيقونات، WCAG 1.4.11)
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: q.color, borderRadius: BorderRadius.circular(Radii.md)),
                            child: Icon(
                              q.icon,
                              size: 22,
                              color: q.color.computeLuminance() > .4 ? const Color(0xFF10201E) : Colors.white,
                            ),
                          ),
                          const SizedBox(height: Space.xs),
                          Text(
                            q.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: cs.onSurface),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// صف «سجل اليوم»: يفتح القائمة الكاملة، ويعرض تقدّم العطاء والتحصيل بشريطين رفيعين.
class _DayLogRow extends StatelessWidget {
  const _DayLogRow({required this.delivered, required this.paid, required this.total, required this.onTap});
  final int delivered;
  final int paid;
  final int total;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget bar(String label, int done, Color c) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label $done/$total',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, fontFeatures: tabular),
          ),
          const SizedBox(height: Space.xs),
          ClipRRect(
            borderRadius: BorderRadius.circular(Radii.pill),
            child: LinearProgressIndicator(
              value: total == 0 ? 0 : done / total,
              minHeight: 6,
              color: c,
              backgroundColor: c.withValues(alpha: .15),
            ),
          ),
        ],
      ),
    );
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, Space.sm, Space.md),
          child: Row(
            children: [
              Icon(Icons.list_alt_rounded, color: cs.primary),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'فتح سجل اليوم',
                      style: TextStyle(fontWeight: FontWeight.w700, color: cs.primary),
                    ),
                    const SizedBox(height: Space.xs),
                    Row(
                      children: [
                        bar('العطاء', delivered, cs.primary),
                        const SizedBox(width: Space.md),
                        bar('التحصيل', paid, paidColor(context)),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left_rounded, color: cs.primary),
            ],
          ),
        ),
      ),
    );
  }
}
