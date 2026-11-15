/// license_service.dart — الترخيص / القفل عن بُعد.
///
/// الملف: `<dist-repo>/hisab-almozaw3/license.json`
/// ```json
/// { "active": true, "code": "HISAB-0000", "message": "نص يظهر عند القفل" }
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
/// - **البيانات لا تُمس أبداً**: القفل يمنع الواجهة فقط، والنسخ الاحتياطي يبقى يعمل.
/// - الحالة تُحفظ في صندوق Hive `meta` (نفس تخزين التطبيق، لا حزمة إضافية).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/store.dart';
import 'remote_config.dart';

@immutable
class LicenseState {
  const LicenseState({required this.allowed, this.message = '', this.codeAccepted = true, this.offline = false});
  final bool allowed;
  final String message;

  /// هل يوجد كود يمكن قبوله أصلاً (false عند حذف الملف)
  final bool codeAccepted;
  final bool offline;
}

class LicenseService extends ChangeNotifier {
  LicenseService(this.store, {RemoteFetcher? fetcher}) : fetcher = fetcher ?? RemoteFetcher();

  final Store store;
  final RemoteFetcher fetcher;
  static const file = 'license.json';
  static const recheckEvery = Duration(minutes: 10);

  static const _kBlocked = 'lic_blocked';
  static const _kMessage = 'lic_message';
  static const _kCode = 'lic_code';
  static const _kActivated = 'lic_activated';
  static const _kDeleted = 'lic_deleted';
  static const _kSeen = 'lic_seen';
  static const _kLastCheck = 'lic_last_check';

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

  /// المنطق الكامل (قابل للاختبار عبر fetcher وهمي)
  Future<LicenseState> check() async {
    final remote = await fetcher.fetch(file);
    if (remote == null) return _fromCache(offline: true);

    if (remote.notFound) {
      // أمان: لا نقفل بسبب ملف لم يُرفع بعد
      if (store.meta<bool>(_kSeen) != true) return _fromCache(offline: true);
      const msg = 'انتهى ترخيص هذه النسخة. يرجى التواصل مع المطوّر.';
      await _put({_kBlocked: true, _kDeleted: true, _kMessage: msg, _kCode: '', _kLastCheck: _now});
      return const LicenseState(allowed: false, message: msg, codeAccepted: false);
    }

    final d = remote.data!;
    final active = d['active'] == true;
    final msg = '${d['message'] ?? ''}';
    final code = '${d['code'] ?? ''}'.trim().toUpperCase();
    await _put({_kSeen: true, _kDeleted: false, _kMessage: msg, _kCode: code, _kLastCheck: _now});

    if (active) {
      await _put({_kBlocked: false});
      return LicenseState(allowed: true, message: msg);
    }
    final saved = (store.meta<String>(_kActivated) ?? '').toUpperCase();
    final unlocked = code.isNotEmpty && saved == code;
    await _put({_kBlocked: !unlocked});
    return LicenseState(allowed: unlocked, message: msg, codeAccepted: code.isNotEmpty);
  }

  /// إدخال كود التفعيل. يتحقق مقابل الملف الحي إن أمكن، وإلا آخر كود معروف.
  Future<bool> unlock(String input) async {
    final remote = await fetcher.fetch(file);
    if (remote != null && remote.notFound) return false;
    if (remote?.data != null) {
      await _put({_kCode: '${remote!.data!['code'] ?? ''}'.trim().toUpperCase()});
    }
    final code = store.meta<String>(_kCode) ?? '';
    if (code.isEmpty) return false;
    final ok = input.trim().toUpperCase() == code;
    if (ok) {
      await _put({_kActivated: code, _kBlocked: false});
      _state = const LicenseState(allowed: true);
      notifyListeners();
    }
    return ok;
  }

  LicenseState _fromCache({bool offline = false}) {
    final blocked = store.meta<bool>(_kBlocked) ?? false;
    final deleted = store.meta<bool>(_kDeleted) ?? false;
    return LicenseState(
      allowed: !blocked,
      message: store.meta<String>(_kMessage) ?? '',
      codeAccepted: !deleted && (store.meta<String>(_kCode) ?? '').isNotEmpty,
      offline: offline,
    );
  }

  static int get _now => DateTime.now().millisecondsSinceEpoch;
  Future<void> _put(Map<String, Object?> m) => store.putMetaSilently(m);
}
