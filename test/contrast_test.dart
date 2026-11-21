// فحص تباين الألوان الآلي (WCAG): لكل نص ظاهر، يُحسب لونه الفعلي مقابل أقرب خلفية حقيقية
// (Material/Ink/Container/Chip). يفشل لو التباين < 3:1 (الحد الأدنى للنص الكبير/العناصر).
// سبب وجوده: خطأ "نص أسود على شريحة داكنة" في 2.2.0 لم يكشفه تدقيق التجاوز.
import 'dart:io';

import 'package:distributor/screens/product_form.dart';
import 'package:distributor/ui/theme.dart';
import 'package:distributor/data/store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/contrast.dart';
import 'package:provider/provider.dart';

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
      final bad = scanContrast(theme.scaffoldBackgroundColor);
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
      final bad = scanContrast(theme.scaffoldBackgroundColor);
      expect(bad, isEmpty, reason: bad.join('\n'));
      await t.pumpWidget(const SizedBox());
    });
  }
}
