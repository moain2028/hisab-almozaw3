import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/store.dart';
import '../models/models.dart';
import '../ui/widgets.dart';

/// إضافة أو تعديل بقالة
Future<Shop?> openShopForm(BuildContext context, {Shop? shop}) {
  return Navigator.push<Shop>(context, MaterialPageRoute(builder: (_) => ShopFormScreen(shop: shop)));
}

class ShopFormScreen extends StatefulWidget {
  const ShopFormScreen({super.key, this.shop});
  final Shop? shop;
  @override
  State<ShopFormScreen> createState() => _ShopFormScreenState();
}

class _ShopFormScreenState extends State<ShopFormScreen> {
  late final name = TextEditingController(text: widget.shop?.name ?? '');
  late final owner = TextEditingController(text: widget.shop?.owner ?? '');
  late final phone = TextEditingController(text: widget.shop?.phone ?? '');
  late final area = TextEditingController(text: widget.shop?.area ?? '');
  late final notes = TextEditingController(text: widget.shop?.notes ?? '');
  late final opening = TextEditingController(
    text: (widget.shop?.openingBalance ?? 0) == 0 ? '' : '${widget.shop!.openingBalance}',
  );

  @override
  void dispose() {
    for (final c in [name, owner, phone, area, notes, opening]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final n = name.text.trim();
    if (n.isEmpty) {
      toast(context, 'اكتب اسم البقالة');
      return;
    }
    final store = context.read<Store>();
    final ob = parseMoney(opening.text) ?? 0;
    Shop saved;
    if (widget.shop == null) {
      saved = await store.addShop(
        name: n,
        owner: owner.text.trim(),
        phone: normalizeDigits(phone.text),
        area: area.text.trim(),
        openingBalance: ob,
      );
      saved.notes = notes.text.trim();
      await store.saveShop(saved);
    } else {
      saved = widget.shop!
        ..name = n
        ..owner = owner.text.trim()
        ..phone = normalizeDigits(phone.text)
        ..area = area.text.trim()
        ..notes = notes.text.trim()
        ..openingBalance = ob;
      await store.saveShop(saved);
    }
    if (mounted) Navigator.pop(context, saved);
  }

  @override
  Widget build(BuildContext context) {
    final areas = context.read<Store>().shops.map((s) => s.area).where((a) => a.isNotEmpty).toSet().toList();
    return Scaffold(
      appBar: AppBar(title: Text(widget.shop == null ? 'بقالة جديدة' : 'تعديل البقالة')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: name,
            autofocus: widget.shop == null,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            decoration: const InputDecoration(labelText: 'اسم البقالة *', prefixIcon: Icon(Icons.storefront)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: owner,
            decoration: const InputDecoration(labelText: 'اسم صاحب البقالة', prefixIcon: Icon(Icons.person_outline)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'رقم الجوال (للواتساب)',
              prefixIcon: Icon(Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: area,
            decoration: const InputDecoration(labelText: 'الحي / المنطقة', prefixIcon: Icon(Icons.place_outlined)),
          ),
          if (areas.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              children: [
                for (final a in areas) ActionChip(label: Text(a), onPressed: () => setState(() => area.text = a)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          NumberField(controller: opening, label: 'دين سابق عليه قبل البرنامج (اختياري)'),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 4, 4, 0),
            child: Text('لو عنده حساب قديم من قبل، اكتبه هنا مرة واحدة.', style: TextStyle(fontSize: 12.5)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'ملاحظات', prefixIcon: Icon(Icons.notes)),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _save,
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
            icon: const Icon(Icons.check),
            label: const Text('حفظ'),
          ),
        ),
      ),
    );
  }
}
