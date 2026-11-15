import 'package:distributor/core/format.dart';
import 'package:distributor/data/ledger.dart';
import 'package:distributor/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

TxLine line(String id, double q, int price, [int cost = 0]) =>
    TxLine(productId: id, name: id, unit: 'كرتون', qty: q, price: price, cost: cost);

var _t = 0;
ShopTx deliver(String day, List<TxLine> l) =>
    ShopTx(id: 'd${_t++}', shopId: 's', type: ShopTxType.delivery, day: day, createdAt: _t, lines: l);
ShopTx pay(String day, int a) =>
    ShopTx(id: 'p${_t++}', shopId: 's', type: ShopTxType.payment, day: day, createdAt: _t, amount: a);
ShopTx ret(String day, List<TxLine> l) =>
    ShopTx(id: 'r${_t++}', shopId: 's', type: ShopTxType.returned, day: day, createdAt: _t, lines: l);

void main() {
  final shop = Shop(id: 's', name: 'بقالة', openingBalance: 1000, createdAt: 0);

  test('المتبقي على البقالة = سابق + عطاء − مرتجع − تحصيل', () {
    final txs = [
      deliver('2025-01-01', [line('z', 2, 2000), line('h', 0.5, 1800)]), // 4900
      pay('2025-01-01', 3000),
      deliver('2025-01-02', [line('z', 1.25, 2000)]), // 2500
      ret('2025-01-02', [line('z', 0.25, 2000)]), // 500
      pay('2025-01-02', 2000),
    ];
    expect(shopBalance(shop, txs), 1000 + 4900 - 3000 + 2500 - 500 - 2000);

    final d2 = shopDay(shop, txs, '2025-01-02');
    expect(d2.before, 1000 + 4900 - 3000);
    expect(d2.delivered, 2500);
    expect(d2.returned, 500);
    expect(d2.due, 2900 + 2000);
    expect(d2.remaining, 2900);

    final st = shopStatement(shop, txs);
    expect(st.last.balanceAfter, 2900);
    expect(st.first.balanceAfter, 5900);
  });

  test('الدفع الزائد يصير رصيداً للبقالة', () {
    final txs = [deliver('2025-01-01', [line('z', 1, 2000)]), pay('2025-01-01', 5000)];
    expect(shopBalance(shop, txs), -2000);
  });

  test('البضاعة في السيارة', () {
    final tr = TraderTx(
        id: 't', traderId: 'tr', type: TraderTxType.pickup, day: '2025-01-01', createdAt: 0, lines: [line('z', 10, 1900)]);
    final rows = dayStock('2025-01-01', [deliver('2025-01-01', [line('z', 7.5, 2000)])], [tr], []);
    expect(rows.single.onHand, 2.5);
    expect(tr.amount, 19000);
  });

  test('التقرير والربح', () {
    final r = buildReport(
      from: '2025-01-01',
      to: '2025-01-31',
      shops: [shop],
      shopTxs: [deliver('2025-01-05', [line('z', 2, 2000, 1500)]), pay('2025-01-05', 1000)],
      traderTxs: const [],
      expenses: [Expense(id: 'e', day: '2025-01-05', amount: 200, category: 'بنزين', createdAt: 0)],
    );
    expect(r.netSales, 4000);
    expect(r.grossProfit, 1000);
    expect(r.netProfit, 800);
    expect(r.collected, 1000);
  });

  test('تنسيق الكميات والأرقام العربية', () {
    expect(qtyText(1.5), '\u20661½\u2069');
    expect(parseQty(qtyText(1.5)), 1.5);
    expect(qtyText(0.25), '¼');
    expect(qtyText(3), '3');
    expect(parseMoney('١٢٬٥٠٠'), 12500);
    expect(parseQty('٢٫٥'), 2.5);
    expect(money(1234567), '1,234,567');
  });
}
