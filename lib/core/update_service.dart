/// update_service.dart — التحديث عن بُعد من داخل التطبيق.
///
/// الملف: `<dist-repo>/hisab-almozaw3/update.json` (يُولَّد بـ `tool/make_update_json.py`)
/// ```json
/// { "version": "2.2.0", "build": 220,
///   "versionCodes": { "arm64": 2220, "armv7": 1220 },
///   "apks": { "arm64": { "url": "…-arm64.apk", "sha256": "…64 hex…", "size": 0 },
///             "armv7": { "url": "…-armv7.apk", "sha256": "…", "size": 0 } },
///   "notes": "ما الجديد", "publishedAt": "2026-11-15", "minSupportedBuild": 0 }
/// ```
///
/// 1. نعرف versionCode والمعمارية **للـ APK المثبّت** من `nativeLibraryDir` (…/lib/arm64)
///    وليس من معمارية الجهاز (قد يُثبَّت armv7 على جهاز arm64).
/// 2. متاح ⇔ `versionCodes[abi] > versionCode المثبّت`.
/// 3. التنزيل إلى `cache/updates/` مع شريط تقدّم ثم **تحقق SHA-256 إلزامي**؛ عدم التطابق = حذف ورفض.
/// 4. التثبيت عبر مثبّت النظام (FileProvider). أندرويد 8+ يطلب "تثبيت تطبيقات غير معروفة" مرة واحدة.
/// 5. فحص تلقائي مرة كل 24 ساعة + زر يدوي. "تخطّي هذا الإصدار" لا يزعج المستخدم به مرة أخرى.
/// 6. `minSupportedBuild` > المثبّت ⇒ تحديث **إلزامي** (لا زر "لاحقاً").
///
/// الأمان: أندرويد نفسه يرفض APK بتوقيع مختلف؛ وSHA-256 يمنع ملفاً ناقصاً أو معدّلاً.
library;

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../data/store.dart';
import 'remote_config.dart';

@immutable
class UpdateApk {
  const UpdateApk({required this.url, required this.sha256, this.size = 0});
  final Uri url;
  final String sha256;
  final int size;

  static UpdateApk? tryParse(Object? v) {
    if (v is! Map) return null;
    final u = Uri.tryParse('${v['url'] ?? ''}');
    final h = '${v['sha256'] ?? ''}'.trim().toLowerCase();
    if (u == null || u.scheme != 'https' || !RegExp(r'^[0-9a-f]{64}$').hasMatch(h)) return null;
    final s = v['size'];
    return UpdateApk(url: u, sha256: h, size: s is num ? s.toInt() : 0);
  }
}

@immutable
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.build,
    required this.versionCodes,
    required this.apks,
    this.notes = '',
    this.publishedAt = '',
    this.minSupportedBuild = 0,
  });
  final String version;
  final int build;
  final Map<String, int> versionCodes;
  final Map<String, UpdateApk> apks;
  final String notes;
  final String publishedAt;
  final int minSupportedBuild;

  static UpdateInfo? tryParse(Object? v) {
    if (v is! Map) return null;
    try {
      int i(Object? x) => x is num ? x.toInt() : int.parse('$x');
      final vc = <String, int>{};
      (v['versionCodes'] as Map?)?.forEach((k, x) => vc['$k'] = i(x));
      final apks = <String, UpdateApk>{};
      (v['apks'] as Map?)?.forEach((k, x) {
        final a = UpdateApk.tryParse(x);
        if (a != null) apks['$k'] = a;
      });
      final version = '${v['version'] ?? ''}'.trim();
      if (version.isEmpty || vc.isEmpty || apks.isEmpty) return null;
      return UpdateInfo(
        version: version,
        build: i(v['build'] ?? 0),
        versionCodes: vc,
        apks: apks,
        notes: '${v['notes'] ?? ''}',
        publishedAt: '${v['publishedAt'] ?? ''}',
        minSupportedBuild: i(v['minSupportedBuild'] ?? 0),
      );
    } catch (_) {
      return null;
    }
  }
}

@immutable
class InstalledInfo {
  const InstalledInfo({
    required this.versionCode,
    required this.versionName,
    required this.abi,
    this.sdkInt = 0,
    this.model = '',
    this.deviceName = '',
  });
  final int versionCode;
  final String versionName;
  final String abi; // arm64 | armv7 | x86_64 | ''
  final int sdkInt;

  /// الشركة والموديل (للوحة الأجهزة فقط)
  final String model;

  /// الاسم الذي سمّى به المستخدم جهازه (الإعدادات ← حول الهاتف، أو اسم البلوتوث)
  final String deviceName;

  /// رقم البناء N من versionCode (Flutter split-per-abi: 1000×ABI + N)
  int get build => versionCode % 1000;
}

enum UpdateStatus { upToDate, available, offline, invalid, unsupported }

@immutable
class UpdateCheck {
  const UpdateCheck(this.status, {this.info, this.installed, this.message = ''});
  final UpdateStatus status;
  final UpdateInfo? info;
  final InstalledInfo? installed;
  final String message;

  bool get available => status == UpdateStatus.available;
  UpdateApk? get apk => info?.apks[installed?.abi ?? ''];

  /// تحديث إلزامي: النسخة المثبّتة أقدم من أقل نسخة مدعومة
  bool get mandatory => available && (installed?.build ?? 0) < (info?.minSupportedBuild ?? 0);
}

class UpdateService extends ChangeNotifier {
  UpdateService(this.store, {RemoteFetcher? fetcher, http.Client? client})
    : fetcher = fetcher ?? RemoteFetcher(),
      client = client ?? http.Client();

  final Store store;
  final RemoteFetcher fetcher;
  final http.Client client;

  static const file = 'update.json';
  static const checkEvery = Duration(hours: 24);
  static const _ch = MethodChannel('app.update');
  static const _kLast = 'upd_last_check';
  static const _kSkipped = 'upd_skipped_code';

  @visibleForTesting
  static Future<dynamic> Function(String method, [dynamic args])? debugInvoke;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  UpdateCheck? last;
  bool checking = false;

  /// تقدّم التنزيل 0..1 (null = لا تنزيل)
  final ValueNotifier<double?> progress = ValueNotifier(null);

  static Future<dynamic> _invoke(String m, [dynamic args]) =>
      debugInvoke != null ? debugInvoke!(m, args) : _ch.invokeMethod(m, args);

  static Future<InstalledInfo?> installed() async {
    try {
      final m = await _invoke('info');
      if (m is! Map) return null;
      return InstalledInfo(
        versionCode: (m['versionCode'] as num?)?.toInt() ?? 0,
        versionName: '${m['versionName'] ?? ''}',
        abi: abiKey('${m['nativeLibDir'] ?? ''}', '${m['abi'] ?? ''}'),
        sdkInt: (m['sdkInt'] as num?)?.toInt() ?? 0,
        model: '${m['model'] ?? ''}',
        deviceName: '${m['deviceName'] ?? ''}'.trim(),
      );
    } catch (_) {
      return null;
    }
  }

  /// المعمارية من مجلد مكتبات الـ APK المثبّت (الأدق) وإلا من معمارية الجهاز
  static String abiKey(String nativeLibDir, String deviceAbi) {
    final parts = nativeLibDir.split('/').where((s) => s.isNotEmpty).toList();
    final d = parts.isEmpty ? '' : parts.last;
    const byDir = {'arm64': 'arm64', 'arm': 'armv7', 'x86_64': 'x86_64', 'x86': 'x86'};
    const byAbi = {'arm64-v8a': 'arm64', 'armeabi-v7a': 'armv7', 'armeabi': 'armv7', 'x86_64': 'x86_64', 'x86': 'x86'};
    return byDir[d] ?? byAbi[deviceAbi] ?? '';
  }

  /// المقارنة الصافية (قابلة للاختبار)
  static UpdateCheck compare(UpdateInfo? info, InstalledInfo? inst) {
    if (info == null) return const UpdateCheck(UpdateStatus.invalid, message: 'ملف التحديث غير صالح');
    if (inst == null || inst.abi.isEmpty) {
      return UpdateCheck(UpdateStatus.unsupported, info: info, installed: inst, message: 'تعذّر تحديد النسخة المثبّتة');
    }
    final target = info.versionCodes[inst.abi];
    if (target == null || info.apks[inst.abi] == null) {
      return UpdateCheck(
        UpdateStatus.unsupported,
        info: info,
        installed: inst,
        message: 'لا يوجد إصدار لهذا النوع من الجوالات (${inst.abi})',
      );
    }
    if (target > inst.versionCode) {
      return UpdateCheck(UpdateStatus.available, info: info, installed: inst, message: 'الإصدار ${info.version} متاح');
    }
    return UpdateCheck(
      UpdateStatus.upToDate,
      info: info,
      installed: inst,
      message: 'لديك آخر إصدار (${inst.versionName})',
    );
  }

  Future<UpdateCheck> check() async {
    if (checking) return last ?? const UpdateCheck(UpdateStatus.offline);
    checking = true;
    notifyListeners();
    try {
      final inst = await installed();
      final remote = await fetcher.fetch(file, deviceId: store.meta<String>('device_id'));
      if (remote == null || remote.notFound) {
        last = UpdateCheck(UpdateStatus.offline, installed: inst, message: 'لا يمكن الوصول لخادم التحديث الآن');
      } else {
        last = compare(UpdateInfo.tryParse(remote.data), inst);
      }
      await store.putMetaSilently({_kLast: DateTime.now().millisecondsSinceEpoch});
      return last!;
    } finally {
      checking = false;
      notifyListeners();
    }
  }

  DateTime? get lastCheck {
    final ms = store.meta<int>(_kLast);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static bool isCheckDue(DateTime? last, {DateTime? now}) =>
      last == null || (now ?? DateTime.now()).difference(last) >= checkEvery;

  /// فحص تلقائي هادئ: يُرجع النتيجة فقط إن كان هناك تحديث يستحق الإظهار
  Future<UpdateCheck?> autoCheck() async {
    if (!supported || !isCheckDue(lastCheck)) return null;
    final r = await check();
    if (!r.available) return null;
    final skipped = store.meta<int>(_kSkipped);
    final code = r.info!.versionCodes[r.installed!.abi];
    if (!r.mandatory && skipped != null && skipped == code) return null;
    return r;
  }

  Future<void> skip(UpdateCheck r) async {
    final code = r.info?.versionCodes[r.installed?.abi ?? ''];
    if (code != null) await store.putMetaSilently({_kSkipped: code});
  }

  // ---------------------------------------------------------------- التنزيل والتثبيت

  static Future<Directory> _dir() async {
    final d = Directory('${(await getTemporaryDirectory()).path}/updates');
    await d.create(recursive: true);
    return d;
  }

  Future<String> download(UpdateApk apk) async {
    final d = await _dir();
    final f = File('${d.path}/${apk.url.pathSegments.last}');
    if (await f.exists() && await sha256File(f) == apk.sha256) return f.path;
    progress.value = 0;
    try {
      final res = await client.send(http.Request('GET', apk.url)).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw UpdateException('فشل التنزيل (HTTP ${res.statusCode})');
      final total = res.contentLength ?? apk.size;
      final sink = f.openWrite();
      var got = 0;
      try {
        await for (final chunk in res.stream) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) progress.value = (got / total).clamp(0.0, 1.0);
        }
      } finally {
        await sink.close();
      }
      if (await sha256File(f) != apk.sha256) {
        await f.delete();
        throw const UpdateException('الملف المنزَّل لا يطابق البصمة المنشورة. أُلغي التثبيت حمايةً لك.');
      }
      return f.path;
    } on UpdateException {
      rethrow;
    } catch (_) {
      if (await f.exists()) await f.delete();
      throw const UpdateException('تعذّر التنزيل. تحقّق من الإنترنت وأعد المحاولة.');
    } finally {
      progress.value = null;
    }
  }

  static Future<String> sha256File(File f) async => (await sha256.bind(f.openRead()).first).toString();

  static Future<bool> canInstall() async {
    try {
      return await _invoke('canInstall') == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openInstallSettings() async {
    try {
      await _invoke('openInstallSettings');
    } catch (_) {}
  }

  static Future<void> install(String path) async {
    try {
      await _invoke('install', {'path': path});
    } on PlatformException catch (e) {
      throw UpdateException('تعذّر فتح المثبّت: ${e.message}');
    }
  }

  /// حذف ملفات التحديث القديمة (عند كل تشغيل)
  static Future<void> cleanup() async {
    if (!supported) return;
    try {
      await for (final e in (await _dir()).list()) {
        if (e is File) await e.delete();
      }
    } catch (_) {}
  }
}

class UpdateException implements Exception {
  const UpdateException(this.message);
  final String message;
  @override
  String toString() => message;
}
