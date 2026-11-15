/// منطق المحاسبة الصافي (بدون واجهة أو تخزين) حتى يمكن اختباره بسهولة.
///
/// القاعدة البسيطة التي يفهمها الموزع:
///   المتبقي على البقالة = دين سابق + كل العطاءات − المرتجعات − التحصيلات − الخصومات
///   المتبقي للتاجر     = رصيد سابق + كل الاستلامات − الإرجاعات − الدفعات
library;

import '../models/models.dart';

// ------------------------------------------------------------------ البقالة

/// ملخص بقالة في يوم معيّن (هذا ما يحتاجه الموزع ليلاً عند التحصيل)
class ShopDay {
  ShopDay({
    required this.before,
    required this.delivered,
    required this.returned,
    required this.paid,
    required this.discount,
  });

  /// الباقي من الأيام السابقة (قبل هذا اليوم)
  final int before;

  /// عطاء هذا اليوم
  final int delivered;

  /// مرتجع هذا اليوم
  final int returned;

  /// المحصَّل في هذا اليوم
  final int paid;

  /// الخصم في هذا اليوم
  final int discount;

  /// المطلوب قبل التحصيل = السابق + عطاء اليوم − المرتجع
  int get due => before + delivered - returned - discount;

  /// الباقي على البقالة في نهاية اليوم
  int get remaining => due - paid;

  bool get hasDelivery => delivered > 0;
  bool get hasPayment => paid > 0;
  bool get hasActivity =>
      delivered > 0 || returned > 0 || paid > 0 || discount > 0;
}

ShopDay shopDay(Shop shop, Iterable<ShopTx> txs, String day) {
  var before = shop.openingBalance;
  var delivered = 0, returned = 0, paid = 0, discount = 0;
  for (final t in txs) {
    if (t.shopId != shop.id) continue;
    final c = t.day.compareTo(day);
    if (c < 0) {
      before += t.effect;
    } else if (c == 0) {
      switch (t.type) {
        case ShopTxType.delivery:
          delivered += t.amount;
        case ShopTxType.returned:
          returned += t.amount;
        case ShopTxType.payment:
          paid += t.amount;
        case ShopTxType.discount:
          discount += t.amount;
      }
    }
  }
  return ShopDay(
    before: before,
    delivered: delivered,
    returned: returned,
    paid: paid,
    discount: discount,
  );
}

int shopBalance(Shop shop, Iterable<ShopTx> txs) {
  var b = shop.openingBalance;
  for (final t in txs) {
    if (t.shopId == shop.id) b += t.effect;
  }
  return b;
}

/// سطر في كشف الحساب مع الرصيد بعد العملية
class StatementRow<T> {
  StatementRow(this.tx, this.balanceAfter);
  final T tx;
  final int balanceAfter;
}

int _cmpShop(ShopTx a, ShopTx b) {
  final c = a.day.compareTo(b.day);
  return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
}

/// كشف حساب البقالة مرتّباً من الأقدم للأحدث مع الرصيد الجاري
List<StatementRow<ShopTx>> shopStatement(Shop shop, Iterable<ShopTx> txs) {
  final list = txs.where((t) => t.shopId == shop.id).toList()..sort(_cmpShop);
  var bal = shop.openingBalance;
  return [
    for (final t in list) StatementRow(t, bal += t.effect),
  ];
}

/// آخر يوم تحصيل للبقالة (لمعرفة من تأخر في السداد)
String? lastPaymentDay(String shopId, Iterable<ShopTx> txs) {
  String? last;
  for (final t in txs) {
    if (t.shopId != shopId || t.type != ShopTxType.payment) continue;
    if (last == null || t.day.compareTo(last) > 0) last = t.day;
  }
  return last;
}

// ------------------------------------------------------------------ التاجر

int traderBalance(Trader trader, Iterable<TraderTx> txs) {
  var b = trader.openingBalance;
  for (final t in txs) {
    if (t.traderId == trader.id) b += t.effect;
  }
  return b;
}

List<StatementRow<TraderTx>> traderStatement(
  Trader trader,
  Iterable<TraderTx> txs,
) {
  final list = txs.where((t) => t.traderId == trader.id).toList()
    ..sort((a, b) {
      final c = a.day.compareTo(b.day);
      return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
    });
  var bal = trader.openingBalance;
  return [
    for (final t in list) StatementRow(t, bal += t.effect),
  ];
}

// ------------------------------------------------------------------ البضاعة في السيارة

class StockRow {
  StockRow(this.productId, this.name, this.unit);
  final String productId;
  final String name;
  final String unit;
  double picked = 0;
  double delivered = 0;
  double shopReturns = 0;
  double traderReturns = 0;

  /// المفروض يكون معك الآن في السيارة
  double get onHand => picked - delivered + shopReturns - traderReturns;
}

/// حركة البضاعة في يوم: ما استلمته من التاجر مقابل ما وزّعته
List<StockRow> dayStock(
  String day,
  Iterable<ShopTx> shopTxs,
  Iterable<TraderTx> traderTxs,
  List<Product> products,
) {
  final rows = <String, StockRow>{};
  StockRow row(TxLine l) => rows.putIfAbsent(
        l.productId,
        () => StockRow(l.productId, l.name, l.unit),
      );

  for (final t in traderTxs) {
    if (t.day != day) continue;
    for (final l in t.lines) {
      if (t.type == TraderTxType.pickup) row(l).picked += l.qty;
      if (t.type == TraderTxType.returned) row(l).traderReturns += l.qty;
    }
  }
  for (final t in shopTxs) {
    if (t.day != day) continue;
    for (final l in t.lines) {
      if (t.type == ShopTxType.delivery) row(l).delivered += l.qty;
      if (t.type == ShopTxType.returned) row(l).shopReturns += l.qty;
    }
  }
  final order = {for (var i = 0; i < products.length; i++) products[i].id: i};
  return rows.values.toList()
    ..sort((a, b) =>
        (order[a.productId] ?? 999).compareTo(order[b.productId] ?? 999));
}

// ------------------------------------------------------------------ التقارير

class ProductStat {
  ProductStat(this.name, this.unit);
  final String name;
  final String unit;
  double qty = 0;
  int sales = 0;
  int profit = 0;
}

class ShopStat {
  ShopStat(this.shop);
  final Shop shop;
  int delivered = 0;
  int returned = 0;
  int paid = 0;
  int get net => delivered - returned;
}

class PeriodReport {
  int delivered = 0; // إجمالي العطاء
  int returned = 0; // المرتجعات من البقالات
  int discounts = 0;
  int collected = 0; // المحصل
  int costOfSold = 0; // تكلفة ما بيع (بسعر الشراء)
  int expenses = 0;
  int traderPickups = 0;
  int traderReturns = 0;
  int traderPaid = 0;
  final Map<String, ProductStat> products = {};
  final Map<String, ShopStat> shops = {};
  final Map<String, int> expensesByCategory = {};
  final Map<String, int> dailySales = {};

  int get netSales => delivered - returned - discounts;
  int get grossProfit => netSales - costOfSold;
  int get netProfit => grossProfit - expenses;

  /// النقد الذي في يدك من حركة الفترة = محصّل − مدفوع للتاجر − مصاريف
  int get cashFlow => collected - traderPaid - expenses;
}

PeriodReport buildReport({
  required String from,
  required String to,
  required List<Shop> shops,
  required Iterable<ShopTx> shopTxs,
  required Iterable<TraderTx> traderTxs,
  required Iterable<Expense> expenses,
}) {
  bool inRange(String d) => d.compareTo(from) >= 0 && d.compareTo(to) <= 0;
  final r = PeriodReport();
  final shopById = {for (final s in shops) s.id: s};

  for (final t in shopTxs) {
    if (!inRange(t.day)) continue;
    final shop = shopById[t.shopId];
    final ss = shop == null ? null : r.shops.putIfAbsent(shop.id, () => ShopStat(shop));
    switch (t.type) {
      case ShopTxType.delivery:
        r.delivered += t.amount;
        ss?.delivered += t.amount;
        r.dailySales[t.day] = (r.dailySales[t.day] ?? 0) + t.amount;
        for (final l in t.lines) {
          r.costOfSold += l.totalCost;
          final p = r.products.putIfAbsent(l.productId, () => ProductStat(l.name, l.unit));
          p.qty += l.qty;
          p.sales += l.total;
          p.profit += l.total - l.totalCost;
        }
      case ShopTxType.returned:
        r.returned += t.amount;
        ss?.returned += t.amount;
        r.dailySales[t.day] = (r.dailySales[t.day] ?? 0) - t.amount;
        for (final l in t.lines) {
          r.costOfSold -= l.totalCost;
          final p = r.products.putIfAbsent(l.productId, () => ProductStat(l.name, l.unit));
          p.qty -= l.qty;
          p.sales -= l.total;
          p.profit -= l.total - l.totalCost;
        }
      case ShopTxType.payment:
        r.collected += t.amount;
        ss?.paid += t.amount;
      case ShopTxType.discount:
        r.discounts += t.amount;
    }
  }
  for (final t in traderTxs) {
    if (!inRange(t.day)) continue;
    switch (t.type) {
      case TraderTxType.pickup:
        r.traderPickups += t.amount;
      case TraderTxType.returned:
        r.traderReturns += t.amount;
      case TraderTxType.payment:
        r.traderPaid += t.amount;
    }
  }
  for (final e in expenses) {
    if (!inRange(e.day)) continue;
    r.expenses += e.amount;
    r.expensesByCategory[e.category] = (r.expensesByCategory[e.category] ?? 0) + e.amount;
  }
  return r;
}
