// لقطات شاشة حقيقية (خطوط حقيقية، 360×800 @3x) لكل شاشة بالوضعين — للمراجعة البصرية بكسل بكسل.
// التشغيل: flutter test test/screenshots_test.dart --tags shots --update-goldens
// الناتج: test/goldens/<light|dark>/NN-name.png  (لا يُستخدم كمقارنة في CI — مراجعة فقط)
@Tags(['shots'])
library;

import 'dart:async';
import 'dart:io';

import 'package:distributor/core/command_service.dart';
import 'package:distributor/core/license_service.dart';
import 'package:distributor/core/remote_config.dart';
import 'package:distributor/core/update_service.dart';
import 'package:distributor/data/backup_service.dart';
import 'package:distributor/data/store.dart';
import 'package:distributor/main.dart';
import 'package:distributor/screens/collect_sheet.dart';
import 'package:distributor/screens/day_log_screen.dart';
import 'package:distributor/screens/developer_screen.dart';
import 'package:distributor/screens/expenses_screen.dart';
import 'package:distributor/screens/lines_editor.dart';
import 'package:distributor/screens/product_form.dart';
import 'package:distributor/screens/products_screen.dart';
import 'package:distributor/screens/settings_screen.dart';
import 'package:distributor/screens/shop_detail_screen.dart';
import 'package:distributor/screens/shop_form.dart';
import 'package:distributor/ui/shell.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:provider/provider.dart';

class _FakeFetcher extends RemoteFetcher {
  @override
  Future<RemoteFile?> fetch(String file, {String? deviceId}) async =>
      file == 'license.json' ? RemoteFile.ok({'active': true, 'code': 'X', 'message': ''}) : null;
}

Future<void> _loadFonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  await load('Plex', [
    for (final w in ['Regular', 'Medium', 'SemiBold', 'Bold']) 'assets/fonts/IBMPlexSansArabic-$w.ttf',
  ]);
  final root = Platform.environment['FLUTTER_ROOT'] ?? '/opt/flutter';
  await load('MaterialIcons', ['$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Store store;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('shots');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
    await _loadFonts();
    store = Store();
    await store.init();
    await store.loadDemo(days: 14);
    await store.setMeta('onboarded', true);
  });

  tearDownAll(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('لقطات $mode', (tester) async {
      // الظلال الحقيقية (الافتراضي في الاختبارات = حدّ أسود صلب بدل الظل)
      debugDisableShadows = false;
      await tester.runAsync(() => store.setMeta('themeMode', dark ? 2 : 1));
      await tester.runAsync(() => store.setMeta('textScale', 1.0));
      tester.view.physicalSize = const Size(360, 800) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(value: store),
            Provider.value(value: BackupService(store)),
            ChangeNotifierProvider(create: (_) => LicenseService(store, fetcher: _FakeFetcher())),
            Provider(create: (c) => CommandService(store, c.read<LicenseService>())),
            ChangeNotifierProvider(create: (_) => UpdateService(store, fetcher: _FakeFetcher())),
          ],
          child: const DistributorApp(),
        ),
      );
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
      }

      var n = 0;
      Future<void> shot(String name) async {
        await settle();
        n++;
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/$mode/${n.toString().padLeft(2, '0')}-$name.png'),
        );
      }

      final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
      Future<void> push(Widget w, String name) async {
        unawaited(nav.push(MaterialPageRoute<void>(builder: (_) => w)));
        await shot(name);
        nav.pop();
        await settle();
      }

      await shot('home');
      for (final (i, name) in [(1, 'shops'), (2, 'trader'), (3, 'reports')]) {
        await tester.tap(find.byType(NavigationDestination).at(i));
        await shot(name);
      }
      await tester.tap(find.byType(NavigationDestination).first);
      await settle();
      shellScaffoldKey.currentState!.openDrawer();
      await shot('drawer');
      shellScaffoldKey.currentState!.closeDrawer();
      await settle();

      final ctx = tester.element(find.byType(HomeShell));
      unawaited(openDayLog(ctx, DayMode.deliver));
      await shot('daylog-deliver');
      await tester.tap(find.textContaining('التحصيل').first);
      await shot('daylog-collect');
      nav.pop();
      await settle();

      final shop = store.shops.first;
      unawaited(showCollectSheet(ctx, shop));
      await shot('collect-sheet');
      nav.pop();
      await settle();

      await push(ShopDetailScreen(shopId: shop.id), 'shop-detail');
      await push(LinesEditorScreen(mode: LinesMode.delivery, day: store.day, shop: shop), 'delivery-editor');
      await push(const ProductsScreen(), 'products');
      await push(const ProductFormScreen(), 'product-form');
      await push(const ShopFormScreen(), 'shop-form');
      await push(const ExpensesScreen(), 'expenses');
      await push(const SettingsScreen(), 'settings');
      await push(const DeveloperScreen(), 'developer');
      debugDisableShadows = true; // يجب إرجاعه قبل نهاية الاختبار (فحص ثوابت flutter_test)
    });
  }
}
