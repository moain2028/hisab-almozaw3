import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/ledger.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// نافذة التحصيل الليلي: تعرض للموزع بوضوح
/// السابق + عطاء اليوم − المرتجع = المطلوب ، ثم يكتب المبلغ فيظهر الباقي.
Future<void> showCollectSheet(BuildContext context, Shop shop, {String? day, ShopTx? edit}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => ChangeNotifierProvider.value(
      value: context.read<Store>(),
      child: _CollectSheet(shop: shop, day: day ?? context.read<Store>().day, edit: edit),
    ),
  );
}

class _CollectSheet extends StatefulWidget {
  const _CollectSheet({required this.shop, required this.day, this.edit});
  final Shop shop;
  final String day;
  final ShopTx? edit;
  @override
  State<_CollectSheet> createState() => _CollectSheetState();
}

class _CollectSheetState extends State<_CollectSheet> {
  late final TextEditingController ctl;
  final noteCtl = TextEditingController();
  bool discount = false;

  @override
  void initState() {
    super.initState();
    ctl = TextEditingController(text: widget.edit == null ? '' : '${widget.edit!.amount}');
    noteCtl.text = widget.edit?.note ?? '';
    discount = widget.edit?.type == ShopTxType.discount;
  }

  @override
  void dispose() {
    ctl.dispose();
    noteCtl.dispose();
    super.dispose();
  }

  int get amount => parseMoney(ctl.text) ?? 0;

  void _set(int v) => setState(() => ctl.text = '$v');

  Future<void> _save() async {
    final store = context.read<Store>();
    if (amount <= 0) return;
    await store.saveShopTx(
      ShopTx(
        id: widget.edit?.id ?? newId(),
        shopId: widget.shop.id,
        type: discount ? ShopTxType.discount : ShopTxType.payment,
        day: widget.edit?.day ?? widget.day,
        createdAt: widget.edit?.createdAt ?? nowMs(),
        amount: amount,
        note: noteCtl.text.trim(),
      ),
    );
    if (!mounted) return;
    haptic(context, strong: true);
    Navigator.pop(context);
    toast(context, discount ? 'تم تسجيل الخصم' : 'تم تسجيل التحصيل ${money(amount)}');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final cs = Theme.of(context).colorScheme;
    // نحسب بدون العملية التي نعدّلها
    // نحسب من الفهرس، ونطرح أثر العملية التي نعدّلها (إن وُجدت)
    final d0 = store.dayOf(widget.shop, widget.day);
    final e = widget.edit;
    final d = e == null
        ? d0
        : ShopDay(
            before: d0.before,
            delivered: d0.delivered,
            returned: d0.returned,
            paid: d0.paid - (e.type == ShopTxType.payment ? e.amount : 0),
            discount: d0.discount - (e.type == ShopTxType.discount ? e.amount : 0),
          );
    final dueNow = d.remaining; // المطلوب قبل هذه الدفعة
    final after = dueNow - amount;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.edit == null ? 'تحصيل من ${widget.shop.name}' : 'تعديل ${widget.edit!.type.label}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
            Text(relativeDay(widget.day), style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  KvRow('الباقي من قبل', d.before, color: d.before > 0 ? debtColor(context) : null),
                  KvRow('عطاء ${relativeDay(widget.day)}', d.delivered, prefix: d.delivered > 0 ? '+ ' : ''),
                  if (d.returned > 0) KvRow('مرتجع', d.returned, prefix: '− ', color: warnColor(context)),
                  if (d.discount > 0) KvRow('خصم', d.discount, prefix: '− '),
                  if (d.paid > 0) KvRow('محصّل سابقاً اليوم', d.paid, prefix: '− ', color: paidColor(context)),
                  const Divider(height: 18),
                  KvRow(
                    dueNow >= 0 ? 'المطلوب الآن' : 'له رصيد',
                    dueNow.abs(),
                    bold: true,
                    color: balanceColor(context, dueNow),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('تحصيل نقدي'), icon: Icon(Icons.payments_outlined)),
                ButtonSegment(value: true, label: Text('خصم / مسامحة'), icon: Icon(Icons.discount_outlined)),
              ],
              selected: {discount},
              onSelectionChanged: (v) => setState(() => discount = v.first),
            ),
            const SizedBox(height: 12),
            NumberField(
              controller: ctl,
              autofocus: true,
              big: true,
              hint: '0',
              suffix: store.currency,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (dueNow > 0) ActionChip(label: Text('كامل المطلوب ${money(dueNow)}'), onPressed: () => _set(dueNow)),
                if (d.delivered > 0 && d.delivered != dueNow && d.delivered < dueNow)
                  ActionChip(label: Text('عطاء اليوم فقط ${money(d.delivered)}'), onPressed: () => _set(d.delivered)),
                if (dueNow > 1000)
                  ActionChip(
                    label: Text('النصف ${money((dueNow / 2 / 100).round() * 100)}'),
                    onPressed: () => _set((dueNow / 2 / 100).round() * 100),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: balanceColor(context, after).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: balanceColor(context, after).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Icon(
                    after > 0 ? Icons.hourglass_bottom : (after < 0 ? Icons.savings_outlined : Icons.check_circle),
                    color: balanceColor(context, after),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      after > 0 ? 'يبقى عليه' : (after < 0 ? 'يصير له رصيد' : 'مسدّد بالكامل'),
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: balanceColor(context, after)),
                    ),
                  ),
                  if (after != 0)
                    MoneyText(after.abs(), size: 22, color: balanceColor(context, after), showCurrency: true),
                ],
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: noteCtl,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                if (widget.edit != null) ...[
                  IconButton.outlined(
                    onPressed: () async {
                      if (!await confirm(context, 'حذف هذه العملية؟')) return;
                      if (!context.mounted) return;
                      final store = context.read<Store>();
                      final old = await store.deleteShopTx(widget.edit!.id);
                      if (!context.mounted) return;
                      Navigator.pop(context);
                      if (old != null) undoToast(context, 'حُذفت العملية', () => store.saveShopTx(old));
                    },
                    icon: Icon(Icons.delete_outline, color: debtColor(context)),
                    style: IconButton.styleFrom(minimumSize: const Size(54, 54)),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: FilledButton.icon(
                    onPressed: amount > 0 ? _save : null,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
                    icon: const Icon(Icons.check),
                    label: Text(discount ? 'تسجيل الخصم' : 'تسجيل التحصيل'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
