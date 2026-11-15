/// فهرس محاسبي سريع لكل حساب (بقالة أو تاجر).
///
/// المشكلة التي يحلها: الحساب الساذج يمسح كل الحركات في كل مرة تُرسم فيها الشاشة
/// (O(n) لكل بقالة → O(n × بقالات) لكل إطار). بعد سنتين من العمل (~60 ألف حركة)
/// يصبح هذا مئات الملّي ثانية على جوال متوسط.
///
/// الحل: لكل حساب قائمة مرتّبة بالتاريخ + مجموع تراكمي (prefix sums).
///   - الرصيد الحالي: O(1)
///   - الرصيد قبل يوم معيّن: بحث ثنائي O(log n)
///   - حركات يوم معيّن: O(log n + k)
/// ويُعاد بناء فهرس الحساب الذي تغيّر فقط (إبطال انتقائي)، وليس كل البيانات.
library;

import '../models/models.dart';
import 'ledger.dart';

/// أي حركة لها يوم ووقت إنشاء وأثر على الرصيد
abstract interface class LedgerEntry {
  String get day;
  int get createdAt;
  int get effect;
}

int compareEntries(LedgerEntry a, LedgerEntry b) {
  final c = a.day.compareTo(b.day);
  return c != 0 ? c : a.createdAt.compareTo(b.createdAt);
}

class AccountIndex<T extends LedgerEntry> {
  AccountIndex._(this.opening, this.entries, this._prefix);

  /// يبني الفهرس من حركات حساب واحد (بأي ترتيب)
  factory AccountIndex.build(int opening, Iterable<T> txs) {
    final list = txs.toList(growable: false)..sort(compareEntries);
    final prefix = List<int>.filled(list.length + 1, 0);
    for (var i = 0; i < list.length; i++) {
      prefix[i + 1] = prefix[i] + list[i].effect;
    }
    return AccountIndex._(opening, list, prefix);
  }

  final int opening;

  /// الحركات مرتبة تصاعدياً (يوم، ثم وقت الإنشاء)
  final List<T> entries;

  /// _prefix[i] = مجموع أثر أول i حركة
  final List<int> _prefix;

  int get length => entries.length;

  /// الرصيد الحالي O(1)
  int get balance => opening + _prefix[entries.length];

  /// الرصيد بعد الحركة رقم i (للكشف الجاري)
  int balanceAfter(int i) => opening + _prefix[i + 1];

  /// أول موضع يومه >= day
  int lowerBound(String day) {
    var lo = 0, hi = entries.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (entries[mid].day.compareTo(day) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// أول موضع يومه > day
  int upperBound(String day) {
    var lo = 0, hi = entries.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (entries[mid].day.compareTo(day) <= 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// الرصيد في بداية يوم (قبل أي حركة فيه) O(log n)
  int balanceBefore(String day) => opening + _prefix[lowerBound(day)];

  /// الرصيد في نهاية يوم O(log n)
  int balanceAtEndOf(String day) => opening + _prefix[upperBound(day)];

  /// حركات يوم واحد O(log n + k)
  List<T> on(String day) => entries.sublist(lowerBound(day), upperBound(day));
}

/// ملخص يوم لبقالة من الفهرس (نفس نتيجة shopDay الساذجة لكن O(log n + k))
ShopDay shopDayFromIndex(AccountIndex<ShopTx> idx, String day) {
  final lo = idx.lowerBound(day);
  final hi = idx.upperBound(day);
  var delivered = 0, returned = 0, paid = 0, discount = 0;
  for (var i = lo; i < hi; i++) {
    final t = idx.entries[i];
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
  return ShopDay(
    before: idx.balanceBefore(day),
    delivered: delivered,
    returned: returned,
    paid: paid,
    discount: discount,
  );
}

/// آخر يوم دفع: مسح من النهاية (عادةً خطوات قليلة)
String? lastPaymentFromIndex(AccountIndex<ShopTx> idx) {
  for (var i = idx.length - 1; i >= 0; i--) {
    if (idx.entries[i].type == ShopTxType.payment) return idx.entries[i].day;
  }
  return null;
}
