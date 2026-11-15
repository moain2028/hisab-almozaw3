/// بيانات مبدئية وتجريبية. تُبنى كخريطة بصيغة النسخة الاحتياطية ثم تُستورد دفعة واحدة
/// (أسرع بكثير من حفظ كل سجل على حدة، ولا تُطلق مئات الإشعارات للواجهة).
library;

import '../core/format.dart';
import '../models/models.dart';
import 'ledger.dart';

/// (الاسم، الوحدة، سعر البيع، سعر الشراء)
const starterProducts = [
  ('زبادي', 'كرتون', 2200, 1900),
  ('حقين', 'كرتون', 1800, 1550),
  ('لبن', 'كرتون', 2000, 1700),
  ('جبن', 'كرتون', 3500, 3100),
];

Map<String, Object?> buildDemoData({required int days, required String Function() newId}) {
  var seed = 7;
  int rnd(int m) {
    seed = (seed * 1103515245 + 12345) & 0x7fffffff;
    return seed % m;
  }

  final now = DateTime.now().millisecondsSinceEpoch;
  final trader = Trader(id: newId(), name: 'مؤسسة الألبان');
  final products = [
    for (var i = 0; i < starterProducts.length; i++)
      Product(
        id: newId(),
        name: starterProducts[i].$1,
        unit: starterProducts[i].$2,
        sellPrice: starterProducts[i].$3,
        costPrice: starterProducts[i].$4,
        sortOrder: i + 1,
      ),
  ];
  const names = [
    ('بقالة الأمانة', 'أبو محمد', 'الحي الشرقي', 0),
    ('سوبرماركت النور', 'عبدالله', 'الحي الشرقي', 4000),
    ('بقالة الخير', 'سالم', 'شارع السوق', 0),
    ('تموينات البركة', 'أحمد', 'شارع السوق', 0),
    ('بقالة السعادة', 'خالد', 'الحي الغربي', 2500),
    ('بقالة الوفاء', 'ناصر', 'الحي الغربي', 0),
  ];
  final shops = [
    for (var i = 0; i < names.length; i++)
      Shop(
        id: newId(),
        name: names[i].$1,
        owner: names[i].$2,
        area: names[i].$3,
        openingBalance: names[i].$4,
        routeOrder: i + 1,
        createdAt: now,
      ),
  ];

  final shopTxs = <ShopTx>[];
  final traderTxs = <TraderTx>[];
  final expenses = <Expense>[];
  final today = todayKey();
  const qs = [0.5, 1.0, 1.5, 2.0, 3.0, 0.25, 1.0, 2.5];
  var traderOwe = 0;
  var lastPickup = 0;

  for (var back = days - 1; back >= 0; back--) {
    final d = shiftDay(today, -back);
    var t = now - back * 86400000 - 40000000;

    // صباحاً: دفع حساب أمس للتاجر
    if (lastPickup > 0 && traderOwe > 0) {
      final pay = lastPickup > traderOwe ? traderOwe : lastPickup;
      traderTxs.add(
        TraderTx(id: newId(), traderId: trader.id, type: TraderTxType.payment, day: d, createdAt: t, amount: pay),
      );
      traderOwe -= pay;
    }

    // العطاء
    final picked = <String, double>{};
    final deliveries = <ShopTx>[];
    for (final s in shops) {
      if (rnd(10) < 2) continue;
      final lines = <TxLine>[];
      for (final p in products) {
        if (rnd(10) < 4) continue;
        final q = qs[rnd(qs.length)];
        lines.add(TxLine(productId: p.id, name: p.name, unit: p.unit, qty: q, price: p.sellPrice, cost: p.costPrice));
        picked[p.id] = (picked[p.id] ?? 0) + q;
      }
      if (lines.isEmpty) continue;
      t += 600000;
      deliveries.add(ShopTx(id: newId(), shopId: s.id, type: ShopTxType.delivery, day: d, createdAt: t, lines: lines));
    }
    final pickup = TraderTx(
      id: newId(),
      traderId: trader.id,
      type: TraderTxType.pickup,
      day: d,
      createdAt: t - 3600000 * 3,
      lines: [
        for (final p in products)
          if (picked[p.id] != null)
            TxLine(
              productId: p.id,
              name: p.name,
              unit: p.unit,
              qty: picked[p.id]! + 1,
              price: p.costPrice,
              cost: p.costPrice,
            ),
      ],
    );
    traderTxs.add(pickup);
    traderOwe += pickup.amount;
    lastPickup = pickup.amount;
    shopTxs.addAll(deliveries);

    // أحياناً مرتجع
    if (rnd(4) == 0 && deliveries.isNotEmpty) {
      final del = deliveries[rnd(deliveries.length)];
      final l = del.lines.first;
      shopTxs.add(
        ShopTx(
          id: newId(),
          shopId: del.shopId,
          type: ShopTxType.returned,
          day: d,
          createdAt: t + 1000,
          lines: [TxLine(productId: l.productId, name: l.name, unit: l.unit, qty: 0.25, price: l.price, cost: l.cost)],
          note: 'منتهي الصلاحية',
        ),
      );
    }

    if (rnd(2) == 0) {
      expenses.add(Expense(id: newId(), day: d, amount: 1500 + rnd(3) * 500, category: 'بنزين', createdAt: t));
    }

    // ليلاً: التحصيل (اليوم الحالي لم يُحصّل بعد)
    if (back == 0) continue;
    for (final s in shops) {
      final due = shopDay(s, shopTxs, d).remaining;
      if (due <= 0 || rnd(10) < 2) continue;
      final pay = rnd(3) == 0 ? (due * 0.6).round() ~/ 100 * 100 : due;
      if (pay <= 0) continue;
      t += 300000;
      shopTxs.add(
        ShopTx(id: newId(), shopId: s.id, type: ShopTxType.payment, day: d, createdAt: t + 36000000, amount: pay),
      );
    }
  }

  return {
    'app': 'hisab_almozaw3',
    'version': 2,
    'shops': [for (final s in shops) s.toMap()],
    'products': [for (final p in products) p.toMap()],
    'traders': [trader.toMap()],
    'shopTxs': [for (final t in shopTxs) t.toMap()],
    'traderTxs': [for (final t in traderTxs) t.toMap()],
    'expenses': [for (final e in expenses) e.toMap()],
  };
}
