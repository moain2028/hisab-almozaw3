import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'products_screen.dart';

enum LinesMode { delivery, shopReturn, pickup, traderReturn }

extension on LinesMode {
  String get title => switch (this) {
        LinesMode.delivery => 'عطاء',
        LinesMode.shopReturn => 'مرتجع من البقالة',
        LinesMode.pickup => 'استلام من التاجر',
        LinesMode.traderReturn => 'إرجاع للتاجر',
      };

  /// عمليات التاجر تُسعَّر بسعر الشراء
  bool get usesCost => this == LinesMode.pickup || this == LinesMode.traderReturn;
  bool get isReturn => this == LinesMode.shopReturn || this == LinesMode.traderReturn;
}

/// شاشة إدخال الكميات بالأزرار السريعة (+¼ +½ +1). تُستخدم لأربع عمليات.
class LinesEditorScreen extends StatefulWidget {
  const LinesEditorScreen({
    super.key,
    required this.mode,
    required this.day,
    this.shop,
    this.trader,
    this.existingShopTx,
    this.existingTraderTx,
    this.prefill,
  });

  final LinesMode mode;
  final String day;
  final Shop? shop;
  final Trader? trader;
  final ShopTx? existingShopTx;
  final TraderTx? existingTraderTx;

  /// كميات مقترحة (مثلاً: استلام الصباح = مجموع عطاء أمس)
  final Map<String, double>? prefill;

  @override
  State<LinesEditorScreen> createState() => _LinesEditorScreenState();
}

class _LinesEditorScreenState extends State<LinesEditorScreen> {
  final qty = <String, double>{};
  final price = <String, int>{};
  final undo = <String, List<double>>{};
  final noteCtl = TextEditingController();
  late List<Product> items;

  @override
  void initState() {
    super.initState();
    final store = context.read<Store>();
    items = store.products;
    final existingLines = widget.existingShopTx?.lines ?? widget.existingTraderTx?.lines ?? const <TxLine>[];
    noteCtl.text = widget.existingShopTx?.note ?? widget.existingTraderTx?.note ?? '';
    // أصناف مخفية لكنها موجودة في العملية القديمة
    for (final l in existingLines) {
      if (!items.any((p) => p.id == l.productId)) {
        final p = store.product(l.productId);
        items.add(p ??
            Product(id: l.productId, name: l.name, unit: l.unit, sellPrice: l.price, costPrice: l.cost, active: false));
      }
    }
    for (final p in items) {
      price[p.id] = widget.mode.usesCost ? p.costPrice : p.sellPrice;
      qty[p.id] = widget.prefill?[p.id] ?? 0;
    }
    for (final l in existingLines) {
      qty[l.productId] = l.qty;
      price[l.productId] = l.price;
    }
  }

  @override
  void dispose() {
    noteCtl.dispose();
    super.dispose();
  }

  void _add(String id, double step) => setState(() {
        qty[id] = roundQty((qty[id] ?? 0) + step);
        (undo[id] ??= []).add(step);
      });

  void _minus(String id) => setState(() {
        final st = undo[id] ?? [];
        final step = st.isNotEmpty ? st.removeLast() : 1.0;
        final v = roundQty((qty[id] ?? 0) - step);
        qty[id] = v < 0 ? 0 : v;
      });

  int get total {
    var t = 0;
    for (final p in items) {
      t += ((qty[p.id] ?? 0) * (price[p.id] ?? 0)).round();
    }
    return t;
  }

  int get count => items.where((p) => (qty[p.id] ?? 0) > 0).length;

  List<TxLine> _lines() => [
        for (final p in items)
          if ((qty[p.id] ?? 0) > 0)
            TxLine(
              productId: p.id,
              name: p.name,
              unit: p.unit,
              qty: qty[p.id]!,
              price: price[p.id] ?? 0,
              cost: widget.mode.usesCost ? (price[p.id] ?? 0) : p.costPrice,
            ),
      ];

  Future<void> _save() async {
    final store = context.read<Store>();
    final lines = _lines();
    final exShop = widget.existingShopTx;
    final exTrader = widget.existingTraderTx;
    if (lines.isEmpty) {
      if (exShop != null) await store.deleteShopTx(exShop.id);
      if (exTrader != null) await store.deleteTraderTx(exTrader.id);
      if (mounted) Navigator.pop(context, true);
      return;
    }
    final note = noteCtl.text.trim();
    switch (widget.mode) {
      case LinesMode.delivery:
      case LinesMode.shopReturn:
        await store.saveShopTx(ShopTx(
          id: exShop?.id ?? newId(),
          shopId: widget.shop!.id,
          type: widget.mode == LinesMode.delivery ? ShopTxType.delivery : ShopTxType.returned,
          day: exShop?.day ?? widget.day,
          createdAt: exShop?.createdAt ?? nowMs(),
          lines: lines,
          note: note,
        ));
      case LinesMode.pickup:
      case LinesMode.traderReturn:
        await store.saveTraderTx(TraderTx(
          id: exTrader?.id ?? newId(),
          traderId: widget.trader!.id,
          type: widget.mode == LinesMode.pickup ? TraderTxType.pickup : TraderTxType.returned,
          day: exTrader?.day ?? widget.day,
          createdAt: exTrader?.createdAt ?? nowMs(),
          lines: lines,
          note: note,
        ));
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _editPrice(Product p) async {
    final v = await askMoney(context, 'سعر ${p.name} في هذه العملية فقط', initial: price[p.id]);
    if (v != null && v >= 0) setState(() => price[p.id] = v);
  }

  Future<void> _typeQty(Product p) async {
    final v = await askQty(context, 'كمية ${p.name} (${p.unit})', initial: qty[p.id]);
    if (v != null && v >= 0) {
      setState(() {
        qty[p.id] = roundQty(v);
        undo[p.id] = [];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final who = widget.shop?.name ?? widget.trader?.name ?? '';
    final accent = widget.mode.isReturn ? AppColors.warn : cs.primary;
    final isEdit = widget.existingShopTx != null || widget.existingTraderTx != null;

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isEdit ? 'تعديل ${widget.mode.title}' : widget.mode.title),
          Text('$who · ${relativeDay(widget.day)}',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        ]),
        actions: [
          if (isEdit)
            IconButton(
              tooltip: 'حذف العملية',
              icon: Icon(Icons.delete_outline, color: debtColor(context)),
              onPressed: () async {
                if (!await confirm(context, 'حذف هذه العملية نهائياً؟')) return;
                if (!context.mounted) return;
                final store = context.read<Store>();
                if (widget.existingShopTx != null) await store.deleteShopTx(widget.existingShopTx!.id);
                if (widget.existingTraderTx != null) await store.deleteTraderTx(widget.existingTraderTx!.id);
                if (context.mounted) Navigator.pop(context, true);
              },
            ),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: EmptyState(
                icon: Icons.inventory_2_outlined,
                text: 'لا توجد أصناف بعد.\nأضف الأصناف (زبادي، حقين...) وأسعارها أولاً.',
                action: FilledButton.icon(
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductsScreen()));
                    if (!context.mounted) return;
                    setState(() {
                      items = context.read<Store>().products;
                      for (final p in items) {
                        price[p.id] ??= widget.mode.usesCost ? p.costPrice : p.sellPrice;
                        qty[p.id] ??= 0;
                      }
                    });
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('إضافة الأصناف'),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              children: [
                if (widget.mode.isReturn)
                  Card(
                    color: AppColors.warn.withValues(alpha: 0.1),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('المرتجع يُخصم من الحساب (بضاعة تالفة أو منتهية أو زائدة).',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                if (widget.prefill != null && !isEdit)
                  Card(
                    color: cs.primaryContainer.withValues(alpha: 0.5),
                    child: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('تم تعبئة الكميات من آخر استلام. عدّلها حسب ما أخذت اليوم.',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                for (final p in items) _itemCard(p, accent),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtl,
                  decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)', prefixIcon: Icon(Icons.notes)),
                ),
              ],
            ),
      bottomNavigationBar: items.isEmpty
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardTheme.color,
                  border: Border(top: BorderSide(color: cs.outlineVariant)),
                ),
                child: Row(children: [
                  Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('المجموع · $count صنف', style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                    MoneyText(total, size: 24, color: accent, showCurrency: true),
                  ]),
                  const SizedBox(width: 14),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54), backgroundColor: accent),
                      icon: const Icon(Icons.check),
                      label: Text(isEdit ? 'حفظ التعديل' : 'حفظ'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }

  Widget _itemCard(Product p, Color accent) {
    final cs = Theme.of(context).colorScheme;
    final q = qty[p.id] ?? 0;
    final pr = price[p.id] ?? 0;
    final active = q > 0;
    final defPrice = widget.mode.usesCost ? p.costPrice : p.sellPrice;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: active ? accent : cs.outlineVariant.withValues(alpha: 0.6), width: active ? 2 : 1),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(children: [
          Row(children: [
            Expanded(
              child: Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            ),
            if (active) MoneyText((q * pr).round(), size: 17, color: accent),
          ]),
          InkWell(
            onTap: () => _editPrice(p),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Text('السعر ${money(pr)} / ${p.unit}',
                    style: TextStyle(
                        color: pr != defPrice ? AppColors.warn : cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
                const SizedBox(width: 4),
                Icon(Icons.edit, size: 14, color: cs.onSurfaceVariant),
                if (pr != defPrice)
                  const Text('  (سعر خاص)', style: TextStyle(fontSize: 12, color: AppColors.warn)),
              ]),
            ),
          ),
          const SizedBox(height: 4),
          Row(children: [
            IconButton.outlined(
              onPressed: active ? () => _minus(p.id) : null,
              icon: const Icon(Icons.remove),
              style: IconButton.styleFrom(minimumSize: const Size(46, 46)),
            ),
            Expanded(
              child: InkWell(
                onTap: () => _typeQty(p),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  height: 46,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: active ? accent.withValues(alpha: 0.1) : cs.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('${qtyText(q)} ${p.unit}',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: active ? accent : null)),
                  ),
                ),
              ),
            ),
            _step(p.id, 0.25, '¼', accent),
            const SizedBox(width: 4),
            _step(p.id, 0.5, '½', accent),
            const SizedBox(width: 4),
            _step(p.id, 1, '1', accent),
          ]),
        ]),
      ),
    );
  }

  Widget _step(String id, double step, String label, Color accent) => SizedBox(
        width: 48,
        height: 46,
        child: FilledButton.tonal(
          onPressed: () => _add(id, step),
          style: FilledButton.styleFrom(padding: EdgeInsets.zero),
          child: Text('+$label', textDirection: TextDirection.ltr, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
      );
}
