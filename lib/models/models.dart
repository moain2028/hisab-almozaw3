/// نماذج البيانات. كل نموذج يتحول إلى Map بسيط ليُخزَّن في Hive ويُصدَّر في النسخ الاحتياطي.
library;

int _int(Object? v) => (v as num?)?.round() ?? 0;
double _dbl(Object? v) => (v as num?)?.toDouble() ?? 0;
String _str(Object? v, [String d = '']) => (v as String?) ?? d;
bool _bool(Object? v) => v == true || v == 1;

// ------------------------------------------------------------------ البقالة

class Shop {
  Shop({
    required this.id,
    required this.name,
    this.owner = '',
    this.phone = '',
    this.area = '',
    this.notes = '',
    this.openingBalance = 0,
    this.routeOrder = 0,
    this.archived = false,
    required this.createdAt,
  });

  final String id;
  String name;
  String owner;
  String phone;
  String area;
  String notes;

  /// دين سابق على البقالة قبل بدء استخدام البرنامج (موجب = عليه)
  int openingBalance;

  /// ترتيب البقالة في خط السير
  int routeOrder;
  bool archived;
  final int createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'owner': owner,
        'phone': phone,
        'area': area,
        'notes': notes,
        'openingBalance': openingBalance,
        'routeOrder': routeOrder,
        'archived': archived,
        'createdAt': createdAt,
      };

  factory Shop.fromMap(Map m) => Shop(
        id: m['id'] as String,
        name: _str(m['name']),
        owner: _str(m['owner']),
        phone: _str(m['phone']),
        area: _str(m['area']),
        notes: _str(m['notes']),
        openingBalance: _int(m['openingBalance']),
        routeOrder: _int(m['routeOrder']),
        archived: _bool(m['archived']),
        createdAt: _int(m['createdAt']),
      );
}

// ------------------------------------------------------------------ الصنف

class Product {
  Product({
    required this.id,
    required this.name,
    this.unit = 'كرتون',
    this.sellPrice = 0,
    this.costPrice = 0,
    this.sortOrder = 0,
    this.active = true,
  });

  final String id;
  String name;
  String unit;

  /// سعر البيع للبقالة
  int sellPrice;

  /// سعر الشراء من التاجر
  int costPrice;
  int sortOrder;
  bool active;

  int get margin => sellPrice - costPrice;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'unit': unit,
        'sellPrice': sellPrice,
        'costPrice': costPrice,
        'sortOrder': sortOrder,
        'active': active,
      };

  factory Product.fromMap(Map m) => Product(
        id: m['id'] as String,
        name: _str(m['name']),
        unit: _str(m['unit'], 'كرتون'),
        sellPrice: _int(m['sellPrice']),
        costPrice: _int(m['costPrice']),
        sortOrder: _int(m['sortOrder']),
        active: m['active'] == null ? true : _bool(m['active']),
      );
}

// ------------------------------------------------------------------ التاجر

class Trader {
  Trader({
    required this.id,
    required this.name,
    this.phone = '',
    this.openingBalance = 0,
    this.archived = false,
  });

  final String id;
  String name;
  String phone;

  /// مبلغ سابق للتاجر عليك قبل بدء البرنامج (موجب = لك عليه أن تدفعه)
  int openingBalance;
  bool archived;

  Map<String, Object?> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'openingBalance': openingBalance,
        'archived': archived,
      };

  factory Trader.fromMap(Map m) => Trader(
        id: m['id'] as String,
        name: _str(m['name']),
        phone: _str(m['phone']),
        openingBalance: _int(m['openingBalance']),
        archived: _bool(m['archived']),
      );
}

// ------------------------------------------------------------------ سطر صنف

/// سطر داخل عملية (توزيع، مرتجع، استلام). يحفظ اسم الصنف والسعر وقت العملية،
/// لذلك تغيير سعر الصنف لاحقاً لا يغيّر الحسابات القديمة.
class TxLine {
  const TxLine({
    required this.productId,
    required this.name,
    required this.unit,
    required this.qty,
    required this.price,
    required this.cost,
  });

  final String productId;
  final String name;
  final String unit;
  final double qty;

  /// السعر المعتمد في هذه العملية (بيع للبقالة، أو شراء في عمليات التاجر)
  final int price;

  /// تكلفة الوحدة وقت العملية (لحساب الربح)
  final int cost;

  int get total => (qty * price).round();
  int get totalCost => (qty * cost).round();

  Map<String, Object?> toMap() => {
        'productId': productId,
        'name': name,
        'unit': unit,
        'qty': qty,
        'price': price,
        'cost': cost,
      };

  factory TxLine.fromMap(Map m) => TxLine(
        productId: _str(m['productId']),
        name: _str(m['name']),
        unit: _str(m['unit']),
        qty: _dbl(m['qty']),
        price: _int(m['price']),
        cost: _int(m['cost']),
      );
}

int linesTotal(List<TxLine> lines) => lines.fold(0, (a, l) => a + l.total);

// ------------------------------------------------------------------ حركات البقالة

enum ShopTxType {
  /// عطاء / توزيع بضاعة (يزيد الدين)
  delivery,

  /// مرتجع بضاعة تالفة أو منتهية (ينقص الدين)
  returned,

  /// تحصيل نقدي (ينقص الدين)
  payment,

  /// خصم / مسامحة (ينقص الدين)
  discount,
}

extension ShopTxTypeX on ShopTxType {
  String get label => switch (this) {
        ShopTxType.delivery => 'عطاء',
        ShopTxType.returned => 'مرتجع',
        ShopTxType.payment => 'تحصيل',
        ShopTxType.discount => 'خصم',
      };

  /// +1 يزيد ما على البقالة، -1 ينقصه
  int get sign => this == ShopTxType.delivery ? 1 : -1;
  bool get hasLines =>
      this == ShopTxType.delivery || this == ShopTxType.returned;
}

class ShopTx {
  ShopTx({
    required this.id,
    required this.shopId,
    required this.type,
    required this.day,
    required this.createdAt,
    this.lines = const [],
    int amount = 0,
    this.note = '',
  }) : _amount = amount;

  final String id;
  final String shopId;
  final ShopTxType type;

  /// اليوم التجاري yyyy-MM-dd
  final String day;
  final int createdAt;
  final List<TxLine> lines;
  final int _amount;
  final String note;

  /// قيمة العملية (موجبة دائماً)
  int get amount => type.hasLines ? linesTotal(lines) : _amount;

  /// أثرها على رصيد البقالة
  int get effect => amount * type.sign;

  Map<String, Object?> toMap() => {
        'id': id,
        'shopId': shopId,
        'type': type.name,
        'day': day,
        'createdAt': createdAt,
        'lines': [for (final l in lines) l.toMap()],
        'amount': _amount,
        'note': note,
      };

  factory ShopTx.fromMap(Map m) => ShopTx(
        id: m['id'] as String,
        shopId: _str(m['shopId']),
        type: ShopTxType.values.firstWhere(
          (t) => t.name == m['type'],
          orElse: () => ShopTxType.payment,
        ),
        day: _str(m['day']),
        createdAt: _int(m['createdAt']),
        lines: [
          for (final l in (m['lines'] as List?) ?? const []) TxLine.fromMap(l as Map),
        ],
        amount: _int(m['amount']),
        note: _str(m['note']),
      );
}

// ------------------------------------------------------------------ حركات التاجر

enum TraderTxType {
  /// استلام بضاعة الصباح (يزيد ما عليك للتاجر)
  pickup,

  /// إرجاع بضاعة للتاجر (ينقص ما عليك)
  returned,

  /// دفع نقدي للتاجر (ينقص ما عليك)
  payment,
}

extension TraderTxTypeX on TraderTxType {
  String get label => switch (this) {
        TraderTxType.pickup => 'استلام بضاعة',
        TraderTxType.returned => 'إرجاع للتاجر',
        TraderTxType.payment => 'دفعة للتاجر',
      };
  int get sign => this == TraderTxType.pickup ? 1 : -1;
  bool get hasLines => this != TraderTxType.payment;
}

class TraderTx {
  TraderTx({
    required this.id,
    required this.traderId,
    required this.type,
    required this.day,
    required this.createdAt,
    this.lines = const [],
    int amount = 0,
    this.note = '',
  }) : _amount = amount;

  final String id;
  final String traderId;
  final TraderTxType type;
  final String day;
  final int createdAt;
  final List<TxLine> lines;
  final int _amount;
  final String note;

  int get amount => type.hasLines ? linesTotal(lines) : _amount;
  int get effect => amount * type.sign;

  Map<String, Object?> toMap() => {
        'id': id,
        'traderId': traderId,
        'type': type.name,
        'day': day,
        'createdAt': createdAt,
        'lines': [for (final l in lines) l.toMap()],
        'amount': _amount,
        'note': note,
      };

  factory TraderTx.fromMap(Map m) => TraderTx(
        id: m['id'] as String,
        traderId: _str(m['traderId']),
        type: TraderTxType.values.firstWhere(
          (t) => t.name == m['type'],
          orElse: () => TraderTxType.payment,
        ),
        day: _str(m['day']),
        createdAt: _int(m['createdAt']),
        lines: [
          for (final l in (m['lines'] as List?) ?? const []) TxLine.fromMap(l as Map),
        ],
        amount: _int(m['amount']),
        note: _str(m['note']),
      );
}

// ------------------------------------------------------------------ المصاريف

class Expense {
  Expense({
    required this.id,
    required this.day,
    required this.amount,
    required this.category,
    this.note = '',
    required this.createdAt,
  });

  final String id;
  final String day;
  final int amount;
  final String category;
  final String note;
  final int createdAt;

  Map<String, Object?> toMap() => {
        'id': id,
        'day': day,
        'amount': amount,
        'category': category,
        'note': note,
        'createdAt': createdAt,
      };

  factory Expense.fromMap(Map m) => Expense(
        id: m['id'] as String,
        day: _str(m['day']),
        amount: _int(m['amount']),
        category: _str(m['category'], 'أخرى'),
        note: _str(m['note']),
        createdAt: _int(m['createdAt']),
      );
}

const expenseCategories = ['بنزين', 'صيانة', 'أكل', 'تالف', 'أجرة', 'أخرى'];
