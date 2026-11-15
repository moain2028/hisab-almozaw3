/// expenses_screen.dart — كل المصاريف مجمّعة حسب اليوم، مع إضافة وحذف (قابل للتراجع).
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'today_screen.dart' show ExpenseDialog;

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});
  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  /// عدد الأيام المعروضة: 7 / 30 / 90
  int days = 30;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final cs = Theme.of(context).colorScheme;
    final to = todayKey();
    final from = shiftDay(to, -(days - 1));
    final list = store.expensesOf(from: from, to: to).toList()
      ..sort((a, b) => b.day == a.day ? b.createdAt.compareTo(a.createdAt) : b.day.compareTo(a.day));
    final total = list.fold<int>(0, (s, e) => s + e.amount);
    final byCat = <String, int>{};
    for (final e in list) {
      byCat[e.category] = (byCat[e.category] ?? 0) + e.amount;
    }
    final cats = byCat.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    // تجميع حسب اليوم
    final groups = <String, List<Expense>>{};
    for (final e in list) {
      (groups[e.day] ??= []).add(e);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('المصاريف')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, store),
        icon: const Icon(Icons.add_rounded),
        label: const Text('مصروف جديد'),
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
            sliver: SliverList.list(
              children: [
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 7, label: Text('أسبوع')),
                    ButtonSegment(value: 30, label: Text('شهر')),
                    ButtonSegment(value: 90, label: Text('3 أشهر')),
                  ],
                  selected: {days},
                  onSelectionChanged: (v) => setState(() => days = v.first),
                ),
                const SizedBox(height: Space.md),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الإجمالي', style: TextStyle(color: cs.onSurfaceVariant)),
                        const SizedBox(height: Space.xs),
                        MoneyText(total, size: 26, color: AppColors.warn),
                        if (cats.isNotEmpty) ...[
                          const SizedBox(height: Space.md),
                          Wrap(
                            spacing: Space.sm,
                            runSpacing: Space.sm,
                            children: [
                              for (final c in cats)
                                Chip(visualDensity: VisualDensity.compact, label: Text('${c.key}: ${money(c.value)}')),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (list.isEmpty) const EmptyState(icon: Icons.receipt_long_outlined, text: 'لا مصاريف في هذه الفترة'),
              ],
            ),
          ),
          for (final g in groups.entries) ...[
            SliverToBoxAdapter(child: SectionTitle(relativeDay(g.key))),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              sliver: SliverList.builder(
                itemCount: g.value.length,
                itemBuilder: (_, i) {
                  final e = g.value[i];
                  return Card(
                    key: ValueKey(e.id),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.warn.withValues(alpha: .12),
                        child: const Icon(Icons.receipt_long_rounded, color: AppColors.warn),
                      ),
                      title: Text(e.category, style: const TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: e.note.isEmpty ? null : Text(e.note, maxLines: 2, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          MoneyText(e.amount, size: 16),
                          IconButton(
                            tooltip: 'حذف',
                            icon: const Icon(Icons.delete_outline_rounded),
                            onPressed: () async {
                              final removed = await store.deleteExpense(e.id);
                              if (removed != null && context.mounted) {
                                undoToast(context, 'حُذف المصروف', () => store.saveExpense(removed));
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );
  }

  Future<void> _add(BuildContext context, Store store) async {
    final r = await showDialog<(int, String, String)>(context: context, builder: (_) => const ExpenseDialog());
    if (r != null) await store.addExpense(store.day, r.$1, r.$2, r.$3);
  }
}
