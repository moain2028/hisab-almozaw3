/// license_service.dart — الترخيص / القفل عن بُعد.
///
/// الملف: `<dist-repo>/hisab-almozaw3/license.json`
/// ```json
/// { "active": true, "codeHash": "<sha256>", "message": "نص يظهر عند القفل" }
/// ```
/// **الكود نفسه لا يُنشر أبداً**: الملف العام يحمل `codeHash = sha256("hisab-almozaw3:" + CODE)` فقط،
/// والكود الحقيقي محفوظ في المستودع الخاص. يولَّد بـ `tool/license_hash.py CODE`.
/// (حقل `code` النصي ما زال مقبولاً للتوافق، ويُحوَّل لهاش فوراً ولا يُخزَّن نصاً.)
/// ```
/// ```
///
/// | التعديل في الملف        | النتيجة في التطبيق                                       |
/// |-------------------------|----------------------------------------------------------|
/// | `active: true`          | يفتح فوراً بلا كود (ويمسح أي قفل سابق)                   |
/// | `active: false`         | يُقفل ويطلب الكود؛ الكود الصحيح يُحفظ ويفتح               |
/// | تغيير `code`            | يُقفل من فعّل بالكود القديم                              |
/// | حذف الملف (404)         | قفل نهائي بلا كود — **فقط** إن سبق رؤية الملف مرة         |
/// | لا إنترنت / ملف تالف    | آخر حالة معروفة (لا قفل خاطئ؛ أول تشغيل بلا نت = مسموح)   |
///
/// - الفحص: عند التشغيل + عند الرجوع للتطبيق (فاصل أدنى 10 دقائق).
///
/// **القفل الفردي (منذ 2.5.0)**: مع كل فحص يُرسل نبض إلى منصة النشر
/// (`POST api.alabbasi.uk/v1/apps/hisab-almozaw3/ping`) بمعرّف عشوائي ثابت للجهاز.
/// المدير يقفل/يفتح الجهاز من `admin.alabbasi.uk`. قفل الجهاز **لا يفتحه كود التفعيل**
/// (وإلا فقد معناه)؛ يُفتح من اللوحة فقط. لا شبكة = آخر حالة معروفة للجهاز.
/// - **البيانات لا تُمس أبداً**: القفل يمنع الواجهة فقط، والنسخ الاحتياطي يبقى يعمل.
/// - الحالة تُحفظ في صندوق Hive `meta` (نفس تخزين التطبيق، لا حزمة إضافية).
library;

import 'dart:async';

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/store.dart';
import 'remote_config.dart';
import 'update_service.dart';

@immutable
class LicenseState {
  const LicenseState({
    required this.allowed,
    this.message = '',
    this.codeAccepted = true,
    this.offline = false,
    this.deviceLocked = false,
  });
  final bool allowed;
  final String message;

  /// هل يوجد كود يمكن قبوله أصلاً (false عند حذف الملف)
  final bool codeAccepted;
  final bool offline;

  /// مقفول من لوحة الأجهزة (لا يُفتح بالكود)
  final bool deviceLocked;
}

/// بيانات الجهاز للنبض (null = لا نبض، مثل معاينة الويب)
typedef DeviceInfoProvider = Future<Map<String, Object?>?> Function();

class LicenseService extends ChangeNotifier {
  LicenseService(this.store, {RemoteFetcher? fetcher, DeviceInfoProvider? deviceInfo})
    : fetcher = fetcher ?? RemoteFetcher(),
      deviceInfo = deviceInfo ?? _androidDeviceInfo;

  final Store store;
  final RemoteFetcher fetcher;
  final DeviceInfoProvider deviceInfo;
  static const deviceLockedMessage = 'تم إيقاف التطبيق على هذا الجهاز. تواصل مع المطوّر لإعادة تفعيله.';
  static const file = 'license.json';
  static const recheckEvery = Duration(minutes: 10);

  static const _kBlocked = 'lic_blocked';
  static const _kMessage = 'lic_message';
  static const _kCode = 'lic_code';
  static const _kActivated = 'lic_activated';
  static const _kDeleted = 'lic_deleted';
  static const _kSeen = 'lic_seen';
  static const _kLastCheck = 'lic_last_check';
  static const _kDevBlocked = 'dev_blocked';
  static const _kDevCode = 'dev_code';
  static const kDeviceId = 'device_id';

  /// أوامر وصلت مع آخر نبض (تعالجها CommandService)
  final ValueNotifier<List<RemoteCommand>> commands = ValueNotifier(const []);
  bool _deviceCode = false;

  /// المدير أنشأ كود تفعيل لهذا الجهاز تحديداً (يظهر حقل الكود في شاشة القفل)
  bool get deviceCodeAvailable => _deviceCode || (store.meta<bool>(_kDevCode) ?? false);

  LicenseState? _state;
  DateTime? _lastCheck;
  bool _checking = false;

  LicenseState get state => _state ?? _fromCache();
  bool get allowed => state.allowed;
  DateTime? get lastCheck {
    final ms = store.meta<int>(_kLastCheck);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  /// يعرض آخر حالة محفوظة فوراً (بلا انتظار الشبكة) ثم يحدّث في الخلفية
  /// لا ينتظر الشبكة أبداً: الإقلاع لا يتأخر حتى بدون إنترنت
  Future<void> init() async {
    deviceId();
    _state = _fromCache();
    notifyListeners();
    unawaited(refresh());
  }

  Future<void> onResumed() async {
    final l = _lastCheck;
    if (l != null && DateTime.now().difference(l) < recheckEvery) return;
    await refresh();
  }

  Future<LicenseState> refresh() async {
    if (_checking) return state;
    _checking = true;
    try {
      _state = await check();
      _lastCheck = DateTime.now();
      notifyListeners();
      return _state!;
    } catch (e) {
      if (kDebugMode) debugPrint('license refresh: $e');
      return state;
    } finally {
      _checking = false;
    }
  }

  /// أول 12 حرفاً من معرّف الجهاز للعرض (قراءة فقط، لا يكتب أثناء البناء). فارغ قبل أول تشغيل.
  String get shortDeviceId {
    final id = store.meta<String>(kDeviceId) ?? '';
    return id.length >= 12 ? id.substring(0, 12) : id;
  }

  /// معرّف عشوائي ثابت لهذا التثبيت (48 حرف hex). لا IMEI ولا معرّفات نظام.
  String deviceId() {
    final cur = store.meta<String>(kDeviceId);
    if (cur != null && RegExp(r'^[0-9a-f]{48}$').hasMatch(cur)) return cur;
    final r = Random.secure();
    final id = List.generate(24, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    unawaited(store.putMetaSilently({kDeviceId: id}));
    return id;
  }

  static Future<Map<String, Object?>?> _androidDeviceInfo() async {
    if (!UpdateService.supported) return null;
    final i = await UpdateService.installed();
    if (i == null) return null;
    return {
      'version': i.versionName,
      'build': i.build,
      'abi': i.abi,
      'sdk': i.sdkInt,
      'model': i.model,
      if (i.deviceName.isNotEmpty) 'deviceName': i.deviceName,
    };
  }

  Future<PingResult?> _ping() async {
    try {
      final info = await deviceInfo();
      if (info == null) return null;
      return await fetcher.ping({'deviceId': deviceId(), ...info});
    } catch (_) {
      return null;
    }
  }

  /// المنطق الكامل (قابل للاختبار عبر fetcher وهمي): الترخيص العام ثم قفل الجهاز فوقه
  Future<LicenseState> check() async {
    final r = await Future.wait<Object?>([fetcher.fetch(file), _ping()]);
    final base = await _checkLicense(r[0] as RemoteFile?);
    final p = r[1] as PingResult?;
    if (p != null) {
      _deviceCode = p.deviceCode;
      await _put({_kDevBlocked: !p.deviceActive, _kDevCode: p.deviceCode});
      if (p.commands.isNotEmpty) commands.value = p.commands;
    }
    return _withDevice(base);
  }

  LicenseState _withDevice(LicenseState base) {
    if (store.meta<bool>(_kDevBlocked) != true) return base;
    return LicenseState(
      allowed: false,
      message: deviceLockedMessage,
      codeAccepted: deviceCodeAvailable,
      offline: base.offline,
      deviceLocked: true,
    );
  }

  Future<LicenseState> _checkLicense(RemoteFile? remote) async {
    if (remote == null) return _licenseFromCache(offline: true);

    if (remote.notFound) {
      // أمان: لا نقفل بسبب ملف لم يُرفع بعد
      if (store.meta<bool>(_kSeen) != true) return _licenseFromCache(offline: true);
      const msg = 'انتهى ترخيص هذه النسخة. يرجى التواصل مع المطوّر.';
      await _put({_kBlocked: true, _kDeleted: true, _kMessage: msg, _kCode: '', _kLastCheck: _now});
      return const LicenseState(allowed: false, message: msg, codeAccepted: false);
    }

    final d = remote.data!;
    final active = d['active'] == true;
    final msg = '${d['message'] ?? ''}';
    final code = codeHashOf(d);
    await _put({_kSeen: true, _kDeleted: false, _kMessage: msg, _kCode: code, _kLastCheck: _now});

    if (active) {
      await _put({_kBlocked: false});
      return LicenseState(allowed: true, message: msg);
    }
    final saved = store.meta<String>(_kActivated) ?? '';
    final unlocked = code.isNotEmpty && saved == code;
    await _put({_kBlocked: !unlocked});
    return LicenseState(allowed: unlocked, message: msg, codeAccepted: code.isNotEmpty);
  }

  /// إدخال كود التفعيل. يتحقق مقابل الملف الحي إن أمكن، وإلا آخر كود معروف.
  Future<bool> unlock(String input) async {
    // جهاز مقفول من اللوحة: يُقبل فقط كود هذا الجهاز (لمرة واحدة) ويتحقق منه الخادم
    if (store.meta<bool>(_kDevBlocked) == true) {
      if (input.trim().isEmpty) return false;
      final r = await fetcher.post('activate', {'deviceId': deviceId(), 'code': input.trim()});
      if (r == null || r['ok'] != true) return false;
      await _put({_kDevBlocked: false, _kDevCode: false});
      _deviceCode = false;
      _state = await check();
      notifyListeners();
      return _state!.allowed;
    }
    final remote = await fetcher.fetch(file);
    if (remote != null && remote.notFound) return false;
    if (remote?.data != null) {
      await _put({_kCode: codeHashOf(remote!.data!)});
    }
    final code = store.meta<String>(_kCode) ?? '';
    if (code.isEmpty || input.trim().isEmpty) return false;
    final ok = hashCode_(input) == code;
    if (ok) {
      await _put({_kActivated: code, _kBlocked: false});
      _state = const LicenseState(allowed: true);
      notifyListeners();
    }
    return ok;
  }

  LicenseState _fromCache({bool offline = false}) => _withDevice(_licenseFromCache(offline: offline));

  LicenseState _licenseFromCache({bool offline = false}) {
    final blocked = store.meta<bool>(_kBlocked) ?? false;
    final deleted = store.meta<bool>(_kDeleted) ?? false;
    return LicenseState(
      allowed: !blocked,
      message: store.meta<String>(_kMessage) ?? '',
      codeAccepted: !deleted && (store.meta<String>(_kCode) ?? '').isNotEmpty,
      offline: offline,
    );
  }

  /// الملح ثابت لكل تطبيق: نفس الكود في تطبيق آخر يعطي هاشاً مختلفاً
  static const salt = 'hisab-almozaw3:';

  /// هاش كود مُدخل (بلا حساسية لحالة الحروف والمسافات)
  static String hashCode_(String code) => sha256.convert(utf8.encode('$salt${code.trim().toUpperCase()}')).toString();

  /// الهاش من الملف البعيد: `codeHash` مفضّل، وإلا `code` نصي (توافق) يُحوَّل لهاش
  static String codeHashOf(Map<String, dynamic> d) {
    final h = '${d['codeHash'] ?? ''}'.trim().toLowerCase();
    if (RegExp(r'^[0-9a-f]{64}$').hasMatch(h)) return h;
    final c = '${d['code'] ?? ''}'.trim();
    return c.isEmpty ? '' : hashCode_(c);
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch;
  Future<void> _put(Map<String, Object?> m) => store.putMetaSilently(m);
}
