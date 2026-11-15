// قياس فعلي: حجم ملفات Hive وذاكرة Dart لعدد سجلات معروف. يطبع جدولاً (لا يفشل إلا لو تجاوز الحدود).
import 'dart:io';

import 'package:distributor/data/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final days in [30, 90, 365]) {
    test('ذاكرة وتخزين: $days يوم', () async {
      final tmp = await Directory.systemTemp.createTemp('mem');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (_) async => tmp.path,
      );
      final rss0 = ProcessInfo.currentRss;
      final store = Store();
      await store.init();
      await store.loadDemo(days: days);
      await store.flush();
      final sw = Stopwatch()..start();
      for (final s in store.shops) {
        store.balanceOf(s);
        store.dayOf(s);
      }
      final balUs = sw.elapsedMicroseconds;
      final rss1 = ProcessInfo.currentRss;
      final json = store.exportJson();
      var disk = 0;
      final files = <String, int>{};
      await for (final f in tmp.list(recursive: true)) {
        if (f is File && f.path.endsWith('.hive')) {
          final n = await f.length();
          disk += n;
          files[f.uri.pathSegments.last] = n;
        }
      }
      final n = store.recordCount;
      // ignore: avoid_print
      print(
        'MEM|$days|$n|${store.shops.length}|$disk|${(disk / n).toStringAsFixed(0)}|${json.length}|'
        '${((rss1 - rss0) / 1024).toStringAsFixed(0)}|$balUs|$files',
      );
      expect(disk / n, lessThan(2048));
      await Hive.close();
      await tmp.delete(recursive: true);
    });
  }
}
