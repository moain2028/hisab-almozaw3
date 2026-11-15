import 'dart:io';

import 'package:distributor/data/ledger.dart';
import 'package:distributor/data/store.dart';
import 'package:distributor/models/models.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// اختبارات تكامل للمخزن: Hive حقيقي في مجلد مؤقت.
/// الهدف: التأكد أن الفهارس التزايدية والكاش تبقى مطابقة للحساب المرجعي بعد أي تسلسل عمليات.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Store store;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('hisab_test');
    // Hive.initFlutter يحتاج path_provider؛ نوجهه لمجلد مؤقت
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
    store = Store();
    await store.init();
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  void expectConsistent() {
    for (final s in store.shops) {
      expect(store.balanceOf(s), shopBalance(s, store.shopTxs), reason: s.name);
      final ref = shopDay(s, store.shopTxs, store.day);
      expect(store.dayOf(s).remaining, ref.remaining);
      expect(store.dayOf(s).before, ref.before);
    }
  }

  test('سيناريو يوم كامل + تعديل + حذف + تراجع', () async {
    await store.addStarterProducts();
    final p = store.products.first;
    final a = await store.addShop(name: 'أ', openingBalance: 1000);
    final b = await store.addShop(name: 'ب');
    final day = store.day;

    ShopTx deliver(Shop s, double q) => ShopTx(
      id: newId(),
      shopId: s.id,
      type: ShopTxType.delivery,
      day: day,
      createdAt: nowMs(),
      lines: [TxLine(productId: p.id, name: p.name, unit: p.unit, qty: q, price: p.sellPrice, cost: p.costPrice)],
    );

    final d1 = deliver(a, 2);
    await store.saveShopTx(d1);
    await store.saveShopTx(deliver(b, 1.5));
    expectConsistent();
    expect(store.balanceOf(a), 1000 + 2 * p.sellPrice);

    // تحصيل جزئي
    await store.addPayment(a.id, day, 3000);
    expectConsistent();
    expect(store.dayOf(a).remaining, 1000 + 2 * p.sellPrice - 3000);

    // تعديل العطاء (نفس المعرّف)
    final edited = ShopTx(
      id: d1.id,
      shopId: a.id,
      type: ShopTxType.delivery,
      day: day,
      createdAt: d1.createdAt,
      lines: [TxLine(productId: p.id, name: p.name, unit: p.unit, qty: 3, price: p.sellPrice, cost: p.costPrice)],
    );
    await store.saveShopTx(edited);
    expectConsistent();
    expect(store.shopTxsOf(a.id, day: day).where((t) => t.type == ShopTxType.delivery).length, 1);

    // حذف ثم تراجع
    final old = await store.deleteShopTx(d1.id);
    expectConsistent();
    await store.saveShopTx(old!);
    expectConsistent();
    expect(store.balanceOf(a), 1000 + 3 * p.sellPrice - 3000);

    // ملخص اليوم
    final s = store.summary();
    expect(s.delivered, 3 * p.sellPrice + (1.5 * p.sellPrice).round());
    expect(s.collected, 3000);
    expect(s.deliveredShops.length, 2);

    // حذف بقالة ثم استرجاعها
    final removed = await store.deleteShop(b.id);
    expect(store.shops.length, 1);
    await store.restoreShop(removed!.$1, removed.$2);
    expect(store.shops.length, 2);
    expectConsistent();
  });

  test('التصدير ثم الاستيراد يرجّع نفس الأرصدة', () async {
    await store.loadDemo(days: 20);
    final before = {for (final s in store.shops) s.name: store.balanceOf(s)};
    final traderBefore = store.traderBalanceOf(store.mainTrader);
    final json = store.exportJson();

    await store.wipeAll();
    expect(store.shops, isEmpty);

    await store.importJson(json, replace: true);
    final after = {for (final s in store.shops) s.name: store.balanceOf(s)};
    expect(after, before);
    expect(store.traderBalanceOf(store.mainTrader), traderBefore);
    expectConsistent();
  });

  test('البيانات تبقى بعد إعادة فتح التطبيق', () async {
    await store.loadDemo(days: 5);
    final total = store.totalOwed;
    final count = store.recordCount;
    await store.flush();
    await Hive.close();

    final reopened = Store();
    await reopened.init();
    expect(reopened.totalOwed, total);
    expect(reopened.recordCount, count);
  });

  test('استيراد ملف من إصدار أحدث يُرفض بدون لمس البيانات', () async {
    await store.loadDemo(days: 3);
    final count = store.recordCount;
    await expectLater(
      store.importMap({'app': kAppId, 'version': 999, 'shops': []}, replace: true),
      throwsFormatException,
    );
    expect(store.recordCount, count);
  });
}
