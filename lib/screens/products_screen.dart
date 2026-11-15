/// products_screen.dart — الأصناف والأسعار.
///
/// أعلى الشاشة بطاقتا إجراء واضحتان: «إضافة صنف جديد» و«بالباركود».
/// المسح بالباركود: إن كان الصنف مسجلاً تُفتح بطاقته للتعديل، وإلا تُفتح شاشة إضافة بالباركود معبأ.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'product_form.dart';
import 'scan_screen.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});
  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  bool reorder = false;

  Future<void> _scan() async {
    final store = context.read<Store>();
    final code = await scanBarcode(context, title: 'مسح باركود الصنف');
    if (code == null || !mounted) return;
    final p = store.productByBarcode(code);
    if (p != null) {
      toast(context, 'الصنف "${p.name}" مسجل مسبقاً');
      await openProductForm(context, product: p);
    } else {
      final saved = await openProductForm(context, barcode: code);
      if (saved != null && mounted) toast(context, 'تمت إضافة "${saved.name}"');
    }
  }

  Future<void> _add() async {
    final saved = await openProductForm(context);
    if (saved != null && mounted) toast(context, 'تمت إضافة "${saved.name}"');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final list = store.products;
    final hidden = store.allProducts.where((p) => !p.active).toList();
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('الأصناف والأسعار'),
        actions: [
          if (list.length > 1)
            IconButton(
              tooltip: reorder ? 'تم' : 'ترتيب الأصناف',
              onPressed: () => setState(() => reorder = !reorder),
              icon: Icon(reorder ? Icons.check_rounded : Icons.swap_vert_rounded),
            ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.sm),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _ActionCard(
                      icon: Icons.add_box_rounded,
                      title: 'إضافة صنف جديد',
                      sub: 'بالاسم والسعر',
                      primary: true,
                      onTap: _add,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Expanded(
                    flex: 2,
                    child: _ActionCard(
                      icon: Icons.qr_code_scanner_rounded,
                      title: 'بالباركود',
                      sub: 'كاميرا الجوال',
                      onTap: _scan,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (list.isEmpty && hidden.isEmpty)
            SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.inventory_2_outlined,
                text: 'أضف الأصناف التي توزعها وأسعارها',
                action: OutlinedButton.icon(
                  onPressed: store.addStarterProducts,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text('إضافة زبادي وحقين ولبن وجبن كبداية'),
                ),
              ),
            ),
          if (list.isNotEmpty)
            SliverToBoxAdapter(
              child: SectionTitle(reorder ? 'اسحب ⠿ لتغيير الترتيب في شاشة العطاء' : 'الأصناف النشطة (${list.length})'),
            ),
          if (list.isNotEmpty)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              sliver: SliverReorderableList(
                itemCount: list.length,
                onReorder: (a, b) {
                  final l = [...list];
                  if (b > a) b--;
                  l.insert(b, l.removeAt(a));
                  store.reorderProducts(l);
                },
                itemBuilder: (_, i) => _ProductTile(key: ValueKey(list[i].id), p: list[i], index: i, reorder: reorder),
              ),
            ),
          if (hidden.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionTitle('أصناف مخفية')),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              sliver: SliverList.builder(
                itemCount: hidden.length,
                itemBuilder: (_, i) {
                  final p = hidden[i];
                  return Card(
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
                  );
                },
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: Space.xl)),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.sub,
    required this.onTap,
    this.primary = false,
  });
  final IconData icon;
  final String title;
  final String sub;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = primary ? cs.onPrimary : cs.primary;
    return Material(
      borderRadius: BorderRadius.circular(Radii.lg),
      clipBehavior: Clip.antiAlias,
      color: primary ? null : cs.primaryContainer.withValues(alpha: .55),
      child: Ink(
        decoration: primary ? BoxDecoration(gradient: heroGradient(cs)) : null,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 88),
            child: Padding(
              padding: const EdgeInsets.all(Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: fg, size: 28),
                  const SizedBox(height: Space.sm),
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 15.5),
                  ),
                  Text(
                    sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: fg.withValues(alpha: .8), fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({super.key, required this.p, required this.index, required this.reorder});
  final Product p;
  final int index;
  final bool reorder;

  @override
  Widget build(BuildContext context) {
    final store = context.read<Store>();
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: reorder ? null : () => openProductForm(context, product: p),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(Space.md, Space.md, Space.xs, Space.md),
          child: Row(
            children: [
              if (reorder)
                ReorderableDragStartListener(
                  index: index,
                  child: const SizedBox(width: 48, height: 48, child: Icon(Icons.drag_indicator_rounded)),
                )
              else
                CircleAvatar(
                  radius: 22,
                  backgroundColor: cs.primaryContainer,
                  child: Text(
                    p.name.characters.first,
                    style: TextStyle(color: cs.onPrimaryContainer, fontWeight: FontWeight.w700, fontSize: 18),
                  ),
                ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16.5),
                          ),
                        ),
                        if (p.barcode.isNotEmpty) ...[
                          const SizedBox(width: Space.xs),
                          Icon(Icons.qr_code_2_rounded, size: 16, color: cs.onSurfaceVariant),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'بيع ${money(p.sellPrice)} · شراء ${money(p.costPrice)} / ${p.unit}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Space.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('الربح', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11.5)),
                  MoneyText(p.margin, size: 15, color: p.margin < 0 ? debtColor(context) : paidColor(context)),
                ],
              ),
              if (!reorder)
                IconButton(
                  tooltip: 'حذف',
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () async {
                    if (await confirm(context, 'حذف "${p.name}"؟\nالحسابات القديمة تبقى كما هي.', ok: 'حذف')) {
                      await store.removeProduct(p);
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
