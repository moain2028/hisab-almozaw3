import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'store.dart';

/// معلومات ملف نسخة احتياطية موجود على الجهاز
class BackupFile {
  BackupFile(this.file, this.modified, this.size);
  final File file;
  final DateTime modified;
  final int size;
  String get name => file.uri.pathSegments.last;
  bool get isAuto => name.contains('-auto-');
}

/// خدمة النسخ الاحتياطي المحلي — بنفس فكرة واتساب.
///
/// **المكان**: `Android/media/com.hisabalmozaw3.distributor/Backups/`
///   - مجلد خارجي (External Media) يظهر في مدير الملفات ويمكن نسخه للكمبيوتر.
///   - لا يحتاج أي إذن تخزين على أي إصدار أندرويد.
///   - **يبقى بعد حذف التطبيق** (مثل مجلد WhatsApp/Databases) فيمكن الاسترجاع بعد إعادة التثبيت.
///   - احتياطاً لو لم يتوفر: مجلد التطبيق الخارجي ثم الداخلي.
///
/// **الصيغة**: `.hisab` = ملف JSON مضغوط GZip داخل غلاف يحتوي بصمة SHA-256
/// للتحقق من سلامة الملف قبل الاسترجاع (لا نسترجع ملفاً تالفاً أبداً).
///
/// **الكتابة الذرية**: نكتب في ملف مؤقت ثم نعيد التسمية؛ لو انقطع الجهاز أثناء الكتابة
/// تبقى النسخة السابقة سليمة.
///
/// **التدوير**: نسخة تلقائية واحدة يومياً تُستبدل خلال اليوم، ويُحتفظ بآخر [keepDaily]
/// يوماً + كل النسخ اليدوية حتى [keepManual].
class BackupService {
  BackupService(this.store);

  final Store store;
  static const ext = '.hisab';
  static const keepDaily = 14;
  static const keepManual = 20;
  static const _debounce = Duration(seconds: 8);

  Directory? _dir;
  Timer? _timer;
  bool _running = false;
  String? lastError;

  /// متاح على الجوال فقط (الويب لا يملك نظام ملفات)
  static bool get supported => !kIsWeb;

  // ================================================================ المجلد

  Future<Directory> directory() async {
    if (_dir != null) return _dir!;
    Directory? base;
    if (Platform.isAndroid) {
      // Android/data/<pkg>/files → نصعد إلى Android/ ثم ننزل إلى media/<pkg>
      final ext = await getExternalStorageDirectory();
      if (ext != null) {
        final parts = ext.path.split('/');
        final i = parts.indexOf('Android');
        if (i > 0 && i + 2 < parts.length) {
          final pkg = parts[i + 2];
          base = Directory([...parts.sublist(0, i + 1), 'media', pkg].join('/'));
        } else {
          base = ext;
        }
      }
    }
    base ??= await getApplicationDocumentsDirectory();
    var dir = Directory('${base.path}/Backups');
    try {
      await dir.create(recursive: true);
      // اختبار صلاحية الكتابة
      final probe = File('${dir.path}/.probe');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
    } catch (_) {
      dir = Directory('${(await getApplicationDocumentsDirectory()).path}/Backups');
      await dir.create(recursive: true);
    }
    return _dir = dir;
  }

  /// مسار مقروء للمستخدم مثل: Android/media/com.../Backups
  Future<String> displayPath() async {
    final p = (await directory()).path;
    final i = p.indexOf('/Android/');
    return i >= 0 ? p.substring(i + 1) : p;
  }

  // ================================================================ التلقائي

  /// يُستدعى بعد كل تعديل: ينتظر هدوء التعديلات ثم ينسخ (لا ينسخ مع كل ضغطة زر)
  void scheduleAuto() {
    if (!supported || !store.autoBackup) return;
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(runAuto()));
  }

  /// نسخة تلقائية عند فتح التطبيق أو ذهابه للخلفية إن وُجدت تغييرات غير محفوظة
  Future<void> runAuto() async {
    if (!supported || !store.autoBackup || !store.hasUnbackedChanges || store.recordCount == 0) return;
    await create(auto: true);
  }

  /// ينفّذ أي نسخة معلّقة فوراً (عند الخروج من التطبيق)
  Future<void> flushPending() async {
    if (_timer?.isActive ?? false) {
      _timer!.cancel();
      await runAuto();
    }
  }

  // ================================================================ إنشاء

  Future<BackupFile?> create({bool auto = false}) async {
    if (!supported || _running) return null;
    _running = true;
    try {
      final dir = await directory();
      final now = DateTime.now();
      final stamp = _stamp(now);
      final name = auto ? 'hisab-auto-${stamp.substring(0, 10)}$ext' : 'hisab-$stamp$ext';
      final bytes = encode(store.toJsonMap());
      final tmp = File('${dir.path}/.$name.tmp');
      await tmp.writeAsBytes(bytes, flush: true);
      final target = File('${dir.path}/$name');
      final f = await tmp.rename(target.path);
      await store.markBackup();
      await _rotate(dir);
      lastError = null;
      return BackupFile(f, now, bytes.length);
    } catch (e) {
      lastError = '$e';
      if (kDebugMode) debugPrint('backup failed: $e');
      return null;
    } finally {
      _running = false;
    }
  }

  // ================================================================ القائمة والتدوير

  Future<List<BackupFile>> list() async {
    if (!supported) return const [];
    final dir = await directory();
    final out = <BackupFile>[];
    await for (final e in dir.list()) {
      if (e is File && e.path.endsWith(ext)) {
        final st = await e.stat();
        out.add(BackupFile(e, st.modified, st.size));
      }
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  Future<void> _rotate(Directory dir) async {
    final all = await list();
    final autos = all.where((b) => b.isAuto).toList();
    final manual = all.where((b) => !b.isAuto).toList();
    for (final b in [...autos.skip(keepDaily), ...manual.skip(keepManual)]) {
      try {
        await b.file.delete();
      } catch (_) {}
    }
  }

  Future<void> delete(BackupFile b) => b.file.delete();

  // ================================================================ استرجاع

  /// يقرأ ويتحقق من الملف ويُرجع البيانات (بدون تطبيقها)
  Future<Map> read(File f) async => decode(await f.readAsBytes());

  Future<int> restore(File f, {required bool replace}) async {
    final doc = await read(f);
    // نسخة أمان من الوضع الحالي قبل الاستبدال (لو أخطأ المستخدم)
    if (replace && store.recordCount > 0) {
      await _safetyCopy();
    }
    return store.importMap(doc, replace: replace);
  }

  Future<void> _safetyCopy() async {
    final dir = await directory();
    final f = File('${dir.path}/hisab-before-restore-${_stamp(DateTime.now())}$ext');
    await f.writeAsBytes(encode(store.toJsonMap()), flush: true);
  }

  // ================================================================ الصيغة

  /// غلاف: {"format":"hisab-backup","sha256":"…","payload":<البيانات>} ثم GZip
  static List<int> encode(Map<String, Object?> data) {
    final payload = jsonEncode(data);
    final env = jsonEncode({
      'format': 'hisab-backup',
      'v': 1,
      'sha256': sha256.convert(utf8.encode(payload)).toString(),
      'payload': payload,
    });
    return GZipEncoder().encode(utf8.encode(env))!;
  }

  /// يقبل: ملف .hisab المضغوط، أو JSON خام (نسخ قديمة/نص منسوخ)
  static Map decode(List<int> bytes) {
    String text;
    if (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
      text = utf8.decode(GZipDecoder().decodeBytes(bytes));
    } else {
      text = utf8.decode(bytes);
    }
    final obj = jsonDecode(text.trim());
    if (obj is Map && obj['format'] == 'hisab-backup') {
      final payload = obj['payload'] as String;
      final sum = sha256.convert(utf8.encode(payload)).toString();
      if (sum != obj['sha256']) {
        throw const FormatException('الملف تالف (فشل التحقق من السلامة)');
      }
      final data = jsonDecode(payload);
      if (data is! Map) throw const FormatException('ملف غير صالح');
      return data;
    }
    if (obj is Map) return obj;
    throw const FormatException('ملف غير صالح');
  }

  static String _stamp(DateTime d) {
    String t(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${t(d.month)}-${t(d.day)}_${t(d.hour)}${t(d.minute)}${t(d.second)}';
  }

  void dispose() => _timer?.cancel();
}
