// فحص تباين الألوان الآلي (WCAG): لكل نص ظاهر، يُحسب لونه الفعلي مقابل أقرب خلفية حقيقية
// (Material/Ink/Container/Chip). يفشل لو التباين < 3:1 (الحد الأدنى للنص الكبير/العناصر).
// سبب وجوده: خطأ "نص أسود على شريحة داكنة" في 2.2.0 لم يكشفه تدقيق التجاوز.
import 'dart:io';
import 'dart:math' as math;

import 'package:distributor/screens/product_form.dart';
import 'package:distributor/ui/theme.dart';
import 'package:distributor/data/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color _blend(Color fg, Color bg) => Color.alphaBlend(fg, bg);

/// يمسح الشجرة: لون النص الفعلي مقابل أقرب خلفية معتمة
List<String> scan(WidgetTester t, Color scaffoldBg) {
  final bad = <String>[];
  for (final el in find.byType(RichText).evaluate()) {
    final rt = el.widget as RichText;
    final text = rt.text.toPlainText().trim();
    if (text.isEmpty) continue;
    // لون null = أسود افتراضي من المحرك (هذا بالضبط خطأ 2.2.0)
    final fg = rt.text.style?.color ?? const Color(0xFF000000);
    var bg = scaffoldBg;
    final layers = <Color>[];
    el.visitAncestorElements((a) {
      final w = a.widget;
      Color? c;
      if (w is Material && w.type != MaterialType.transparency) c = w.color;
      if (w is DecoratedBox && w.decoration is BoxDecoration) c = (w.decoration as BoxDecoration).color;
      if (w is Container && w.decoration is BoxDecoration) c = (w.decoration as BoxDecoration).color;
      if (w is Container && w.color != null) c = w.color;
      if (w is ColoredBox) c = w.color;
      if (w is Ink && w.decoration is BoxDecoration) c = (w.decoration as BoxDecoration).color;
      if (c != null && c.a > 0) {
        layers.add(c);
        if (c.a >= 0.99) return false;
      }
      return true;
    });
    for (final c in layers.reversed) {
      bg = _blend(c, bg);
    }
    final r = contrast(_blend(fg, bg), bg);
    if (r < 3.0) bad.add('"$text" ${r.toStringAsFixed(2)}:1');
  }
  return bad;
}

void main() {
  late Store store;
  setUpAll(() async {
    final tmp = await Directory.systemTemp.createTemp('contrast');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
    store = Store();
    await store.init();
  });

  for (final b in Brightness.values) {
    testWidgets('تباين الشرائح والأزرار — $b', (t) async {
      final theme = buildTheme(b);
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          home: Scaffold(
            body: ListView(
              children: [
                Wrap(
                  children: [
                    for (var i = 0; i < 3; i++)
                      ChoiceChip(label: Text('شريحة$i'), selected: i == 0, onSelected: (_) {}),
                    ActionChip(label: const Text('إجراء'), onPressed: () {}),
                    const Chip(label: Text('عرض')),
                    FilterChip(label: const Text('فلتر'), selected: true, onSelected: (_) {}),
                  ],
                ),
                FilledButton(onPressed: () {}, child: const Text('ممتلئ')),
                FilledButton.tonal(onPressed: () {}, child: const Text('نغمي')),
                OutlinedButton(onPressed: () {}, child: const Text('محدد')),
                TextButton(onPressed: () {}, child: const Text('نصي')),
                SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('أ')),
                    ButtonSegment(value: 1, label: Text('ب')),
                  ],
                  selected: const {0},
                  onSelectionChanged: (_) {},
                ),
              ],
            ),
            bottomNavigationBar: NavigationBar(
              destinations: const [
                NavigationDestination(icon: Icon(Icons.today), label: 'اليوم'),
                NavigationDestination(icon: Icon(Icons.store), label: 'البقالات'),
              ],
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      final bad = scan(t, theme.scaffoldBackgroundColor);
      expect(bad, isEmpty, reason: bad.join('\n'));
    });

    testWidgets('تباين نموذج الصنف (لقطة المستخدم) — $b', (t) async {
      final theme = buildTheme(b);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: store,
          child: MaterialApp(theme: theme, home: const ProductFormScreen()),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      final bad = scan(t, theme.scaffoldBackgroundColor);
      expect(bad, isEmpty, reason: bad.join('\n'));
      await t.pumpWidget(const SizedBox());
    });
  }
}
