import 'dart:io' show gzip;
import 'dart:convert';

import 'package:distributor/data/backup_service.dart';
import 'package:distributor/data/demo_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  var n = 0;
  String id() => 'id${n++}';

  test('ترميز ثم فك: نفس البيانات بالضبط', () {
    final data = buildDemoData(days: 30, newId: id);
    final bytes = BackupService.encode(data);
    final back = BackupService.decode(bytes);
    expect(jsonEncode(back), jsonEncode(data));
    // الضغط يجب أن يوفّر مساحة كبيرة
    final raw = utf8.encode(jsonEncode(data)).length;
    expect(bytes.length, lessThan(raw ~/ 3));
  });

  test('ملف تالف يُرفض ولا يُسترجع', () {
    final data = buildDemoData(days: 3, newId: id);
    final env = jsonDecode(utf8.decode(GZipHelper.unzip(BackupService.encode(data)))) as Map;
    env['payload'] = (env['payload'] as String).replaceFirst('بقالة', 'XXXX');
    final tampered = utf8.encode(jsonEncode(env));
    expect(() => BackupService.decode(tampered), throwsFormatException);
  });

  test('يقبل JSON خام من النسخ القديمة (نسخ كنص)', () {
    final data = buildDemoData(days: 2, newId: id);
    final back = BackupService.decode(utf8.encode(jsonEncode(data)));
    expect(back['app'], 'hisab_almozaw3');
  });

  test('نص عشوائي يُرفض', () {
    expect(() => BackupService.decode(utf8.encode('hello')), throwsFormatException);
  });
}

class GZipHelper {
  static List<int> unzip(List<int> b) => gzip.decode(b);
}
