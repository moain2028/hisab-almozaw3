/// أدوات تنسيق الأرقام والتواريخ والكميات.
library;

String two(int n) => n.toString().padLeft(2, '0');

/// تاريخ اليوم كنص ثابت yyyy-MM-dd (يُستخدم كمفتاح لليوم التجاري)
String dayKey(DateTime d) => '${d.year}-${two(d.month)}-${two(d.day)}';
String todayKey() => dayKey(DateTime.now());

DateTime parseDay(String s) {
  final p = s.split('-');
  return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
}

String shiftDay(String key, int days) {
  final d = parseDay(key);
  return dayKey(DateTime(d.year, d.month, d.day + days));
}

const _weekDays = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const _months = [
  'يناير',
  'فبراير',
  'مارس',
  'أبريل',
  'مايو',
  'يونيو',
  'يوليو',
  'أغسطس',
  'سبتمبر',
  'أكتوبر',
  'نوفمبر',
  'ديسمبر',
];

String weekDayName(String key) => _weekDays[parseDay(key).weekday - 1];

/// "السبت 15 نوفمبر"
String arDay(String key) {
  final d = parseDay(key);
  return '${_weekDays[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';
}

/// "15/11"
String shortDay(String key) {
  final d = parseDay(key);
  return '${d.day}/${d.month}';
}

/// "اليوم" / "أمس" / التاريخ
String relativeDay(String key) {
  final t = todayKey();
  if (key == t) return 'اليوم';
  if (key == shiftDay(t, -1)) return 'أمس';
  return arDay(key);
}

String timeOf(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${two(d.minute)} ${d.hour < 12 ? 'ص' : 'م'}';
}

/// 12500 -> 12,500
String money(num v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return neg ? '-$b' : b.toString();
}

/// 0.25 -> ¼ ، 1.5 -> 1½ ، 2 -> 2 ، 1.2 -> 1.2
String qtyText(double q) {
  final neg = q < 0;
  final a = q.abs();
  final whole = a.floor();
  final frac = a - whole;
  String out;
  if (frac.abs() < 0.001) {
    out = '$whole';
  } else if ((frac - 0.25).abs() < 0.001) {
    out = whole == 0 ? '¼' : '$whole¼';
  } else if ((frac - 0.5).abs() < 0.001) {
    out = whole == 0 ? '½' : '$whole½';
  } else if ((frac - 0.75).abs() < 0.001) {
    out = whole == 0 ? '¾' : '$whole¾';
  } else {
    out = a.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }
  final r = neg ? '-$out' : out;
  // عزل اتجاه النص حتى لا ينقلب 1½ إلى ½1 داخل النص العربي
  return RegExp(r'\d[¼½¾]').hasMatch(r) ? '\u2066$r\u2069' : r;
}

/// يحوّل الأرقام العربية/الفارسية إلى إنجليزية ويحذف الفواصل والمسافات
String normalizeDigits(String s) {
  const ar = '٠١٢٣٤٥٦٧٨٩';
  const fa = '۰۱۲۳۴۵۶۷۸۹';
  final b = StringBuffer();
  for (final ch in s.split('')) {
    var i = ar.indexOf(ch);
    if (i < 0) i = fa.indexOf(ch);
    b.write(i >= 0 ? '$i' : ch);
  }
  return b
      .toString()
      .replaceAll(',', '')
      .replaceAll('٬', '')
      .replaceAll('٫', '.')
      .replaceAll('،', '')
      .replaceAll(' ', '');
}

int? parseMoney(String s) {
  final n = double.tryParse(normalizeDigits(s));
  return n?.round();
}

double? parseQty(String s) {
  final t = normalizeDigits(
    s.replaceAll('\u2066', '').replaceAll('\u2069', ''),
  ).replaceAll('¼', '.25').replaceAll('½', '.5').replaceAll('¾', '.75');
  return double.tryParse(t.startsWith('.') ? '0$t' : t);
}

double roundQty(double v) => (v * 100).round() / 100;
