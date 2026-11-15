import 'dart:math';

import 'package:distributor/core/format.dart';
import 'package:distributor/data/ledger.dart';
import 'package:distributor/data/ledger_index.dart';
import 'package:distributor/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// يولّد حركات عشوائية حتمية (بذرة ثابتة) لمقارنة الفهرس بالحساب الساذج المرجعي
List<ShopTx> randomTxs(Random r, List<Shop> shops, int days) {
  final out = <ShopTx>[];
  var day = '2024-01-01';
  var c = 0;
  for (var d = 0; d < days; d++) {
    for (final s in shops) {
      final n = r.nextInt(4);
      for (var k = 0; k < n; k++) {
        final type = ShopTxType.values[r.nextInt(4)];
        out.add(
          ShopTx(
            id: 't${c++}',
            shopId: s.id,
            type: type,
            day: day,
            // وقت إنشاء عشوائي حتى نتأكد أن الترتيب داخل اليوم لا يؤثر على النتائج
            createdAt: r.nextInt(1 << 30),
            lines: type.hasLines
                ? [
                    TxLine(
                      productId: 'p',
                      name: 'p',
                      unit: 'k',
                      qty: (r.nextInt(12) + 1) * 0.25,
                      price: 1000 + r.nextInt(3000),
                      cost: 900,
                    ),
                  ]
                : const [],
            amount: type.hasLines ? 0 : r.nextInt(9000) + 1,
          ),
        );
      }
    }
    day = shiftDay(day, 1);
  }
  return out..shuffle(r);
}

void main() {
  group('AccountIndex يطابق الحساب المرجعي', () {
    for (final seed in [1, 2, 3, 4, 5]) {
      test('بذرة $seed', () {
        final r = Random(seed);
        final shops = [
          for (var i = 0; i < 6; i++) Shop(id: 's$i', name: 's$i', openingBalance: r.nextInt(5000), createdAt: 0),
        ];
        final txs = randomTxs(r, shops, 60);
        for (final s in shops) {
          final idx = AccountIndex<ShopTx>.build(s.openingBalance, txs.where((t) => t.shopId == s.id));
          expect(idx.balance, shopBalance(s, txs), reason: 'balance ${s.id}');
          // كل يوم + أيام خارج النطاق
          for (final day in ['2023-12-31', '2024-01-01', '2024-01-15', '2024-02-10', '2024-02-29', '2025-01-01']) {
            final a = shopDayFromIndex(idx, day);
            final b = shopDay(s, txs, day);
            expect(a.before, b.before, reason: 'before $day');
            expect(a.delivered, b.delivered);
            expect(a.returned, b.returned);
            expect(a.paid, b.paid);
            expect(a.discount, b.discount);
            expect(a.remaining, b.remaining);
          }
          // الكشف الجاري
          final st = shopStatement(s, txs);
          expect(idx.length, st.length);
          for (var i = 0; i < st.length; i++) {
            expect(idx.balanceAfter(i), st[i].balanceAfter);
          }
          expect(lastPaymentFromIndex(idx), lastPaymentDay(s.id, txs));
        }
      });
    }
  });

  test('حساب فارغ', () {
    final idx = AccountIndex<ShopTx>.build(700, const []);
    expect(idx.balance, 700);
    expect(idx.balanceBefore('2024-01-01'), 700);
    expect(idx.on('2024-01-01'), isEmpty);
    expect(lastPaymentFromIndex(idx), isNull);
  });

  test('الأداء: سنتان × 40 بقالة (~60 ألف حركة)', () {
    final r = Random(9);
    final shops = [for (var i = 0; i < 40; i++) Shop(id: 's$i', name: 's$i', createdAt: 0)];
    final txs = randomTxs(r, shops, 730);
    final today = shiftDay('2024-01-01', 729);

    // المرجعي الساذج: مسح كل الحركات لكل بقالة
    final sw1 = Stopwatch()..start();
    var a = 0;
    for (final s in shops) {
      a += shopDay(s, txs, today).remaining + shopBalance(s, txs);
    }
    sw1.stop();

    // الفهرس: يُبنى مرة واحدة ثم كل إطار رسم = بحث ثنائي
    final byShop = <String, List<ShopTx>>{};
    for (final t in txs) {
      (byShop[t.shopId] ??= []).add(t);
    }
    final swBuild = Stopwatch()..start();
    final idx = {for (final s in shops) s.id: AccountIndex<ShopTx>.build(0, byShop[s.id] ?? const <ShopTx>[])};
    swBuild.stop();
    final sw2 = Stopwatch()..start();
    var b = 0;
    for (var frame = 0; frame < 100; frame++) {
      b = 0;
      for (final s in shops) {
        b += shopDayFromIndex(idx[s.id]!, today).remaining + idx[s.id]!.balance;
      }
    }
    sw2.stop();
    final perFrameUs = sw2.elapsedMicroseconds / 100;

    expect(b, a);
    // ignore: avoid_print
    print(
      'txs=${txs.length} | ساذج لكل إطار: ${sw1.elapsedMilliseconds}ms | '
      'بناء الفهرس مرة واحدة: ${swBuild.elapsedMilliseconds}ms | فهرس لكل إطار: ${perFrameUs.toStringAsFixed(0)}µs',
    );
    // ميزانية إطار 60fps = 16.6ms؛ نطلب أقل من 2ms للحسابات
    expect(perFrameUs, lessThan(2000));
  });
}
