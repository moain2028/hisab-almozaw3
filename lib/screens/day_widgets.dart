/// day_widgets.dart — مكونات يوم العمل المشتركة بين الرئيسية وسجل اليوم.
library;

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

// ------------------------------------------------------------------ بطاقة الملخص

class HeroCard extends StatelessWidget {
  const HeroCard({super.key, required this.summary, required this.shopsCount});
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
      padding: const EdgeInsets.all(16), // 16 + حدّ ذهبي 1px (الرئيسية بلا تمرير على 360×740)
      decoration: BoxDecoration(
        gradient: heroGradient(cs),
        borderRadius: BorderRadius.circular(Radii.lg),
        // حدّ ذهبي رفيع + ظل بنفسجي (--glow في المرجع)
        border: Border.all(color: AppColors.goldDeep.withValues(alpha: .45)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: .35),
            blurRadius: 30,
            offset: const Offset(0, 12),
            spreadRadius: -12,
          ),
        ],
      ),
      // merge وليس DefaultTextStyle(...): الأخير يستبدل النمط كاملاً فيضيع خط التطبيق
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: kOnHero, fontSize: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الباقي عند البقالات',
              style: TextStyle(color: kOnHeroGold, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: MoneyText(s.remainingEndOfDay, size: 36, color: kOnHero, showCurrency: true),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress.toDouble(),
                minHeight: 7,
                backgroundColor: kOnHero.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation(AppColors.goldMid),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _mini(context, 'العطاء', netDelivered, Icons.arrow_upward),
                _mini(context, 'المحصّل', s.collected, Icons.arrow_downward),
                _mini(
                  context,
                  'في جيبك',
                  s.collected - s.traderPaid - s.expenses,
                  Icons.account_balance_wallet_outlined,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _mini(BuildContext c, String label, int v, IconData icon) {
    const on = kOnHero;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: kOnHeroGold),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: kOnHeroGold),
                ),
              ),
            ],
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: MoneyText(v, size: 17, color: on),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ البضاعة في السيارة

/// صف مختصر في الرئيسية: «في السيارة: زبادي 2 · لبن 1…» → يفتح صفحة الجدول الكامل.
/// (كان ExpansionTile يتمدد داخل الرئيسية فيجعلها تتمرّر كصفحة ويب.)
class StockCard extends StatelessWidget {
  const StockCard({super.key, required this.rows});
  final List<StockRow> rows;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (rows.isEmpty) return const SizedBox.shrink();
    final short = rows.any((r) => r.onHand < 0);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => StockScreen(rows: rows))),
        leading: Icon(
          short ? Icons.warning_amber_rounded : Icons.inventory_outlined,
          color: short ? debtColor(context) : cs.tertiary,
        ),
        title: const Text('البضاعة في السيارة', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        subtitle: Text(
          rows.map((r) => '${r.name} ${qtyText(r.onHand)}').join(' · '),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: const Icon(Icons.chevron_left_rounded),
      ),
    );
  }
}

class StockScreen extends StatelessWidget {
  const StockScreen({super.key, required this.rows});
  final List<StockRow> rows;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget cell(String t, {bool head = false, bool bold = false, Color? color}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.md, horizontal: Space.xs),
      child: Text(
        t,
        style: TextStyle(
          fontWeight: head || bold ? FontWeight.w700 : FontWeight.w400,
          fontSize: head ? 13 : 15,
          color: head ? cs.onSurfaceVariant : color,
          fontFeatures: tabular,
        ),
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('البضاعة في السيارة')),
      body: ListView(
        padding: const EdgeInsets.all(Space.md),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
              child: Table(
                columnWidths: const {0: FlexColumnWidth(1.6)},
                border: TableBorder(horizontalInside: BorderSide(color: cs.outlineVariant.withValues(alpha: .6))),
                children: [
                  TableRow(
                    children: [
                      for (final t in ['الصنف', 'استلمت', 'وزّعت', 'الباقي']) cell(t, head: true),
                    ],
                  ),
                  for (final r in rows)
                    TableRow(
                      children: [
                        cell(r.name, bold: true),
                        cell(qtyText(r.picked - r.traderReturns)),
                        cell(qtyText(r.delivered - r.shopReturns)),
                        cell(
                          qtyText(r.onHand),
                          bold: true,
                          color: r.onHand < 0
                              ? debtColor(context)
                              : (r.onHand > 0 ? warnColor(context) : paidColor(context)),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (rows.any((r) => r.onHand < 0))
            Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Text(
                'تنبيه: وزّعت أكثر مما استلمت في بعض الأصناف. راجع الاستلام.',
                style: TextStyle(color: debtColor(context), fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ بطاقات البقالات

class DeliverTile extends StatelessWidget {
  const DeliverTile({super.key, required this.shop, required this.day});
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
        onLongPress: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: shop.id))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              ShopAvatar(shop.name, active: done, done: done),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shop.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5)),
                    const SizedBox(height: 2),
                    Text(
                      done
                          ? summary.join(' · ')
                          : (day.before > 0 ? 'عليه من قبل ${money(day.before)}' : 'لم يُعطَ بعد'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5),
                    ),
                  ],
                ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class CollectTile extends StatelessWidget {
  const CollectTile({super.key, required this.shop, required this.day});
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
        onLongPress: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => ShopDetailScreen(shopId: shop.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ShopAvatar(shop.name, active: day.hasDelivery, done: paid),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(shop.name, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5)),
                    const SizedBox(height: 2),
                    Text(
                      lines.isEmpty ? 'لا شيء' : lines.join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13.5),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(paid ? 'الباقي' : 'المطلوب', style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
                  BalanceBadge(rem),
                ],
              ),
            ],
          ),
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final c in expenseCategories)
                  ChoiceChip(label: Text(c), selected: cat == c, onSelected: (_) => setState(() => cat = c)),
              ],
            ),
            const SizedBox(height: 12),
            NumberField(controller: amount, autofocus: true, big: true, hint: 'المبلغ'),
            const SizedBox(height: 10),
            TextField(
              controller: note,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
          ],
        ),
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
