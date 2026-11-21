import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../data/store.dart';
import 'theme.dart';

void toast(BuildContext c, String msg, {SnackBarAction? action}) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(msg),
        action: action,
        duration: Duration(seconds: action == null ? 3 : 5),
      ),
    );
}

/// إشعار بعد الحذف مع زر "تراجع" — بدل نوافذ التأكيد المزعجة للأفعال القابلة للعكس
void undoToast(BuildContext c, String msg, Future<void> Function() undo) {
  toast(
    c,
    msg,
    action: SnackBarAction(label: 'تراجع', onPressed: () => undo()),
  );
}

/// شريط اختيار اليوم: ‹ اليوم ›
class DayBar extends StatelessWidget {
  const DayBar({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final day = store.day;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          IconButton.filledTonal(
            tooltip: 'اليوم السابق',
            onPressed: () => store.setDay(shiftDay(day, -1)),
            icon: const Icon(Icons.chevron_right),
          ),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: parseDay(day),
                  firstDate: DateTime(2022),
                  lastDate: DateTime.now(),
                );
                if (d != null) store.setDay(dayKey(d));
              },
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: store.isToday ? cs.primaryContainer : warnColor(context).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.calendar_month,
                      size: 18,
                      color: store.isToday ? cs.onPrimaryContainer : warnColor(context),
                    ),
                    const SizedBox(width: 8),
                    // Flexible + ellipsis: التاريخ الطويل أو الخط الكبير لا يتجاوز العرض أبداً
                    Flexible(
                      child: Text(
                        store.isToday ? 'اليوم · ${arDay(day)}' : arDay(day),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: store.isToday ? cs.onPrimaryContainer : warnColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton.filledTonal(
            tooltip: 'اليوم التالي',
            onPressed: store.isToday ? null : () => store.setDay(shiftDay(day, 1)),
            icon: const Icon(Icons.chevron_left),
          ),
          if (!store.isToday)
            IconButton(
              tooltip: 'الرجوع لليوم',
              onPressed: () => store.setDay(todayKey()),
              icon: const Icon(Icons.today),
            ),
        ],
      ),
    );
  }
}

/// رقم مبلغ مع العملة
class MoneyText extends StatelessWidget {
  const MoneyText(
    this.value, {
    super.key,
    this.size = 16,
    this.color,
    this.weight = FontWeight.w700,
    this.showCurrency = false,
    this.abs = false,
  });
  final int value;
  final double size;
  final Color? color;
  final FontWeight weight;
  final bool showCurrency;
  final bool abs;

  @override
  Widget build(BuildContext context) {
    final cur = context.select<Store, String>((s) => s.currency);
    final v = abs ? value.abs() : value;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '\u2066${money(v)}\u2069',
            style: TextStyle(fontSize: size, fontWeight: weight, color: color, fontFeatures: tabular, height: 1.15),
          ),
          if (showCurrency)
            TextSpan(
              text: ' $cur',
              style: TextStyle(fontSize: size * 0.55, fontWeight: FontWeight.w600, color: color),
            ),
        ],
      ),
      textDirection: TextDirection.rtl,
    );
  }
}

/// شارة الرصيد: المبلغ + (عليه / له / مسدّد)
class BalanceBadge extends StatelessWidget {
  const BalanceBadge(this.balance, {super.key, this.size = 17});
  final int balance;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = balanceColor(context, balance);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          money(balance.abs()),
          style: TextStyle(fontSize: size, fontWeight: FontWeight.w700, color: c, fontFeatures: tabular),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
          child: Text(
            balanceLabel(balance),
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c),
          ),
        ),
      ],
    );
  }
}

/// بطاقة رقم صغيرة في الملخصات
class StatBox extends StatelessWidget {
  const StatBox({super.key, required this.label, required this.value, this.icon, this.color, this.onTap, this.sub});
  final String label;
  final int value;
  final IconData? icon;
  final Color? color;
  final VoidCallback? onTap;
  final String? sub;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = color ?? cs.primary;
    return Card(
      margin: const EdgeInsets.all(4),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (icon != null) ...[
                    Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 16, color: c),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: MoneyText(value, size: 20, color: c),
              ),
              if (sub != null) Text(sub!, style: TextStyle(fontSize: 11.5, color: cs.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// سطر: عنوان ..... قيمة
class KvRow extends StatelessWidget {
  const KvRow(this.label, this.value, {super.key, this.bold = false, this.color, this.prefix = ''});
  final String label;
  final int value;
  final bool bold;
  final Color? color;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: bold ? 16 : 14.5, fontWeight: bold ? FontWeight.w700 : FontWeight.w500),
            ),
          ),
          Text(
            '$prefix${money(value)}',
            textDirection: TextDirection.ltr,
            style: TextStyle(
              fontSize: bold ? 18 : 15,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: tabular,
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 14, 6, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w700)),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: cs.outline),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
          ),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

class ShopAvatar extends StatelessWidget {
  const ShopAvatar(this.name, {super.key, this.active = false, this.done = false});
  final String name;
  final bool active;
  final bool done;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final letter = name.trim().isEmpty
        ? '؟'
        : name
              .trim()
              .replaceFirst(RegExp(r'^(بقالة|تموينات|سوبرماركت|محل|محلات)\s+'), '')
              .replaceFirst(RegExp(r'^ال(?=..)'), '')
              .characters
              .first;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: active ? cs.primary : cs.surfaceContainerHighest,
          foregroundColor: active ? cs.onPrimary : cs.onSurfaceVariant,
          child: Text(letter, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        ),
        if (done)
          PositionedDirectional(
            bottom: -2,
            end: -2,
            child: Container(
              decoration: BoxDecoration(
                color: paidColor(context),
                shape: BoxShape.circle,
                border: Border.all(color: cs.surface, width: 2),
              ),
              padding: const EdgeInsets.all(1.5),
              child: Icon(Icons.check, size: 12, color: isDark(context) ? const Color(0xFF0B2E12) : Colors.white),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ نوافذ إدخال

Future<bool> confirm(BuildContext c, String msg, {String ok = 'حذف', bool danger = true}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      content: Text(msg, style: const TextStyle(fontSize: 16)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: debtColor(ctx)) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// حقل رقم يقبل الأرقام العربية والإنجليزية
class NumberField extends StatelessWidget {
  const NumberField({
    super.key,
    required this.controller,
    this.label,
    this.hint,
    this.autofocus = false,
    this.decimal = false,
    this.onChanged,
    this.onSubmitted,
    this.big = false,
    this.suffix,
  });
  final TextEditingController controller;
  final String? label;
  final String? hint;
  final bool autofocus;
  final bool decimal;
  final bool big;
  final String? suffix;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹.,٫٬]'))],
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: big ? 28 : 17, fontWeight: FontWeight.w700),
      decoration: InputDecoration(labelText: label, hintText: hint, suffixText: suffix),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

Future<int?> askMoney(BuildContext c, String title, {int? initial, String? hint}) async {
  final ctl = TextEditingController(text: initial == null || initial == 0 ? '' : '$initial');
  final r = await showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: NumberField(
        controller: ctl,
        autofocus: true,
        hint: hint,
        big: true,
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('حفظ')),
      ],
    ),
  );
  return r == null ? null : parseMoney(r);
}

Future<double?> askQty(BuildContext c, String title, {double? initial}) async {
  final ctl = TextEditingController(
    text: initial == null || initial == 0
        ? ''
        : qtyText(initial)
              .replaceAll('\u2066', '')
              .replaceAll('\u2069', '')
              .replaceAll('¼', '.25')
              .replaceAll('½', '.5')
              .replaceAll('¾', '.75'),
  );
  final r = await showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          NumberField(
            controller: ctl,
            autofocus: true,
            decimal: true,
            big: true,
            onSubmitted: (v) => Navigator.pop(ctx, v),
          ),
          const SizedBox(height: 8),
          const Text('مثال: 2.5 = اثنين ونص ، 0.25 = ربع', style: TextStyle(fontSize: 12.5)),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text), child: const Text('حفظ')),
      ],
    ),
  );
  return r == null ? null : parseQty(r);
}

Future<String?> askText(BuildContext c, String title, {String initial = '', String? hint}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: c,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('حفظ')),
      ],
    ),
  );
}
