import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import '../models/models.dart';
import 'demo_data.dart';
import 'ledger.dart';
import 'ledger_index.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();
int nowMs() => DateTime.now().millisecondsSinceEpoch;

/// صيغة ملف البيانات (تُرفع عند أي تغيير غير متوافق في البنية)
const kSchemaVersion = 2;
const kAppId = 'hisab_almozaw3';

/// المخزن الوحيد للتطبيق (مصدر الحقيقة).
///
/// التصميم:
/// - **التخزين**: Hive (ملفات append-only محلية، سريعة، تتحمل الانقطاع المفاجئ).
/// - **الذاكرة**: كل السجلات محمّلة في Maps، مع فهارس تزايدية:
///     * حسب البقالة  `_txByShop`   → لإعادة بناء فهرس حساب واحد فقط عند التعديل.
///     * حسب اليوم    `_txByDay`    → ملخص اليوم والتقارير بدون مسح كل البيانات.
/// - **كاش محسوب**: فهرس محاسبي لكل حساب (prefix sums) + ملخص كل يوم + القوائم المرتبة،
///   كلها تُبطَل انتقائياً عند التغيير فقط.
/// - **الإشعار**: `revision` يزيد مع كل تغيير، والواجهات تعيد البناء عبر Provider.
class Store extends ChangeNotifier with WidgetsBindingObserver {
  static const _boxNames = ['shops', 'products', 'traders', 'shop_txs', 'trader_txs', 'expenses', 'meta'];

  late Box _shopsBox, _productsBox, _tradersBox, _shopTxBox, _traderTxBox, _expBox, _meta;

  // ---------------------------------------------------------------- السجلات
  final Map<String, Shop> _shops = {};
  final Map<String, Product> _products = {};
  final Map<String, Trader> _traders = {};
  final Map<String, ShopTx> _shopTxs = {};
  final Map<String, TraderTx> _traderTxs = {};
  final Map<String, Expense> _expenses = {};

  // ---------------------------------------------------------------- فهارس تزايدية
  final Map<String, Map<String, ShopTx>> _txByShop = {};
  final Map<String, Map<String, ShopTx>> _txByDay = {};
  final Map<String, Map<String, TraderTx>> _ttxByTrader = {};
  final Map<String, Map<String, TraderTx>> _ttxByDay = {};

  // ---------------------------------------------------------------- كاش محسوب (يُبطَل انتقائياً)
  final Map<String, AccountIndex<ShopTx>> _shopIdx = {};
  final Map<String, AccountIndex<TraderTx>> _traderIdx = {};
  final Map<String, DaySummary> _summaryCache = {};
  List<Shop>? _shopsSorted;
  List<Product>? _productsSorted;

  bool ready = false;

  /// يزيد مع كل تغيير في البيانات (يُستخدم لمعرفة هل تغيّر شيء منذ آخر نسخة احتياطية)
  int get revision => _revision;
  int _revision = 0;

  /// يُستدعى بعد كل تغيير في البيانات (تستخدمه خدمة النسخ الاحتياطي التلقائي)
  VoidCallback? onDataChanged;

  // ================================================================ اليوم المعروض

  String _day = todayKey();
  String get day => _day;
  bool get isToday => _day == todayKey();
  void setDay(String d) {
    if (d.compareTo(todayKey()) > 0 || d == _day) return;
    _day = d;
    notifyListeners();
  }

  /// عند بقاء التطبيق مفتوحاً بعد منتصف الليل: انتقل لليوم الجديد تلقائياً
  void refreshToday() {
    final t = todayKey();
    if (_day != t && _day == shiftDay(t, -1)) {
      _day = t;
      notifyListeners();
    }
  }

  // ================================================================ التهيئة

  Future<void> init() async {
    await Hive.initFlutter();
    final boxes = await Future.wait([
      for (final n in _boxNames)
        Hive.openBox(
          n,
          // ضغط الملف عندما تتراكم السجلات المحذوفة/المستبدلة (يوفّر المساحة ويسرّع الفتح)
          compactionStrategy: (entries, deleted) => deleted > 200 && deleted > entries ~/ 4,
        ),
    ]);
    _shopsBox = boxes[0];
    _productsBox = boxes[1];
    _tradersBox = boxes[2];
    _shopTxBox = boxes[3];
    _traderTxBox = boxes[4];
    _expBox = boxes[5];
    _meta = boxes[6];
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
      ..addEntries(_shopsBox.values.map((m) => Shop.fromMap(m as Map)).map((s) => MapEntry(s.id, s)));
    _products
      ..clear()
      ..addEntries(_productsBox.values.map((m) => Product.fromMap(m as Map)).map((p) => MapEntry(p.id, p)));
    _traders
      ..clear()
      ..addEntries(_tradersBox.values.map((m) => Trader.fromMap(m as Map)).map((t) => MapEntry(t.id, t)));
    _expenses
      ..clear()
      ..addEntries(_expBox.values.map((m) => Expense.fromMap(m as Map)).map((e) => MapEntry(e.id, e)));

    _shopTxs.clear();
    _txByShop.clear();
    _txByDay.clear();
    for (final m in _shopTxBox.values) {
      _indexShopTx(ShopTx.fromMap(m as Map));
    }
    _traderTxs.clear();
    _ttxByTrader.clear();
    _ttxByDay.clear();
    for (final m in _traderTxBox.values) {
      _indexTraderTx(TraderTx.fromMap(m as Map));
    }
    _invalidateAll();
  }

  // ================================================================ الفهرسة والإبطال

  void _indexShopTx(ShopTx t) {
    _shopTxs[t.id] = t;
    (_txByShop[t.shopId] ??= {})[t.id] = t;
    (_txByDay[t.day] ??= {})[t.id] = t;
  }

  ShopTx? _unindexShopTx(String id) {
    final old = _shopTxs.remove(id);
    if (old != null) {
      _txByShop[old.shopId]?.remove(id);
      _txByDay[old.day]?.remove(id);
    }
    return old;
  }

  void _indexTraderTx(TraderTx t) {
    _traderTxs[t.id] = t;
    (_ttxByTrader[t.traderId] ??= {})[t.id] = t;
    (_ttxByDay[t.day] ??= {})[t.id] = t;
  }

  TraderTx? _unindexTraderTx(String id) {
    final old = _traderTxs.remove(id);
    if (old != null) {
      _ttxByTrader[old.traderId]?.remove(id);
      _ttxByDay[old.day]?.remove(id);
    }
    return old;
  }

  void _invalidateAll() {
    _shopIdx.clear();
    _traderIdx.clear();
    _summaryCache.clear();
    _shopsSorted = null;
    _productsSorted = null;
  }

  /// يعلن تغيّر البيانات: يبطل ملخصات الأيام (رخيصة) ويُخطر الواجهات
  void _changed() {
    _revision++;
    _summaryCache.clear();
    notifyListeners();
    onDataChanged?.call();
  }

  // ================================================================ إعدادات

  String get currency => (_meta.get('currency') as String?) ?? 'ريال';
  String get distributorName => (_meta.get('distributorName') as String?) ?? '';
  int get themeMode => (_meta.get('themeMode') as int?) ?? 0;
  double get textScale => ((_meta.get('textScale') as num?) ?? 1.0).toDouble();
  bool get haptics => (_meta.get('haptics') as bool?) ?? true;
  bool get autoBackup => (_meta.get('autoBackup') as bool?) ?? true;
  int get lastBackup => (_meta.get('lastBackup') as int?) ?? 0;
  int get lastBackupRevision => (_meta.get('lastBackupRevision') as int?) ?? -1;
  bool get onboarded => (_meta.get('onboarded') as bool?) ?? false;

  T? meta<T>(String key) => _meta.get(key) as T?;

  Future<void> setMeta(String key, Object? value) async {
    await _meta.put(key, value);
    notifyListeners();
  }

  /// يسجّل وقت آخر نسخة احتياطية ومرجع البيانات وقتها (لتجنب نسخ مكرر بلا تغيير)
  Future<void> markBackup() async {
    await _meta.putAll({'lastBackup': nowMs(), 'lastBackupRevision': _persistentRevision});
    notifyListeners();
  }

  /// مرجع ثابت عبر إعادة التشغيل: عدد السجلات + آخر تعديل
  int get _persistentRevision => Object.hash(
    _shops.length,
    _shopTxs.length,
    _traderTxs.length,
    _expenses.length,
    _products.length,
    _meta.get('dataStamp'),
  );

  bool get hasUnbackedChanges => lastBackupRevision != _persistentRevision;

  Future<void> _stamp() => _meta.put('dataStamp', nowMs());

  // ================================================================ البقالات

  /// البقالات النشطة بترتيب خط السير (مخزّنة مؤقتاً)
  List<Shop> get shops => _shopsSorted ??= (_shops.values.where((s) => !s.archived).toList()
    ..sort((a, b) {
      final c = a.routeOrder.compareTo(b.routeOrder);
      return c != 0 ? c : a.name.compareTo(b.name);
    }));

  List<Shop> get archivedShops =>
      _shops.values.where((s) => s.archived).toList()..sort((a, b) => a.name.compareTo(b.name));

  Shop? shop(String id) => _shops[id];

  Future<Shop> saveShop(Shop s) async {
    final old = _shops[s.id];
    _shops[s.id] = s;
    _shopsSorted = null;
    if (old == null || old.openingBalance != s.openingBalance) _shopIdx.remove(s.id);
    _changed();
    await _shopsBox.put(s.id, s.toMap());
    await _stamp();
    return s;
  }

  Future<Shop> addShop({
    required String name,
    String owner = '',
    String phone = '',
    String area = '',
    String notes = '',
    int openingBalance = 0,
  }) {
    final maxOrder = _shops.values.fold<int>(0, (m, s) => s.routeOrder > m ? s.routeOrder : m);
    return saveShop(
      Shop(
        id: newId(),
        name: name,
        owner: owner,
        phone: phone,
        area: area,
        notes: notes,
        openingBalance: openingBalance,
        routeOrder: maxOrder + 1,
        createdAt: nowMs(),
      ),
    );
  }

  Future<void> reorderShops(List<Shop> ordered) async {
    final batch = <String, Map<String, Object?>>{};
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].routeOrder = i + 1;
      batch[ordered[i].id] = ordered[i].toMap();
    }
    _shopsSorted = null;
    _changed();
    await _shopsBox.putAll(batch);
  }

  /// حذف نهائي للبقالة مع كل حركاتها. يُرجع ما حُذف لإمكانية التراجع.
  Future<(Shop, List<ShopTx>)?> deleteShop(String id) async {
    final shop = _shops.remove(id);
    if (shop == null) return null;
    final txs = (_txByShop.remove(id) ?? {}).values.toList();
    for (final t in txs) {
      _shopTxs.remove(t.id);
      _txByDay[t.day]?.remove(t.id);
    }
    _shopIdx.remove(id);
    _shopsSorted = null;
    _changed();
    await _shopTxBox.deleteAll(txs.map((t) => t.id));
    await _shopsBox.delete(id);
    await _stamp();
    return (shop, txs);
  }

  Future<void> restoreShop(Shop s, List<ShopTx> txs) async {
    _shops[s.id] = s;
    for (final t in txs) {
      _indexShopTx(t);
    }
    _shopIdx.remove(s.id);
    _shopsSorted = null;
    _changed();
    await _shopsBox.put(s.id, s.toMap());
    await _shopTxBox.putAll({for (final t in txs) t.id: t.toMap()});
  }

  // ================================================================ الأصناف

  List<Product> get allProducts => _productsSorted ??= (_products.values.toList()
    ..sort((a, b) {
      final c = a.sortOrder.compareTo(b.sortOrder);
      return c != 0 ? c : a.name.compareTo(b.name);
    }));

  List<Product> get products => allProducts.where((p) => p.active).toList();

  Product? product(String id) => _products[id];

  Future<void> saveProduct(Product p) async {
    _products[p.id] = p;
    _productsSorted = null;
    _changed();
    await _productsBox.put(p.id, p.toMap());
    await _stamp();
  }

  Future<void> addProduct(String name, String unit, int sell, int cost) {
    final maxOrder = _products.values.fold<int>(0, (m, p) => p.sortOrder > m ? p.sortOrder : m);
    return saveProduct(
      Product(id: newId(), name: name, unit: unit, sellPrice: sell, costPrice: cost, sortOrder: maxOrder + 1),
    );
  }

  Future<void> reorderProducts(List<Product> ordered) async {
    final batch = <String, Map<String, Object?>>{};
    for (var i = 0; i < ordered.length; i++) {
      ordered[i].sortOrder = i + 1;
      batch[ordered[i].id] = ordered[i].toMap();
    }
    _productsSorted = null;
    _changed();
    await _productsBox.putAll(batch);
  }

  /// الصنف المستخدم في عمليات سابقة لا يُحذف بل يُخفى (حتى تبقى الحسابات القديمة سليمة)
  Future<void> removeProduct(Product p) async {
    final used =
        _shopTxs.values.any((t) => t.lines.any((l) => l.productId == p.id)) ||
        _traderTxs.values.any((t) => t.lines.any((l) => l.productId == p.id));
    if (used) {
      p.active = false;
      await saveProduct(p);
    } else {
      _products.remove(p.id);
      _productsSorted = null;
      _changed();
      await _productsBox.delete(p.id);
    }
  }

  // ================================================================ التاجر

  List<Trader> get traders =>
      _traders.values.where((t) => !t.archived).toList()..sort((a, b) => a.name.compareTo(b.name));
  Trader get mainTrader => traders.isNotEmpty ? traders.first : _traders.values.first;
  Trader? trader(String id) => _traders[id];

  Future<void> saveTrader(Trader t) async {
    _traders[t.id] = t;
    _traderIdx.remove(t.id);
    _changed();
    await _tradersBox.put(t.id, t.toMap());
    await _stamp();
  }

  // ================================================================ حركات البقالات

  Iterable<ShopTx> get shopTxs => _shopTxs.values;

  /// حركات بقالة (مرتبة) — اختيارياً ليوم واحد
  List<ShopTx> shopTxsOf(String shopId, {String? day}) {
    final s = _shops[shopId];
    if (s == null) return const [];
    final idx = shopIndex(s);
    return day == null ? idx.entries : idx.on(day);
  }

  Future<void> saveShopTx(ShopTx t) async {
    final old = _unindexShopTx(t.id);
    _indexShopTx(t);
    _shopIdx.remove(t.shopId);
    if (old != null && old.shopId != t.shopId) _shopIdx.remove(old.shopId);
    _changed();
    await _shopTxBox.put(t.id, t.toMap());
    await _stamp();
  }

  /// يحذف ويُرجع الحركة المحذوفة (لزر "تراجع")
  Future<ShopTx?> deleteShopTx(String id) async {
    final old = _unindexShopTx(id);
    if (old == null) return null;
    _shopIdx.remove(old.shopId);
    _changed();
    await _shopTxBox.delete(id);
    await _stamp();
    return old;
  }

  Future<void> addPayment(String shopId, String day, int amount, {String note = ''}) => saveShopTx(
    ShopTx(
      id: newId(),
      shopId: shopId,
      type: ShopTxType.payment,
      day: day,
      createdAt: nowMs(),
      amount: amount,
      note: note,
    ),
  );

  // ================================================================ حركات التاجر

  Iterable<TraderTx> get traderTxs => _traderTxs.values;

  List<TraderTx> traderTxsOf(String traderId, {String? day}) {
    final t = _traders[traderId];
    if (t == null) return const [];
    final idx = traderIndex(t);
    return day == null ? idx.entries : idx.on(day);
  }

  /// آخر استلام قبل يوم معيّن (لتعبئة كميات الاستلام تلقائياً)
  TraderTx? lastPickupBefore(String traderId, String day) {
    final t = _traders[traderId];
    if (t == null) return null;
    final idx = traderIndex(t);
    for (var i = idx.lowerBound(day) - 1; i >= 0; i--) {
      if (idx.entries[i].type == TraderTxType.pickup) return idx.entries[i];
    }
    return null;
  }

  Future<void> saveTraderTx(TraderTx t) async {
    final old = _unindexTraderTx(t.id);
    _indexTraderTx(t);
    _traderIdx.remove(t.traderId);
    if (old != null && old.traderId != t.traderId) _traderIdx.remove(old.traderId);
    _changed();
    await _traderTxBox.put(t.id, t.toMap());
    await _stamp();
  }

  Future<TraderTx?> deleteTraderTx(String id) async {
    final old = _unindexTraderTx(id);
    if (old == null) return null;
    _traderIdx.remove(old.traderId);
    _changed();
    await _traderTxBox.delete(id);
    await _stamp();
    return old;
  }

  // ================================================================ المصاريف

  List<Expense> expensesOf({String? day, String? from, String? to}) =>
      _expenses.values
          .where(
            (e) =>
                (day == null || e.day == day) &&
                (from == null || e.day.compareTo(from) >= 0) &&
                (to == null || e.day.compareTo(to) <= 0),
          )
          .toList()
        ..sort((a, b) {
          final c = b.day.compareTo(a.day);
          return c != 0 ? c : b.createdAt.compareTo(a.createdAt);
        });

  Iterable<Expense> get expenses => _expenses.values;

  Future<void> addExpense(String day, int amount, String category, String note) =>
      saveExpense(Expense(id: newId(), day: day, amount: amount, category: category, note: note, createdAt: nowMs()));

  Future<void> saveExpense(Expense e) async {
    _expenses[e.id] = e;
    _changed();
    await _expBox.put(e.id, e.toMap());
    await _stamp();
  }

  Future<Expense?> deleteExpense(String id) async {
    final old = _expenses.remove(id);
    _changed();
    await _expBox.delete(id);
    await _stamp();
    return old;
  }

  // ================================================================ الحسابات (من الكاش)

  /// فهرس حساب البقالة: يُبنى عند أول طلب ويبقى حتى تتغير حركاتها
  AccountIndex<ShopTx> shopIndex(Shop s) =>
      _shopIdx[s.id] ??= AccountIndex.build(s.openingBalance, (_txByShop[s.id] ?? const {}).values);

  AccountIndex<TraderTx> traderIndex(Trader t) =>
      _traderIdx[t.id] ??= AccountIndex.build(t.openingBalance, (_ttxByTrader[t.id] ?? const {}).values);

  int balanceOf(Shop s) => shopIndex(s).balance;
  ShopDay dayOf(Shop s, [String? d]) => shopDayFromIndex(shopIndex(s), d ?? _day);
  String? lastPaymentOf(Shop s) => lastPaymentFromIndex(shopIndex(s));
  int traderBalanceOf(Trader t) => traderIndex(t).balance;

  int get totalOwed => shops.fold(0, (a, s) => a + balanceOf(s));
  int get totalToTraders => traders.fold(0, (a, t) => a + traderBalanceOf(t));

  /// ملخص يوم كامل (مخزّن مؤقتاً لكل يوم حتى يحدث تغيير)
  DaySummary summary([String? d]) {
    final k = d ?? _day;
    return _summaryCache[k] ??= _buildSummary(k);
  }

  DaySummary _buildSummary(String k) {
    final s = DaySummary();
    for (final t in (_txByDay[k] ?? const {}).values) {
      final shop = _shops[t.shopId];
      if (shop == null || shop.archived) continue;
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
    for (final t in (_ttxByDay[k] ?? const {}).values) {
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
      s.remainingEndOfDay += shopIndex(shop).balanceAtEndOf(k);
    }
    return s;
  }

  List<StockRow> stockOf([String? d]) {
    final k = d ?? _day;
    return dayStock(k, (_txByDay[k] ?? const {}).values, (_ttxByDay[k] ?? const {}).values, allProducts);
  }

  /// تقرير فترة: يمر فقط على أيام الفترة عبر فهرس الأيام
  PeriodReport report(String from, String to) {
    final shopTx = <ShopTx>[];
    final trTx = <TraderTx>[];
    final n = parseDay(to).difference(parseDay(from)).inDays;
    if (n <= 400) {
      for (var i = 0; i <= n; i++) {
        final d = shiftDay(from, i);
        shopTx.addAll((_txByDay[d] ?? const {}).values);
        trTx.addAll((_ttxByDay[d] ?? const {}).values);
      }
    } else {
      shopTx.addAll(_shopTxs.values);
      trTx.addAll(_traderTxs.values);
    }
    return buildReport(
      from: from,
      to: to,
      shops: _shops.values.toList(),
      shopTxs: shopTx,
      traderTxs: trTx,
      expenses: _expenses.values,
    );
  }

  /// أقدم يوم فيه بيانات
  String? get firstDay {
    String? f;
    for (final k in _txByDay.keys) {
      if ((_txByDay[k]?.isNotEmpty ?? false) && (f == null || k.compareTo(f) < 0)) f = k;
    }
    return f;
  }

  // ================================================================ تصدير واستيراد

  int get recordCount =>
      _shops.length + _products.length + _traders.length + _shopTxs.length + _traderTxs.length + _expenses.length;

  Map<String, Object?> toJsonMap() => {
    'app': kAppId,
    'version': kSchemaVersion,
    'createdAt': DateTime.now().toIso8601String(),
    'settings': {'currency': currency, 'distributorName': distributorName},
    'shops': [for (final s in _shops.values) s.toMap()],
    'products': [for (final p in _products.values) p.toMap()],
    'traders': [for (final t in _traders.values) t.toMap()],
    'shopTxs': [for (final t in _shopTxs.values) t.toMap()],
    'traderTxs': [for (final t in _traderTxs.values) t.toMap()],
    'expenses': [for (final e in _expenses.values) e.toMap()],
  };

  String exportJson() => jsonEncode(toJsonMap());

  /// يستورد بيانات (من نسخة احتياطية). replace=true يمسح الحالي أولاً.
  /// الكتابة مجمّعة (putAll) لكل صندوق: أسرع بعشرات المرات من put لكل سجل.
  Future<int> importMap(Map doc, {required bool replace}) async {
    if (doc['app'] != kAppId) {
      throw const FormatException('هذا ليس ملف نسخة احتياطية من حساب الموزع');
    }
    final v = (doc['version'] as num?)?.toInt() ?? 1;
    if (v > kSchemaVersion) {
      throw const FormatException('النسخة من إصدار أحدث من التطبيق. حدّث التطبيق أولاً.');
    }
    // تحقّق كامل قبل لمس أي بيانات: لو فشل التحويل لا يتغير شيء
    Map<String, Map<String, Object?>> conv(String key, Map<String, Object?> Function(Map) f) => {
      for (final m in (doc[key] as List?) ?? const []) (m as Map)['id'] as String: f(m),
    };
    final shops = conv('shops', (m) => Shop.fromMap(m).toMap());
    final products = conv('products', (m) => Product.fromMap(m).toMap());
    final traders = conv('traders', (m) => Trader.fromMap(m).toMap());
    final shopTxs = conv('shopTxs', (m) => ShopTx.fromMap(m).toMap());
    final traderTxs = conv('traderTxs', (m) => TraderTx.fromMap(m).toMap());
    final expenses = conv('expenses', (m) => Expense.fromMap(m).toMap());

    if (replace) {
      await Future.wait([for (final b in _dataBoxes) b.clear()]);
    }
    await Future.wait([
      _shopsBox.putAll(shops),
      _productsBox.putAll(products),
      _tradersBox.putAll(traders),
      _shopTxBox.putAll(shopTxs),
      _traderTxBox.putAll(traderTxs),
      _expBox.putAll(expenses),
    ]);
    final settings = doc['settings'];
    if (settings is Map) {
      for (final k in ['currency', 'distributorName']) {
        if (settings[k] is String && (settings[k] as String).isNotEmpty) await _meta.put(k, settings[k]);
      }
    }
    if (_tradersBox.isEmpty) {
      final t = Trader(id: newId(), name: 'التاجر');
      await _tradersBox.put(t.id, t.toMap());
    }
    await _stamp();
    _loadAll();
    _changed();
    return shops.length + products.length + traders.length + shopTxs.length + traderTxs.length + expenses.length;
  }

  Future<int> importJson(String text, {required bool replace}) async {
    final doc = jsonDecode(text.trim());
    if (doc is! Map) throw const FormatException('ملف غير صالح');
    return importMap(doc, replace: replace);
  }

  List<Box> get _dataBoxes => [_shopsBox, _productsBox, _tradersBox, _shopTxBox, _traderTxBox, _expBox];

  Future<void> wipeAll() async {
    await Future.wait([for (final b in _dataBoxes) b.clear()]);
    final t = Trader(id: newId(), name: 'التاجر');
    await _tradersBox.put(t.id, t.toMap());
    await _stamp();
    _loadAll();
    _changed();
  }

  /// يضمن كتابة كل شيء على القرص (يُستدعى عند ذهاب التطبيق للخلفية)
  Future<void> flush() async {
    await Future.wait([
      for (final b in [..._dataBoxes, _meta]) b.flush(),
    ]);
  }

  // ================================================================ بيانات مبدئية / تجريبية

  bool get isEmpty => _shops.isEmpty && _products.isEmpty;

  Future<void> addStarterProducts() async {
    var order = _products.values.fold<int>(0, (m, p) => p.sortOrder > m ? p.sortOrder : m);
    final batch = <String, Map<String, Object?>>{};
    for (final i in starterProducts) {
      final p = Product(id: newId(), name: i.$1, unit: i.$2, sellPrice: i.$3, costPrice: i.$4, sortOrder: ++order);
      _products[p.id] = p;
      batch[p.id] = p.toMap();
    }
    _productsSorted = null;
    _changed();
    await _productsBox.putAll(batch);
  }

  /// يملأ التطبيق ببيانات أسبوع لتجربة البرنامج (يمسح الحالي)
  Future<void> loadDemo({int days = 7}) async {
    final doc = buildDemoData(days: days, newId: newId);
    await importMap(doc, replace: true);
  }

  void attachLifecycle() => WidgetsBinding.instance.addObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) refreshToday();
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) unawaited(flush());
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

  /// النقد الفعلي من حركة اليوم
  int get cash => collected - traderPaid - expenses;
}
