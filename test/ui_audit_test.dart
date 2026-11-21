// تدقيق الواجهة الآلي: كل شاشة رئيسية × 3 مقاسات × خطّان.
// يقيس: (1) تجاوز الحدود overflow  (2) أهداف لمس أصغر من 48dp  (3) نص مقطوع.
// يطبع تقريراً ويفشل عند أي overflow (أهداف اللمس تُطبع للمراجعة).
import 'dart:io';

import 'package:distributor/core/license_service.dart';
import 'package:distributor/core/remote_config.dart';
import 'package:distributor/core/update_service.dart';
import 'package:distributor/data/backup_service.dart';
import 'package:distributor/data/store.dart';
import 'package:distributor/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

import 'support/contrast.dart';

const sizes = {'صغير 320×568': Size(320, 568), 'شائع 360×740': Size(360, 740), 'كبير 412×915': Size(412, 915)};

/// خادم وهمي: الترخيص مفعّل، بدون شبكة حقيقية
class _FakeFetcher extends RemoteFetcher {
  @override
  Future<RemoteFile?> fetch(String file) async =>
      file == 'license.json' ? RemoteFile.ok({'active': true, 'code': 'X', 'message': ''}) : null;
}

/// الشاشات الفرعية التي تُفتح من القائمة الجانبية / زر الإعدادات
const drawerPages = ['الأصناف والأسعار', 'المصاريف', 'الإعدادات', 'تواصل مع المطوّر'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Store store;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('ui_audit');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
    store = Store();
    await store.init();
    await store.loadDemo(days: 14);
    await store.setMeta('onboarded', true);
  });

  tearDownAll(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  final report = <String>[];
  tearDownAll(() {
    // ignore: avoid_print
    print('\n===== تقرير تدقيق الواجهة =====\n${report.join('\n')}');
  });

  // كل مقاس × خطّان × وضعان (فاتح/داكن). التباين يُفحص في كل شاشة يزورها التدقيق.
  for (final dark in [false, true]) {
    for (final scale in [1.0, 1.25]) {
      for (final e in sizes.entries) {
        final tag = '${e.key} ×$scale ${dark ? 'داكن' : 'فاتح'}';
        testWidgets('${e.key} · خط ×$scale · ${dark ? 'داكن' : 'فاتح'}', (tester) async {
          await tester.runAsync(() => store.setMeta('textScale', scale));
          await tester.runAsync(() => store.setMeta('themeMode', dark ? 2 : 1));
          tester.view.physicalSize = e.value * 3;
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);

          final overflows = <String>[];
          final others = <String>[];
          final oldHandler = FlutterError.onError;
          FlutterError.onError = (d) {
            final s = d.exceptionAsString();
            // مصدر الخطأ: أول سطر يشير لملف داخل lib/ (الودجت المسبّب ورقم السطر)
            final full = d.toString(minLevel: DiagnosticLevel.debug);
            final src = RegExp(r'lib/[\w/]+\.dart:\d+').firstMatch(full)?.group(0) ?? '?';
            (s.contains('overflowed') ? overflows : others).add('${s.split('\n').first} ← $src');
          };

          Object? crash;
          final small = <String>{};
          final lowContrast = <String>{};
          void contrastAt(String where) {
            final ctx = tester.element(find.byType(Scaffold).last);
            for (final b in scanContrast(Theme.of(ctx).scaffoldBackgroundColor)) {
              lowContrast.add('$where $b');
            }
          }

          try {
            await tester.pumpWidget(
              MultiProvider(
                providers: [
                  ChangeNotifierProvider.value(value: store),
                  Provider.value(value: BackupService(store)),
                  ChangeNotifierProvider(create: (_) => LicenseService(store, fetcher: _FakeFetcher())),
                  ChangeNotifierProvider(create: (_) => UpdateService(store, fetcher: _FakeFetcher())),
                ],
                child: const DistributorApp(),
              ),
            );
            await tester.pump(const Duration(milliseconds: 500));
            await tester.pump(const Duration(milliseconds: 500));

            final tabs = tester.widgetList<NavigationDestination>(find.byType(NavigationDestination)).length;
            for (var t = 0; t < (tabs == 0 ? 1 : tabs); t++) {
              if (tabs > 0) {
                await tester.tap(find.byType(NavigationDestination).at(t));
                await tester.pump(const Duration(milliseconds: 400));
                await tester.pump(const Duration(milliseconds: 400));
              }
              contrastAt('tab$t');
              for (final f in [find.byType(IconButton), find.byType(InkWell), find.byType(ButtonStyleButton)]) {
                for (final el in f.evaluate()) {
                  final w = el.widget;
                  // InkWell غير تفاعلي (مثل Chip للعرض فقط) ليس هدف لمس
                  if (w is InkWell && w.onTap == null && w.onLongPress == null) continue;
                  // الشرائح (Chip): منطقة اللمس الحقيقية = حجم RawChip (يشمل حشوة 48dp خارج الـ InkWell)
                  RenderObject? box = el.renderObject;
                  el.visitAncestorElements((a) {
                    if (a.widget is RawChip) {
                      box = a.renderObject;
                      return false;
                    }
                    return a.widget is! Card;
                  });
                  final b = box;
                  if (b is! RenderBox || !b.hasSize || !b.attached) continue;
                  final s = b.size;
                  if (s.width < 1 || s.height < 1) continue;
                  if (s.height < 40 || s.width < 40) {
                    small.add(
                      'tab$t ${el.widget.runtimeType} ${s.width.toStringAsFixed(0)}×${s.height.toStringAsFixed(0)}',
                    );
                  }
                }
              }
            }

            // ---- القائمة الجانبية + الشاشات الفرعية
            Future<void> settle() async {
              await tester.pump(const Duration(milliseconds: 400));
              await tester.pump(const Duration(milliseconds: 400));
            }

            void scanTargets(String where) {
              contrastAt(where);
              for (final f in [find.byType(IconButton), find.byType(InkWell), find.byType(ButtonStyleButton)]) {
                for (final el in f.evaluate()) {
                  final w = el.widget;
                  // InkWell غير تفاعلي (مثل Chip للعرض فقط) ليس هدف لمس
                  if (w is InkWell && w.onTap == null && w.onLongPress == null) continue;
                  // الشرائح (Chip): منطقة اللمس الحقيقية = حجم RawChip (يشمل حشوة 48dp خارج الـ InkWell)
                  RenderObject? box = el.renderObject;
                  el.visitAncestorElements((a) {
                    if (a.widget is RawChip) {
                      box = a.renderObject;
                      return false;
                    }
                    return a.widget is! Card;
                  });
                  final b = box;
                  if (b is! RenderBox || !b.hasSize || !b.attached) continue;
                  final s = b.size;
                  if (s.width < 1 || s.height < 1) continue;
                  if (s.height < 40 || s.width < 40) {
                    small.add(
                      '$where ${el.widget.runtimeType} ${s.width.toStringAsFixed(0)}×${s.height.toStringAsFixed(0)}',
                    );
                  }
                }
              }
            }

            await tester.tap(find.byType(NavigationDestination).first);
            await settle();
            // ---- سجل اليوم (من الرئيسية)
            await tester.scrollUntilVisible(
              find.text('فتح سجل اليوم'),
              120,
              scrollable: find.descendant(of: find.byType(ListView).first, matching: find.byType(Scrollable)).first,
            );
            await settle();
            await tester.tap(find.text('فتح سجل اليوم'));
            await settle();
            expect(find.widgetWithText(AppBar, 'سجل اليوم'), findsOneWidget);
            scanTargets('سجل اليوم');
            tester.state<NavigatorState>(find.byType(Navigator).first).pop();
            await settle();
            for (final page in drawerPages) {
              await tester.tap(find.byTooltip('القائمة').first);
              await settle();
              scanTargets('drawer');
              final inDrawer = find.descendant(of: find.byType(NavigationDrawer), matching: find.text(page));
              await tester.scrollUntilVisible(
                inDrawer,
                80,
                scrollable: find.descendant(of: find.byType(NavigationDrawer), matching: find.byType(Scrollable)).first,
              );
              await tester.tap(inDrawer.last);
              await settle();
              scanTargets(page);
              if (page == 'الأصناف والأسعار') {
                await tester.tap(find.text('إضافة صنف جديد').first);
                await settle();
                scanTargets('نموذج الصنف');
                tester.state<NavigatorState>(find.byType(Navigator).first).pop();
                await settle();
              }
              tester.state<NavigatorState>(find.byType(Navigator).first).pop();
              await settle();
            }
          } catch (e, st) {
            crash = '$e\n${st.toString().split('\n').where((l) => l.contains('ui_audit_test')).take(2).join('\n')}';
          } finally {
            FlutterError.onError = oldHandler;
          }
          if (crash != null) report.add('   ✖ تعطل: $crash');
          expect(crash, isNull);
          report.add(
            '$tag: overflow=${overflows.length} · أهداف<40dp=${small.length} · تباين<3=${lowContrast.length}'
            '${small.isEmpty ? '' : '\n   ${small.take(8).join('\n   ')}'}'
            '${overflows.isEmpty ? '' : '\n   ⚠ ${overflows.toSet().join('\n   ⚠ ')}'}'
            '${lowContrast.isEmpty ? '' : '\n   ◐ ${lowContrast.take(10).join('\n   ◐ ')}'}',
          );
          if (others.isNotEmpty) report.add('   ✖ أخطاء أخرى: ${others.toSet().take(5).join('\n   ✖ ')}');
          expect(overflows, isEmpty, reason: overflows.join('\n'));
          expect(others, isEmpty, reason: others.join('\n'));
          expect(lowContrast, isEmpty, reason: lowContrast.join('\n'));
        });
      }
    }
  }
}
