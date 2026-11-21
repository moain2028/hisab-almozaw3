/// remote_config.dart — مكان واحد لعناوين التحكم عن بُعد (ترخيص + تحديث + نبض الجهاز).
///
/// **منذ 2.5.0** المصدر الأساسي منصة «صفحة المنشورات» على الدومين:
///   `https://api.alabbasi.uk/v1/apps/hisab-almozaw3/{update.json,license.json}`
///   `POST https://api.alabbasi.uk/v1/apps/hisab-almozaw3/ping`  (تسجيل الجهاز + القفل الفردي)
/// والاحتياط (إن تعطّلت المنصة) مستودع GitHub العام كما في ≤2.4.0.
/// المنصة وتوثيقها: github.com/moain2028/alabbasi-publish (خاص).
///
/// نفس نمط منظومة الضيافة (MoTechSys/diafa-apps):
///   مستودع عام للتوزيع ← مجلد لهذا التطبيق ← license.json + update.json
///
///   `github.com/{owner}/{repo}/{folder}/license.json`
///   `github.com/{owner}/{repo}/{folder}/update.json`
///
/// ⚠️ هذه القيم تُقرأ حرفياً من كل نسخة مثبّتة. تغييرها بعد النشر = إصدار جديد إلزامي.
/// ⚠️ مستودع التوزيع يبقى **عاماً** حتى تنتقل كل الأجهزة إلى ≥2.5.0 (النسخ القديمة تقرأ منه فقط).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

class RemoteConfig {
  static const owner = 'moain2028';
  static const repo = 'hisab-almozaw3-dist';
  static const branch = 'main';
  static const folder = 'hisab-almozaw3';

  /// منصة النشر (المصدر الأساسي منذ 2.5.0)
  static const platformHost = 'api.alabbasi.uk';
  static const appId = 'hisab-almozaw3';
  static Uri platformUri(String file) => Uri.https(platformHost, '/v1/apps/$appId/$file');
  static Uri get pingUri => Uri.https(platformHost, '/v1/apps/$appId/ping');

  /// الاحتياط: GitHub Contents API (بلا كاش CDN)، والاحتياطي raw (كاش حتى 5 دقائق)
  static Uri apiUri(String file) =>
      Uri.https('api.github.com', '/repos/$owner/$repo/contents/$folder/$file', {'ref': branch});
  static Uri rawUri(String file) => Uri.https('raw.githubusercontent.com', '/$owner/$repo/$branch/$folder/$file');

  /// صفحة التطبيق للعملاء (على الدومين؛ لا روابط GitHub في الواجهة أبداً)
  static Uri get downloadsPage => Uri.https('downloads.alabbasi.uk', '/app/$appId');
  static Uri platformPath(String path) => Uri.https(platformHost, '/v1/apps/$appId/$path');
}

/// رد النبض: هل هذا الجهاز مسموح (القفل الفردي من لوحة admin.alabbasi.uk)
class PingResult {
  const PingResult({
    required this.deviceActive,
    this.message = '',
    this.commands = const [],
    this.deviceCode = false,
    this.appActive = true,
    this.latest,
    this.canonicalId,
    this.updateBlocked = false,
  });
  final bool deviceActive;
  final String message;

  /// التطبيق كله مفعّل في اللوحة (إيقافه = قفل فوري لكل الأجهزة، يُفتح بالكود العام أو من اللوحة)
  final bool appActive;

  /// آخر إصدار منشور (منذ 2.7.0): التطبيق يعرف بالتحديث مع كل نبض بلا طلب إضافي
  final LatestRelease? latest;

  /// المعرّف المعتمد من الخادم (إن كان هذا الجهاز مسجّلاً سابقاً بمعرّف آخر: إعادة تثبيت)
  final String? canonicalId;

  /// التحديث موقوف لهذا الجهاز أو للكل أو خارج النشر التدريجي
  final bool updateBlocked;

  /// أوامر معلّقة من اللوحة: [{id, type: message|backup, payload}]
  final List<RemoteCommand> commands;

  /// المدير أنشأ كوداً لمرة واحدة لهذا الجهاز (يُقبل من شاشة القفل)
  final bool deviceCode;
}

/// آخر إصدار كما يعلنه النبض. `mandatoryFor(build)` = التحديث إجباري لهذه النسخة.
@immutable
class LatestRelease {
  const LatestRelease({required this.version, required this.build, this.minSupportedBuild = 0, this.notes = ''});
  final String version;
  final int build;
  final int minSupportedBuild;
  final String notes;
  bool newerThan(int installed) => build > installed;
  bool mandatoryFor(int installed) => build > installed && installed < minSupportedBuild;
  static LatestRelease? tryParse(Object? v) {
    if (v is! Map || v['build'] is! num || v['version'] is! String) return null;
    return LatestRelease(
      version: v['version'] as String,
      build: (v['build'] as num).toInt(),
      minSupportedBuild: (v['minSupportedBuild'] as num?)?.toInt() ?? 0,
      notes: '${v['notes'] ?? ''}',
    );
  }
}

/// أمر من لوحة المنصة (منذ 2.6.0)
class RemoteCommand {
  const RemoteCommand(this.id, this.type, this.payload);
  final int id;
  final String type;
  final Map<String, dynamic> payload;
  static RemoteCommand? tryParse(Object? v) {
    if (v is! Map) return null;
    final id = v['id'];
    if (id is! num || v['type'] is! String) return null;
    final p = v['payload'];
    return RemoteCommand(
      id.toInt(),
      v['type'] as String,
      p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{},
    );
  }
}

/// نتيجة جلب ملف عن بُعد
class RemoteFile {
  RemoteFile.ok(this.data) : notFound = false;
  RemoteFile.notFound() : data = null, notFound = true;
  final Map<String, dynamic>? data;
  final bool notFound;
}

/// جلب JSON بلا كاش: المنصة أولاً، ثم GitHub API (حد 60 طلب/ساعة)، ثم الملف الخام.
/// 404 من المنصة لا يُعتبر «حذفاً» — نرجع لـ GitHub (الحذف المقصود يُقرأ من GitHub فقط).
/// يُرجع null عند انقطاع الشبكة أو ملف تالف (= "لا نعرف"، لا قفل خاطئ أبداً).
class RemoteFetcher {
  RemoteFetcher([http.Client? client]) : client = client ?? http.Client();
  http.Client client;

  static const _noCache = {'Cache-Control': 'no-cache, no-store, max-age=0', 'Pragma': 'no-cache'};
  static const timeout = Duration(seconds: 8);

  Future<RemoteFile?> fetch(String file, {String? deviceId}) async {
    // 0) منصة النشر (?device= يطبّق إيقاف التحديث والنشر التدريجي لهذا الجهاز)
    try {
      final u = RemoteConfig.platformUri(file).replace(
        queryParameters: {
          't': '${DateTime.now().millisecondsSinceEpoch}',
          if (deviceId != null && deviceId.isNotEmpty) 'device': deviceId,
        },
      );
      final res = await client.get(u, headers: _noCache).timeout(timeout);
      if (res.statusCode == 200) return RemoteFile.ok(_obj(utf8.decode(res.bodyBytes)));
    } catch (_) {
      // شبكة / JSON تالف → GitHub
    }
    // 1) Contents API
    try {
      final res = await client
          .get(RemoteConfig.apiUri(file), headers: {..._noCache, 'Accept': 'application/vnd.github+json'})
          .timeout(timeout);
      if (res.statusCode == 200) {
        final meta = jsonDecode(utf8.decode(res.bodyBytes));
        final b64 = '${meta is Map ? meta['content'] ?? '' : ''}'.replaceAll(RegExp(r'\s'), '');
        if (b64.isNotEmpty) return RemoteFile.ok(_obj(utf8.decode(base64Decode(b64))));
      }
      if (res.statusCode == 404) return RemoteFile.notFound();
    } catch (_) {
      // 403 حد الطلبات / شبكة / JSON تالف → نجرّب الخام
    }
    // 2) الملف الخام
    try {
      final u = RemoteConfig.rawUri(file).replace(queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'});
      final res = await client.get(u, headers: _noCache).timeout(timeout);
      if (res.statusCode == 200) return RemoteFile.ok(_obj(utf8.decode(res.bodyBytes)));
      if (res.statusCode == 404) return RemoteFile.notFound();
    } catch (_) {}
    return null;
  }

  /// نبض الجهاز: يسجّله في المنصة ويُرجع حالة القفل الفردي.
  /// null = لا نعرف (شبكة/خطأ خادم) ⇒ لا يتغيّر شيء. لا يقفل بسبب الشبكة أبداً.
  Future<PingResult?> ping(Map<String, Object?> body) async {
    try {
      final res = await client
          .post(RemoteConfig.pingUri, headers: {'content-type': 'application/json'}, body: jsonEncode(body))
          .timeout(timeout);
      if (res.statusCode != 200) return null;
      final j = _obj(utf8.decode(res.bodyBytes));
      final dev = j['deviceActive'];
      if (dev is! bool) return null;
      final raw = j['commands'];
      final cmds = (raw is List ? raw : const []).map(RemoteCommand.tryParse).whereType<RemoteCommand>().toList();
      return PingResult(
        deviceActive: dev,
        message: '${j['message'] ?? ''}',
        commands: cmds,
        deviceCode: j['deviceCode'] == true,
        appActive: j['appActive'] != false,
        latest: LatestRelease.tryParse(j['latest']),
        canonicalId: j['deviceId'] is String ? j['deviceId'] as String : null,
        updateBlocked: j['updateBlocked'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// POST JSON إلى المنصة. يُرجع الرد أو null (شبكة/خطأ). لا يرمي استثناءات.
  Future<Map<String, dynamic>?> post(String path, Map<String, Object?> body, {Duration? wait}) async {
    try {
      final res = await client
          .post(RemoteConfig.platformPath(path), headers: {'content-type': 'application/json'}, body: jsonEncode(body))
          .timeout(wait ?? timeout);
      if (res.statusCode != 200) return null;
      return _obj(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
  }

  static Map<String, dynamic> _obj(String body) {
    final v = jsonDecode(body);
    if (v is Map<String, dynamic>) return v;
    throw const FormatException('not an object');
  }
}
