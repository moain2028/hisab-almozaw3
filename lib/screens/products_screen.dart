import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  Future<void> _edit(BuildContext context, [Product? p]) async {
    final store = context.read<Store>();
    final name = TextEditingController(text: p?.name ?? '');
    final unit = TextEditingController(text: p?.unit ?? 'كرتون');
    final sell = TextEditingController(text: p == null ? '' : '${p.sellPrice}');
    final cost = TextEditingController(text: p == null ? '' : '${p.costPrice}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p == null ? 'صنف جديد' : 'تعديل ${p.name}'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, autofocus: p == null, decoration: const InputDecoration(labelText: 'اسم الصنف (زبادي، حقين...)')),
            const SizedBox(height: 10),
            TextField(controller: unit, decoration: const InputDecoration(labelText: 'الوحدة (كرتون، طبق، حبة)')),
            const SizedBox(height: 10),
            NumberField(controller: sell, label: 'سعر البيع للبقالة'),
            const SizedBox(height: 10),
            NumberField(controller: cost, label: 'سعر الشراء من التاجر'),
            if (p != null) ...[
              const SizedBox(height: 10),
              const Text('تغيير السعر لا يغيّر الحسابات القديمة.', style: TextStyle(fontSize: 12.5)),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, name.text.trim().isNotEmpty), child: const Text('حفظ')),
        ],
      ),
    );
    if (ok != true) return;
    final u = unit.text.trim().isEmpty ? 'كرتون' : unit.text.trim();
    final s = parseMoney(sell.text) ?? 0;
    final c = parseMoney(cost.text) ?? 0;
    if (p == null) {
      await store.addProduct(name.text.trim(), u, s, c);
    } else {
      p
        ..name = name.text.trim()
        ..unit = u
        ..sellPrice = s
        ..costPrice = c
        ..active = true;
      await store.saveProduct(p);
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final list = store.products;
    final hidden = store.allProducts.where((p) => !p.active).toList();
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الأصناف والأسعار')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context),
        icon: const Icon(Icons.add),
        label: const Text('صنف جديد'),
      ),
      body: list.isEmpty && hidden.isEmpty
          ? Center(
              child: EmptyState(
                icon: Icons.inventory_2_outlined,
                text: 'أضف الأصناف التي توزعها وأسعارها',
                action: OutlinedButton.icon(
                  onPressed: store.addStarterProducts,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('إضافة زبادي وحقين ولبن وجبن كبداية'),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 96),
              children: [
                if (list.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                    child: Text('اسحب ⠿ لتغيير الترتيب في شاشة العطاء', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  ),
                ReorderableListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  onReorder: (a, b) {
                    final l = [...list];
                    if (b > a) b--;
                    l.insert(b, l.removeAt(a));
                    store.reorderProducts(l);
                  },
                  children: [
                    for (var i = 0; i < list.length; i++)
                      Card(
                        key: ValueKey(list[i].id),
                        child: ListTile(
                          onTap: () => _edit(context, list[i]),
                          leading: ReorderableDragStartListener(index: i, child: const Icon(Icons.drag_indicator)),
                          title: Text(list[i].name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
                          subtitle: Text(
                              'بيع ${money(list[i].sellPrice)} · شراء ${money(list[i].costPrice)} · ربح ${money(list[i].margin)} / ${list[i].unit}'),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (await confirm(context, 'حذف "${list[i].name}"؟\nالحسابات القديمة تبقى كما هي.')) {
                                await store.removeProduct(list[i]);
                              }
                            },
                          ),
                        ),
                      ),
                  ],
                ),
                if (hidden.isNotEmpty) ...[
                  const SectionTitle('أصناف مخفية'),
                  for (final p in hidden)
                    Card(
                      child: ListTile(
                        title: Text(p.name, style: TextStyle(color: cs.onSurfaceVariant)),
                        trailing: TextButton(
                          onPressed: () {
                            p.active = true;
                            store.saveProduct(p);
                          },
                          child: Text('إظهار', style: TextStyle(color: paidColor(context))),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}
