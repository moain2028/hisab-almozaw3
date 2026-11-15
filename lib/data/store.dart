import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../models/models.dart';
import 'ledger.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();
int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// المخزن الوحيد للتطبيق: يحمّل كل البيانات في الذاكرة من Hive،
/// ويحفظ كل تعديل فوراً، ويُبلغ الواجهات بالتغيير (Provider).
class Store extends ChangeNotifier {
  static const _boxes = [
    'shops',
    'products',
    'traders',
    'shop_txs',
    'trader_txs',
    'expenses',
    'meta',
  ];

  late Box _shopsBox, _productsBox, _tradersBox, _shopTxBox, _traderTxBox, _expBox, _meta;

  final Map<String, Shop> _shops = {};
  final Map<String, Product> _products = {};
  final Map<String, Trader> _traders = {};
  final Map<String, ShopTx> _shopTxs = {};
  final Map<String, TraderTx> _traderTxs = {};
  final Map<String, Expense> _expenses = {};

  bool ready = false;

  /// اليوم التجاري المعروض في الشاشات (افتراضياً اليوم)
  String _day = todayKey();
  String get day => _day;
  bool get isToday => _day == todayKey();
  void setDay(String d) {
    if (d.compareTo(todayKey()) > 0) return;
    _day = d;
    notifyListeners();
  }

  Future<void> init() async {
    await Hive.initFlutter();
    final opened = <Box>[];
    for (final name in _boxes) {
      opened.add(await Hive.openBox(name));
    }
    _shopsBox = opened[0];
    _productsBox = opened[1];
    _tradersBox = opened[2];
    _shopTxBox = opened[3];
    _traderTxBox = opened[4];
    _expBox = opened[5];
    _meta = opened[6];
    _loadAll();
    if (_traders.isEmpty) {
      final t = Trader(id: newId(), name: 'التاجر');
      _traders[t.id] = t;
      await _tradersBox.put(t.id, t.toMap());
    }
    ready = true;
    notifyListeners();
  }

  void _loadAll() {
    _shops
      ..clear()
      ..addEntries(_shopsBox.values.map((m) {
        final s = Shop.fromMap(m as Map);
        return MapEntry(s.id, s);
      }));
    _products
      ..clear()
      ..addEntries(_productsBox.values.map((m) {
        final p = Product.fromMap(m as Map);
        return MapEntry(p.id, p);
      }));
    _traders
      ..clear()
      ..addEntries(_tradersBox.values.map((m) {
        final t = Trader.fromMap(m as Map);
        return MapEntry(t.id, t);
      }));
    _shopTxs
      ..clear()
      ..addEntries(_shopTxBox.values.map((m) {
        final t = ShopTx.fromMap(m as Map);
        return MapEntry(t.id, t);
      }));
    _traderTxs
      ..clear()
      ..addEntries(_traderTxBox.values.map((m) {
        final t = TraderTx.fromMap(m as Map);
        return MapEntry(t.id, t);
      }));
    _expenses
      ..clear()
      ..addEntries(_expBox.values.map((m) {
        final e = Expense.fromMap(m as Map);
        return MapEntry(e.id, e);
      }));
  }

  // ================================================================ إعدادات بسيطة

  String get currency => (_meta.get('currency') as String?) ?? 'ريال';
  String get distributorName => (_meta.get('distributorName') as String?) ?? '';
  int get themeMode => (_meta.get('themeMode') as int?) ?? 0; // 0 تلقائي 1 فاتح 2 داكن
  double get textScale => ((_meta.get('textScale') as num?) ?? 1.0).toDouble();
  int get lastBackup => (_meta.get('lastBackup') as int?) ?? 0;

  Future<void> setMeta(String key, Object? value) async {
    await _meta.put(key, value);
    notifyListeners();
  }

  // ================================================================ البقالات

  /// البقالات النشطة بترتيب خط السير
  List<Shop> get shops {
    final l = _shops.values.where((s) => !s.archived).toList()
      ..sort((a, b) {
        final c = a.routeOrder.compareTo(b.routeOrder);
        return c != 0 ? c : a.name.compareTo(b.name);
      });
    return l;
  }

  List<Shop> get archivedShops =>
      _shops.values.where((s) => s.archived).toList()..sort((a, b) => a.name.compareTo(b.name));

  Shop? shop(String id) => _shops[id];

  Future<Shop> saveShop(Shop s) async {
    _shops[s.id] = s;
    await _shopsBox.put(s.id, s.toMap());
    notifyListeners();
    return s;
  }

  Future<Shop> addShop({
    required String name,
    String owner = '',
    String phone = '',
    String area = '',
    int openingBalance = 0,
  }) {
    final maxOrder = _shops.values.fold<int>(0, (m, s) => s.routeOrder > m ? s.routeOrder : m);
    return saveShop(Shop(
      id: newId(),
      name: name,
      owner: owner,
      phone: phone,
      area: area,
      openingBalance: openingBalance,
      routeOrder: maxOrder + 1,
      createdAt: nowMs(),
    ));
  }

  Future<void> reorderShops(List<Shop> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].routeOrder = i + 1;
      await _shopsBox.put(ordered[i].id, ordered[i].toMap());
    }
    notifyListeners();
  }

  /// حذف نهائي للبقالة مع كل حركاتها
  Future<void> deleteShop(String id) async {
    final ids = _shopTxs.values.where((t) => t.shopId == id).map((t) => t.id).toList();
    for (final t in ids) {
      _shopTxs.remove(t);
    }
    await _shopTxBox.deleteAll(ids);
    _shops.remove(id);
    await _shopsBox.delete(id);
    notifyListeners();
  }

  // ================================================================ الأصناف

  List<Product> get allProducts => _products.values.toList()
    ..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.name.compareTo(b.name);
    });

  List<Product> get products => allProducts.where((p) => p.active).toList();

  Product? product(String id) => _products[id];

  Future<void> saveProduct(Product p) async {
    _products[p.id] = p;
    await _productsBox.put(p.id, p.toMap());
    notifyListeners();
  }

  Future<void> addProduct(String name, String unit, int sell, int cost) {
    final maxOrder = _products.values.fold<int>(0, (m, p) => p.sortOrder > m ? p.sortOrder : m);
    return saveProduct(Product(
      id: newId(),
      name: name,
      unit: unit,
      sellPrice: sell,
      costPrice: cost,
      sortOrder: maxOrder + 1,
    ));
  }

  Future<void> reorderProducts(List<Product> ordered) async {
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].sortOrder = i + 1;
      await _productsBox.put(ordered[i].id, ordered[i].toMap());
    }
    notifyListeners();
  }

  /// الصنف المستخدم في عمليات سابقة لا يُحذف، بل يُخفى
  Future<void> removeProduct(Product p) async {
    final used = _shopTxs.values.any((t) => t.lines.any((l) => l.productId == p.id)) ||
        _traderTxs.values.any((t) => t.lines.any((l) => l.productId == p.id));
    if (used) {
      p.active = false;
      await saveProduct(p);
    } else {
      _products.remove(p.id);
      await _productsBox.delete(p.id);
      notifyListeners();
    }
  }

  // ================================================================ التاجر

  List<Trader> get traders =>
      _traders.values.where((t) => !t.archived).toList()..sort((a, b) => a.name.compareTo(b.name));
  Trader get mainTrader => traders.isNotEmpty ? traders.first : _traders.values.first;
  Trader? trader(String id) => _traders[id];

  Future<void> saveTrader(Trader t) async {
    _traders[t.id] = t;
    await _tradersBox.put(t.id, t.toMap());
    notifyListeners();
  }

  Future<void> addTrader(String name, String phone) =>
      saveTrader(Trader(id: newId(), name: name, phone: phone));

  // ================================================================ حركات البقالات

  Iterable<ShopTx> get shopTxs => _shopTxs.values;

  List<ShopTx> shopTxsOf(String shopId, {String? day}) => _shopTxs.values
      .where((t) => t.shopId == shopId && (day == null || t.day == day))
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Future<void> saveShopTx(ShopTx t) async {
    _shopTxs[t.id] = t;
    await _shopTxBox.put(t.id, t.toMap());
    notifyListeners();
  }

  Future<void> deleteShopTx(String id) async {
    _shopTxs.remove(id);
    await _shopTxBox.delete(id);
    notifyListeners();
  }

  Future<void> addPayment(String shopId, String day, int amount, {String note = ''}) =>
      saveShopTx(ShopTx(
        id: newId(),
        shopId: shopId,
        type: ShopTxType.payment,
        day: day,
        createdAt: nowMs(),
        amount: amount,
        note: note,
      ));

  // ================================================================ حركات التاجر

  Iterable<TraderTx> get traderTxs => _traderTxs.values;

  List<TraderTx> traderTxsOf(String traderId, {String? day}) => _traderTxs.values
      .where((t) => t.traderId == traderId && (day == null || t.day == day))
      .toList()
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

  Future<void> saveTraderTx(TraderTx t) async {
    _traderTxs[t.id] = t;
    await _traderTxBox.put(t.id, t.toMap());
    notifyListeners();
  }

  Future<void> deleteTraderTx(String id) async {
    _traderTxs.remove(id);
    await _traderTxBox.delete(id);
    notifyListeners();
  }

  // ================================================================ المصاريف

  List<Expense> expensesOf({String? day}) => _expenses.values
      .where((e) => day == null || e.day == day)
      .toList()
    ..sort((a, b) {
      final c = b.day.compareTo(a.day);
      return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
    });

  Iterable<Expense> get expenses => _expenses.values;

  Future<void> addExpense(String day, int amount, String category, String note) async {
    final e = Expense(
      id: newId(),
      day: day,
      amount: amount,
      category: category,
      note: note,
      createdAt: nowMs(),
    );
    _expenses[e.id] = e;
    await _expBox.put(e.id, e.toMap());
    notifyListeners();
  }

  Future<void> deleteExpense(String id) async {
    _expenses.remove(id);
    await _expBox.delete(id);
    notifyListeners();
  }

  // ================================================================ حسابات جاهزة للواجهة

  int balanceOf(Shop s) => shopBalance(s, _shopTxs.values);
  ShopDay dayOf(Shop s, [String? d]) => shopDay(s, _shopTxs.values, d ?? _day);
  int traderBalanceOf(Trader t) => traderBalance(t, _traderTxs.values);

  /// مجموع المتبقي عند كل البقالات الآن
  int get totalOwed => shops.fold(0, (a, s) => a + balanceOf(s));

  /// مجموع ما عليك لكل التجار الآن
  int get totalToTraders => traders.fold(0, (a, t) => a + traderBalanceOf(t));

  /// ملخص يوم كامل
  DaySummary summary([String? d]) {
    final k = d ?? _day;
    final s = DaySummary();
    for (final t in _shopTxs.values) {
      if (t.day != k || !_shops.containsKey(t.shopId)) continue;
      switch (t.type) {
        case ShopTxType.delivery:
          s.delivered += t.amount;
          s.deliveredShops.add(t.shopId);
        case ShopTxType.returned:
          s.returned += t.amount;
        case ShopTxType.payment:
          s.collected += t.amount;
          s.paidShops.add(t.shopId);
        case ShopTxType.discount:
          s.discount += t.amount;
      }
    }
    for (final t in _traderTxs.values) {
      if (t.day != k) continue;
      switch (t.type) {
        case TraderTxType.pickup:
          s.picked += t.amount;
        case TraderTxType.returned:
          s.traderReturned += t.amount;
        case TraderTxType.payment:
          s.traderPaid += t.amount;
      }
    }
    for (final e in _expenses.values) {
      if (e.day == k) s.expenses += e.amount;
    }
    for (final shop in shops) {
      s.remainingEndOfDay += dayOf(shop, k).remaining;
    }
    return s;
  }

  List<StockRow> stockOf([String? d]) =>
      dayStock(d ?? _day, _shopTxs.values, _traderTxs.values, allProducts);

  PeriodReport report(String from, String to) => buildReport(
        from: from,
        to: to,
        shops: _shops.values.toList(),
        shopTxs: _shopTxs.values,
        traderTxs: _traderTxs.values,
        expenses: _expenses.values,
      );

  // ================================================================ النسخ الاحتياطي

  String exportJson() {
    final doc = {
      'app': 'hisab_almozaw3',
      'version': 2,
      'createdAt': DateTime.now().toIso8601String(),
      'shops': [for (final s in _shops.values) s.toMap()],
      'products': [for (final p in _products.values) p.toMap()],
      'traders': [for (final t in _traders.values) t.toMap()],
      'shopTxs': [for (final t in _shopTxs.values) t.toMap()],
      'traderTxs': [for (final t in _traderTxs.values) t.toMap()],
      'expenses': [for (final e in _expenses.values) e.toMap()],
    };
    return jsonEncode(doc);
  }

  Future<void> markBackup() => setMeta('lastBackup', nowMs());

  /// يرجع عدد السجلات المستوردة. replace=true يمسح البيانات الحالية أولاً
  Future<int> importJson(String text, {required bool replace}) async {
    final doc = jsonDecode(text.trim());
    if (doc is! Map || doc['app'] != 'hisab_almozaw3') {
      throw const FormatException('هذا ليس ملف نسخة احتياطية من حساب الموزع');
    }
    if (replace) await _clearData();
    var n = 0;
    Future<void> put(Box box, String key, Map<String, Object?> Function(Map) conv) async {
      for (final m in (doc[key] as List?) ?? const []) {
        final map = conv(m as Map);
        await box.put(map['id'], map);
        n++;
      }
    }

    await put(_shopsBox, 'shops', (m) => Shop.fromMap(m).toMap());
    await put(_productsBox, 'products', (m) => Product.fromMap(m).toMap());
    await put(_tradersBox, 'traders', (m) => Trader.fromMap(m).toMap());
    await put(_shopTxBox, 'shopTxs', (m) => ShopTx.fromMap(m).toMap());
    await put(_traderTxBox, 'traderTxs', (m) => TraderTx.fromMap(m).toMap());
    await put(_expBox, 'expenses', (m) => Expense.fromMap(m).toMap());
    _loadAll();
    notifyListeners();
    return n;
  }

  Future<void> _clearData() async {
    for (final b in [_shopsBox, _productsBox, _tradersBox, _shopTxBox, _traderTxBox, _expBox]) {
      await b.clear();
    }
    _loadAll();
  }

  Future<void> wipeAll() async {
    await _clearData();
    final t = Trader(id: newId(), name: 'التاجر');
    await saveTrader(t);
    notifyListeners();
  }

  // ================================================================ بيانات تجريبية

  bool get isEmpty => _shops.isEmpty && _products.isEmpty;

  Future<void> addStarterProducts() async {
    const items = [
      ('زبادي', 'كرتون', 2200, 1900),
      ('حقين', 'كرتون', 1800, 1550),
      ('لبن', 'كرتون', 2000, 1700),
      ('جبن', 'كرتون', 3500, 3100),
    ];
    for (final i in items) {
      await addProduct(i.$1, i.$2, i.$3, i.$4);
    }
  }

  /// يملأ التطبيق ببيانات أسبوع لتجربة البرنامج
  Future<void> loadDemo() async {
    await _clearData();
    final trader = Trader(id: newId(), name: 'مؤسسة الألبان', phone: '');
    await saveTrader(trader);
    await addStarterProducts();
    final prods = products;
    const names = [
      ('بقالة الأمانة', 'أبو محمد', 'الحي الشرقي', 0),
      ('سوبرماركت النور', 'عبدالله', 'الحي الشرقي', 4000),
      ('بقالة الخير', 'سالم', 'شارع السوق', 0),
      ('تموينات البركة', 'أحمد', 'شارع السوق', 0),
      ('بقالة السعادة', 'خالد', 'الحي الغربي', 2500),
      ('بقالة الوفاء', 'ناصر', 'الحي الغربي', 0),
    ];
    final created = <Shop>[];
    for (final n in names) {
      created.add(await addShop(name: n.$1, owner: n.$2, area: n.$3, openingBalance: n.$4));
    }
    final today = todayKey();
    var seed = 7;
    int rnd(int m) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      return seed % m;
    }

    for (var back = 6; back >= 0; back--) {
      final d = shiftDay(today, -back);
      var created0 = DateTime.now().millisecondsSinceEpoch - back * 86400000 - 50000000;
      final pickupLines = <String, double>{};
      final dayDeliveries = <String, List<TxLine>>{};
      for (final s in created) {
        if (rnd(10) < 2) continue; // بعض الأيام بدون توزيع
        final lines = <TxLine>[];
        for (final p in prods) {
          if (rnd(10) < 4) continue;
          const qs = [0.5, 1.0, 1.5, 2.0, 3.0, 0.25, 1.0, 2.5];
          final q = qs[rnd(qs.length)];
          lines.add(TxLine(
            productId: p.id,
            name: p.name,
            unit: p.unit,
            qty: q,
            price: p.sellPrice,
            cost: p.costPrice,
          ));
          pickupLines[p.id] = (pickupLines[p.id] ?? 0) + q;
        }
        if (lines.isNotEmpty) dayDeliveries[s.id] = lines;
      }
      await saveTraderTx(TraderTx(
        id: newId(),
        traderId: trader.id,
        type: TraderTxType.pickup,
        day: d,
        createdAt: created0,
        lines: [
          for (final p in prods)
            if (pickupLines[p.id] != null)
              TxLine(
                productId: p.id,
                name: p.name,
                unit: p.unit,
                qty: pickupLines[p.id]! + 1,
                price: p.costPrice,
                cost: p.costPrice,
              ),
        ],
      ));
      for (final e in dayDeliveries.entries) {
        created0 += 600000;
        await saveShopTx(ShopTx(
          id: newId(),
          shopId: e.key,
          type: ShopTxType.delivery,
          day: d,
          createdAt: created0,
          lines: e.value,
        ));
      }
      if (back == 0) continue; // اليوم: لم يتم التحصيل بعد
      for (final s in created) {
        final due = dayOf(s, d).due;
        if (due <= 0 || rnd(10) < 2) continue;
        final pay = rnd(3) == 0 ? (due * 0.6).round() ~/ 100 * 100 : due;
        created0 += 300000;
        await saveShopTx(ShopTx(
          id: newId(),
          shopId: s.id,
          type: ShopTxType.payment,
          day: d,
          createdAt: created0 + 40000000,
          amount: pay,
        ));
      }
      final owe = traderBalanceOf(trader);
      final yesterdayPickup = traderTxsOf(trader.id, day: shiftDay(d, -1))
          .where((t) => t.type == TraderTxType.pickup)
          .fold(0, (a, t) => a + t.amount);
      if (yesterdayPickup > 0 && owe > 0) {
        await saveTraderTx(TraderTx(
          id: newId(),
          traderId: trader.id,
          type: TraderTxType.payment,
          day: d,
          createdAt: created0 - 1000,
          amount: yesterdayPickup > owe ? owe : yesterdayPickup,
        ));
      }
      if (rnd(2) == 0) {
        await addExpense(d, 1500 + rnd(3) * 500, 'بنزين', '');
      }
    }
    if (kDebugMode) debugPrint('demo loaded');
  }
}

class DaySummary {
  int picked = 0;
  int traderReturned = 0;
  int traderPaid = 0;
  int delivered = 0;
  int returned = 0;
  int discount = 0;
  int collected = 0;
  int expenses = 0;
  int remainingEndOfDay = 0;
  final Set<String> deliveredShops = {};
  final Set<String> paidShops = {};
}
