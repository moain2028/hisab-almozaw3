/// product_form.dart — شاشة "إضافة صنف جديد" / تعديل صنف (شاشة كاملة بدل نافذة صغيرة).
///
/// - حقل باركود بزر مسح بالكاميرا (اختياري).
/// - وحدات جاهزة بنقرة (كرتون، طبق، حبة، علبة، كيلو، لتر).
/// - معاينة الربح لكل وحدة لحظياً + تحذير لو سعر البيع أقل من الشراء.
/// - منع تكرار الباركود: لو الباركود مسجل لصنف آخر يُعرض اسمه ولا يُحفظ.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';
import 'scan_screen.dart';

const productUnits = ['كرتون', 'طبق', 'حبة', 'علبة', 'كيلو', 'لتر'];

/// يفتح شاشة الصنف. يُرجع الصنف المحفوظ أو null
Future<Product?> openProductForm(BuildContext context, {Product? product, String barcode = ''}) =>
    Navigator.push<Product>(
      context,
      MaterialPageRoute(
        builder: (_) => ProductFormScreen(product: product, barcode: barcode),
      ),
    );

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product, this.barcode = ''});
  final Product? product;
  final String barcode;
  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final name = TextEditingController(text: widget.product?.name ?? '');
  late final unit = TextEditingController(text: widget.product?.unit ?? 'كرتون');
  late final sell = TextEditingController(text: widget.product == null ? '' : '${widget.product!.sellPrice}');
  late final cost = TextEditingController(text: widget.product == null ? '' : '${widget.product!.costPrice}');
  late final code = TextEditingController(text: widget.product?.barcode ?? widget.barcode);
  String? _nameErr;
  String? _codeErr;
  bool _saving = false;

  bool get isEdit => widget.product != null;

  @override
  void dispose() {
    for (final c in [name, unit, sell, cost, code]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _scan() async {
    final v = await scanBarcode(context);
    if (v == null || !mounted) return;
    setState(() {
      code.text = v;
      _codeErr = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final store = context.read<Store>();
    final n = name.text.trim();
    final c = normalizeDigits(code.text).trim();
    setState(() {
      _nameErr = n.isEmpty ? 'اكتب اسم الصنف' : null;
      final other = store.productByBarcode(c);
      _codeErr = other != null && other.id != widget.product?.id ? 'هذا الباركود مسجل للصنف "${other.name}"' : null;
    });
    if (_nameErr != null || _codeErr != null) return;
    _saving = true;
    final u = unit.text.trim().isEmpty ? 'كرتون' : unit.text.trim();
    final s = parseMoney(sell.text) ?? 0;
    final k = parseMoney(cost.text) ?? 0;
    Product saved;
    if (widget.product == null) {
      saved = await store.addProduct(n, u, s, k, barcode: c);
    } else {
      saved = widget.product!
        ..name = n
        ..unit = u
        ..sellPrice = s
        ..costPrice = k
        ..barcode = c
        ..active = true;
      await store.saveProduct(saved);
    }
    if (!mounted) return;
    haptic(context, strong: true);
    Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final s = parseMoney(sell.text) ?? 0;
    final k = parseMoney(cost.text) ?? 0;
    final margin = s - k;
    final u = unit.text.trim().isEmpty ? 'وحدة' : unit.text.trim();

    return Scaffold(
      appBar: AppBar(title: Text(isEdit ? 'تعديل الصنف' : 'إضافة صنف جديد')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xl),
        children: [
          // ---------------- الهوية
          const _Label('اسم الصنف'),
          TextField(
            controller: name,
            autofocus: !isEdit && widget.barcode.isEmpty,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'زبادي، حقين، لبن...',
              errorText: _nameErr,
              prefixIcon: const Icon(Icons.inventory_2_outlined),
            ),
            onChanged: (_) => _nameErr == null ? null : setState(() => _nameErr = null),
          ),
          const SizedBox(height: Space.lg),
          const _Label('الباركود (اختياري)'),
          TextField(
            controller: code,
            keyboardType: TextInputType.number,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              hintText: 'امسحه بالكاميرا أو اكتبه',
              errorText: _codeErr,
              prefixIcon: const Icon(Icons.qr_code_2_rounded),
              suffixIcon: IconButton(
                tooltip: 'مسح بالكاميرا',
                onPressed: _scan,
                icon: Icon(Icons.qr_code_scanner_rounded, color: cs.primary),
              ),
            ),
            onChanged: (_) => _codeErr == null ? null : setState(() => _codeErr = null),
          ),
          const SizedBox(height: Space.lg),

          // ---------------- الوحدة
          const _Label('الوحدة'),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              for (final x in productUnits)
                ChoiceChip(
                  label: Text(x),
                  selected: unit.text.trim() == x,
                  onSelected: (_) => setState(() => unit.text = x),
                ),
            ],
          ),
          const SizedBox(height: Space.sm),
          TextField(
            controller: unit,
            decoration: const InputDecoration(hintText: 'أو اكتب وحدة أخرى'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: Space.lg),

          // ---------------- الأسعار
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label('سعر البيع للبقالة'),
                    NumberField(controller: sell, hint: '0', onChanged: (_) => setState(() {})),
                  ],
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Label('سعر الشراء من التاجر'),
                    NumberField(controller: cost, hint: '0', onChanged: (_) => setState(() {})),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(Space.md),
            decoration: BoxDecoration(
              color: (margin < 0 ? debtColor(context) : paidColor(context)).withValues(alpha: .08),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              children: [
                Icon(
                  margin < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                  color: margin < 0 ? debtColor(context) : paidColor(context),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    margin < 0 ? 'سعر البيع أقل من الشراء! خسارة لكل $u' : 'ربحك في كل $u',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                MoneyText(margin, size: 18, color: margin < 0 ? debtColor(context) : paidColor(context)),
              ],
            ),
          ),
          if (isEdit) ...[
            const SizedBox(height: Space.md),
            Text(
              'تغيير السعر لا يغيّر الحسابات القديمة، فقط العمليات الجديدة.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
            ),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.md),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            onPressed: _save,
            icon: const Icon(Icons.check_rounded),
            label: Text(isEdit ? 'حفظ التعديل' : 'حفظ الصنف'),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(start: Space.xs, bottom: Space.sm),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
  );
}
